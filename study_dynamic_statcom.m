function out = study_dynamic_statcom(pre_case, critical_case, weak_bus, cap_MVAr, cap_bus, Vref, cfg, mpopt, results_dir)

define_constants;

if isempty(cap_bus), cap_bus = weak_bus;         end
if isempty(Vref),    Vref    = cfg.statcom_Vref; end

wrow = @(r) find(r.bus(:,BUS_I)==weak_bus,1);
crow = @(r) find(r.bus(:,BUS_I)==cap_bus,1);

[rpre,  ~] = run_pf_safe(pre_case, mpopt, cfg);
[rcrit, ~] = run_pf_safe(critical_case, mpopt, cfg);
if ~rpre.success || ~rcrit.success
    warning('study_dynamic_statcom:pf','Dynamic study skipped: no operating point.');
    out.success = false; return;
end
Vpre  = rpre.bus(wrow(rpre), VM);
Vcrit = rcrit.bus(wrow(rcrit), VM);

capbase = pre_case;
capbase.bus(crow(capbase), BS) = capbase.bus(crow(capbase), BS) + cap_MVAr;
capcrit = critical_case;
capcrit.bus(crow(capcrit), BS) = capcrit.bus(crow(capcrit), BS) + cap_MVAr;
[rcb,~] = run_pf_safe(capbase, mpopt, cfg);
[rcc,~] = run_pf_safe(capcrit, mpopt, cfg);
if rcb.success && rcc.success
    Vcap_pre = rcb.bus(wrow(rcb), VM);  Vcap_post = rcc.bus(wrow(rcc), VM);
    Vcb_pre  = rcb.bus(crow(rcb), VM);  Vcb_post  = rcc.bus(crow(rcc), VM);
    cap_ok = true;
else
    Vcap_pre = Vpre; Vcap_post = Vcrit; Vcb_pre = Vpre; Vcb_post = Vcrit;
    cap_ok = false;
    warning('study_dynamic_statcom:cap','Capacitor operating point unavailable.');
end

[statcrit, grow] = add_statcom(critical_case, weak_bus, cfg, Vref);
[rsc,~] = run_pf_safe(statcrit, mpopt, cfg);
if rsc.success
    Vstat_post = rsc.bus(wrow(rsc), VM);
    Qstat_post = rsc.gen(grow, QG);
else
    Vstat_post = Vref; Qstat_post = NaN;
end

if isfinite(Qstat_post) && abs(Qstat_post) > 1e-6
    kq = (Vstat_post - Vcrit) / Qstat_post;
    kq_source = 'calibrated to the MATPOWER STATCOM solution';
else
    probe = critical_case;
    probe.bus(wrow(probe), QD) = probe.bus(wrow(probe), QD) - cfg.dyn.Qprobe;
    [rp,~] = run_pf_safe(probe, mpopt, cfg);
    kq = (rp.bus(wrow(rp),VM) - Vcrit) / cfg.dyn.Qprobe;
    kq_source = 'small-signal probe (fallback)';
end
kq = max(kq, 1e-5);

Kp = cfg.dyn.loop_gain / kq;
Ki = cfg.dyn.Ki_ratio * Kp;
Qmin = cfg.statcom_Qmin; Qmax = cfg.statcom_Qmax;

dt = cfg.dyn.dt;
t  = (0:dt:cfg.dyn.t_end)';
N  = numel(t);
V0  = zeros(N,1); Vc = zeros(N,1); Vs = zeros(N,1); Vcb = zeros(N,1);
Qs  = zeros(N,1); Qc = zeros(N,1); Qcmd = zeros(N,1);

V0(1)  = Vpre;
Vc(1)  = Vcap_pre;
Vcb(1) = Vcb_pre;

qpre  = min(max((Vref - Vpre)/kq, Qmin), Qmax);
Vs(1) = Vpre + kq*qpre;
Qs(1) = qpre;
e0    = Vref - Vs(1);
xi    = (qpre - Kp*e0)/Ki;

for k = 1:N-1
    after = t(k) >= cfg.dyn.t_event;
    if after, Vnet = Vcrit; else, Vnet = Vpre; end

    % 1. no compensation
    V0(k+1) = V0(k) + dt*((Vnet - V0(k))/cfg.dyn.Tgrid);

    % 2. fixed capacitor, interpolated between two exact power-flow solutions
    if after, Vtc = Vcap_post; Vtb = Vcb_post; else, Vtc = Vcap_pre; Vtb = Vcb_pre; end
    Vc(k+1)  = Vc(k)  + dt*((Vtc - Vc(k)) /cfg.dyn.Tgrid);
    Vcb(k+1) = Vcb(k) + dt*((Vtb - Vcb(k))/cfg.dyn.Tgrid);
    Qc(k)    = cap_MVAr*Vcb(k)^2;

    % 3. STATCOM, PI regulator with conditional integration
    e = Vref - Vs(k);
    if abs(e) < cfg.dyn.deadband, ec = 0; else, ec = e; end
    raw = Kp*ec + Ki*xi;
    cmd = min(max(raw, Qmin), Qmax);
    Qcmd(k) = cmd;
    if (raw < Qmax && raw > Qmin) || (raw >= Qmax && ec < 0) || (raw <= Qmin && ec > 0)
        xi = xi + dt*ec;
    end
    Qs(k+1) = Qs(k) + dt*((cmd - Qs(k))/cfg.dyn.Tstat);
    Vs(k+1) = Vs(k) + dt*((Vnet + kq*Qs(k) - Vs(k))/cfg.dyn.Tgrid);
end
Qc(N) = cap_MVAr*Vcb(N)^2;
Qcmd(N) = Qcmd(N-1);

post = t >= cfg.dyn.t_event;
dip_nocomp  = min(V0(post));
dip_statcom = min(Vs(post));
dip_cap     = min(Vc(post));

tol = 0.01*abs(Vs(1));
ip  = find(post);
bad = find(abs(Vs(ip) - Vs(end)) > tol, 1, 'last');
if isempty(bad)
    settle = 0;
elseif bad < numel(ip)
    settle = t(ip(bad+1)) - cfg.dyn.t_event;
else
    settle = NaN;
end

Q_at_sag = cap_MVAr*Vcrit^2;

T = table(t, V0, Vc, Vs, Qs, Qc, Qcmd, Vcb, 'VariableNames', ...
    {'Time_s','V_NoComp_pu','V_Capacitor_pu','V_STATCOM_pu', ...
     'Q_STATCOM_MVAr','Q_Capacitor_MVAr','Qcmd_MVAr','V_CapBus_pu'});
writetable(T, fullfile(results_dir,'09_dynamic_STATCOM_data.csv'));

fig = figure('Visible','off');
plot(t,V0,'LineWidth',1.3); hold on;
plot(t,Vc,'LineWidth',1.3);
plot(t,Vs,'LineWidth',1.6);
yline(cfg.vmin_accept,'--','0.95 pu','HandleVisibility','off');
xline(cfg.dyn.t_event,':','Outage','HandleVisibility','off');
grid on; xlabel('Time (s)'); ylabel(sprintf('Bus %d Voltage (pu)',weak_bus));
title(sprintf('Dynamic Voltage Response at Bus %d', weak_bus));
legend('No compensation', sprintf('Fixed capacitor (%.1f MVAr)',cap_MVAr), ...
       sprintf('STATCOM (Vref = %.2f pu)',Vref), 'Location','southwest');
saveas(fig, fullfile(results_dir,'09_dynamic_voltage.png')); close(fig);

fig = figure('Visible','off');
plot(t,Qs,'LineWidth',1.6); hold on;
plot(t,Qc,'LineWidth',1.3);
yline(Qmax,'--','+Qmax','HandleVisibility','off');
xline(cfg.dyn.t_event,':','Outage','HandleVisibility','off');
grid on; xlabel('Time (s)'); ylabel('Reactive Power Output (MVAr)');
title('Reactive-Power Response: Controlled Source vs Fixed Bank');
legend('STATCOM (controlled)','Capacitor (Q proportional to V^2)','Location','east');
saveas(fig, fullfile(results_dir,'09_dynamic_STATCOM_Q.png')); close(fig);

fprintf('\n============ PHASE 6: DYNAMIC STATCOM (REDUCED-ORDER) ============\n');
fprintf('Both devices at bus %d (like-for-like comparison)\n', weak_bus);
fprintf('Sensitivity dV/dQ  : %.5f pu/MVAr (%s)\n', kq, kq_source);
fprintf('PI gains           : Kp = %.1f, Ki = %.1f (loop gain %.2f)\n', Kp, Ki, cfg.dyn.loop_gain);
fprintf('No compensation    : %.4f -> %.4f pu\n', Vpre, dip_nocomp);
if cap_ok
    fprintf('Capacitor          : %.4f -> %.4f pu | output %.2f -> %.2f MVAr (%+.1f%%)\n', ...
        Vcap_pre, Vc(end), Qc(1), Qc(end), 100*(Qc(end)-Qc(1))/max(Qc(1),eps));
end
fprintf('STATCOM            : %.4f -> %.4f pu | output %.2f -> %.2f MVAr\n', ...
    Vs(1), Vs(end), Qs(1), Qs(end));
fprintf('  MATPOWER steady state for comparison : %.4f pu, %.2f MVAr\n', Vstat_post, Qstat_post);
fprintf('  lowest point during the event        : %.4f pu (limit %.2f)\n', dip_statcom, cfg.vmin_accept);
fprintf('  settling to within 1%% of final       : %.2f s\n', settle);
fprintf('V-squared check    : a %.1f MVAr bank at the uncompensated post-outage\n', cap_MVAr);
fprintf('  voltage of %.4f pu delivers only %.2f MVAr, %.0f%% of nameplate.\n', ...
    Vcrit, Q_at_sag, 100*Q_at_sag/cap_MVAr);
fprintf('  A STATCOM is a controlled current source and holds its rating.\n');

out.success = true;
out.kq = kq; out.kq_source = kq_source; out.Kp = Kp; out.Ki = Ki;
out.Vpre = Vpre; out.Vcrit = Vcrit;
out.dip_nocomp = dip_nocomp; out.dip_statcom = dip_statcom; out.dip_cap = dip_cap;
out.finalV = Vs(end); out.finalQ = Qs(end);
out.Vstat_matpower = Vstat_post; out.Qstat_matpower = Qstat_post;
out.Qcap_start = Qc(1); out.Qcap_end = Qc(end); out.Q_at_sag = Q_at_sag;
out.settling_time_s = settle;
out.table = T;
end
