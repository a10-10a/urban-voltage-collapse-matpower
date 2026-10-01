function out = study_mitigations(critical_case, weak_bus, cfg, mpopt, results_dir)

define_constants;

[rcrit, Mcrit] = run_pf_safe(critical_case, mpopt, cfg);
fprintf('\n============ PHASE 5: MITIGATION SCREENING ============\n');
fprintf('Critical case: Vmin = %.4f pu at bus %d, %d buses below %.2f pu\n', ...
    Mcrit.Vmin_load, Mcrit.weak_load_bus, Mcrit.lowV_buses, cfg.vmin_accept);

capRows = [];
for b = unique([weak_bus, cfg.cap_candidate_buses])
    brow = find(critical_case.bus(:,BUS_I)==b,1);
    if isempty(brow), continue; end
    for q = cfg.cap_sizes_MVAr
        c = critical_case;
        c.bus(brow,BS) = c.bus(brow,BS) + q;      % Bs is MVAr injected at 1.0 pu
        [~,M] = run_pf_safe(c, mpopt, cfg);
        capRows(end+1,:) = [b q M.success M.Vmin_load M.Vmax_load M.Ploss_MW ...
            M.lowV_buses M.highV_buses M.in_band M.max_loading_pct M.qlim_artifact]; %#ok<AGROW>
    end
end
Tcap = array2table(capRows,'VariableNames', {'Bus','Cap_MVAr','Converged','Vmin_pu','Vmax_load_pu','Ploss_MW', ...
     'LowVBusCount','HighVBusCount','InBand','MaxLoading_pct','QlimArtifact'});
writetable(Tcap, fullfile(results_dir,'07_capacitor_screen.csv'));

good = Tcap.Converged==1 & Tcap.InBand==1 & Tcap.QlimArtifact==0;
if any(good)
    Tg = Tcap(good,:);
    [~,ord] = sortrows([Tg.Cap_MVAr, -Tg.Vmin_pu], [1 2]);   % smallest rating wins
    bestcap = Tg(ord(1),:);
    capmsg = 'minimum rating that holds every load bus inside the band';
else
    Tk = Tcap(Tcap.Converged==1 & Tcap.HighVBusCount==0,:);
    if isempty(Tk), Tk = Tcap(Tcap.Converged==1,:); end
    [~,ii] = max(Tk.Vmin_pu); bestcap = Tk(ii,:);
    capmsg = 'no rating meets the band; best achievable without over-voltage';
end

atw = Tcap.Bus==weak_bus & Tcap.Converged==1 & Tcap.InBand==1 & Tcap.QlimArtifact==0;
if any(atw)
    Tw = Tcap(atw,:); [~,iw] = min(Tw.Cap_MVAr);
    cap_at_weak = Tw.Cap_MVAr(iw);
else
    cap_at_weak = bestcap.Cap_MVAr;
end

cap_case = critical_case;
caprow   = find(cap_case.bus(:,BUS_I)==bestcap.Bus,1);
cap_case.bus(caprow,BS) = cap_case.bus(caprow,BS) + bestcap.Cap_MVAr;
[rcap, Mcap] = run_pf_safe(cap_case, mpopt, cfg);
fprintf('Capacitor : %.1f MVAr at bus %d  (%s)\n', bestcap.Cap_MVAr, bestcap.Bus, capmsg);
if bestcap.Bus ~= weak_bus
    fprintf('            best rating at the weak bus %d itself: %.1f MVAr\n', weak_bus, cap_at_weak);
end


tapRows = [];
for p = 1:size(cfg.transformer_pairs,1)
    br = find_branch_by_pair(critical_case, cfg.transformer_pairs(p,:));
    if isempty(br) || critical_case.branch(br,BR_STATUS)==0, continue; end
    tap0 = critical_case.branch(br,TAP); if tap0==0, tap0 = 1; end
    for tap = cfg.tap_values
        c = critical_case; c.branch(br,TAP) = tap;
        [~,M] = run_pf_safe(c, mpopt, cfg);
        tapRows(end+1,:) = [br c.branch(br,F_BUS) c.branch(br,T_BUS) tap tap0 M.success M.Vmin_load M.Vmax_load M.Ploss_MW M.lowV_buses M.in_band]; 
    end
end
Ttap = array2table(tapRows,'VariableNames', ...
    {'BranchRow','FromBus','ToBus','Tap','Tap_original','Converged', 'Vmin_pu','Vmax_load_pu','Ploss_MW','LowVBusCount','InBand'});
writetable(Ttap, fullfile(results_dir,'07_tap_screen.csv'));

good = Ttap.Converged==1 & Ttap.InBand==1;
if any(good)
    Tg = Ttap(good,:);
    [~,ii] = min(abs(Tg.Tap - Tg.Tap_original));   % least movement from nominal
    besttap = Tg(ii,:);
    tapmsg = 'smallest tap movement that meets the band';
else
    Tk = Ttap(Ttap.Converged==1,:);
    [~,ii] = max(Tk.Vmin_pu); besttap = Tk(ii,:);
    tapmsg = 'no tap meets the band alone; best achievable setting';
end
tap_case = critical_case;
tap_case.branch(besttap.BranchRow,TAP) = besttap.Tap;
[rtap, Mtap] = run_pf_safe(tap_case, mpopt, cfg);
fprintf('Tap       : branch %d (%d-%d) set to %.4f from %.4f  (%s)\n', besttap.BranchRow, besttap.FromBus, besttap.ToBus, besttap.Tap, besttap.Tap_original, tapmsg);

drRows = [];
for d = cfg.dr_levels
    [c, shed] = apply_demand_response(critical_case, cfg, d);
    [~,M] = run_pf_safe(c, mpopt, cfg);
    drRows(end+1,:) = [100*d shed M.success M.Vmin_load M.Vmax_load M.Ploss_MW M.lowV_buses M.in_band]; %#ok<AGROW>
end
Tdr = array2table(drRows,'VariableNames', {'DR_pct','MW_shed','Converged','Vmin_pu','Vmax_load_pu','Ploss_MW', ...
     'LowVBusCount','InBand'});
writetable(Tdr, fullfile(results_dir,'07_DR_screen.csv'));

good = Tdr.Converged==1 & Tdr.InBand==1;
if any(good)
    Tg = Tdr(good,:); [~,ii] = min(Tg.DR_pct); bestdr = Tg(ii,:);
    drmsg = 'minimum curtailment that meets the band';
else
    Tk = Tdr(Tdr.Converged==1,:); [~,ii] = max(Tk.Vmin_pu); bestdr = Tk(ii,:);
    drmsg = 'no level meets the band alone; largest tested level';
end
[dr_case, dr_shed] = apply_demand_response(critical_case, cfg, bestdr.DR_pct/100);
[rdr, Mdr] = run_pf_safe(dr_case, mpopt, cfg);
fprintf('DR        : %.0f%% on flexible load = %.1f MW shed  (%s)\n', ...
    bestdr.DR_pct, dr_shed, drmsg);
fprintf('            hospital/water buses %s protected.\n', mat2str(cfg.critical_buses));


statRows = [];
best_vref = NaN; stat_case = []; stat_grow = NaN;
for v = cfg.statcom_Vref_options
    [c, grow] = add_statcom(critical_case, weak_bus, cfg, v);
    [r,M] = run_pf_safe(c, mpopt, cfg);
    if r.success, Q = r.gen(grow,QG); else, Q = NaN; end
    hit = r.success && abs(Q - cfg.statcom_Qmax) < 1e-3;
    statRows(end+1,:) = [v M.success Q hit M.Vmin_load M.Vmax_load ...
        M.lowV_buses M.in_band M.Ploss_MW]; 
    if isnan(best_vref) && M.success && M.in_band
        best_vref = v; stat_case = c; stat_grow = grow;
    end
end
Tstat = array2table(statRows,'VariableNames', {'Vref_pu','Converged','Q_STATCOM_MVAr','AtQmax','Vmin_pu','Vmax_load_pu', ...
     'LowVBusCount','InBand','Ploss_MW'});
writetable(Tstat, fullfile(results_dir,'07_STATCOM_screen.csv'));

if isnan(best_vref)
    [~,ii] = max(statRows(:,5));
    best_vref = statRows(ii,1);
    [stat_case, stat_grow] = add_statcom(critical_case, weak_bus, cfg, best_vref);
    statmsg = 'no setpoint meets the band; best achievable';
else
    statmsg = 'lowest setpoint that meets the band';
end
[rstat, Mstat] = run_pf_safe(stat_case, mpopt, cfg);
if rstat.success, Qstat = rstat.gen(stat_grow,QG); else, Qstat = NaN; end
fprintf('STATCOM   : bus %d, Vref = %.2f pu, Q = %.2f of +/-%.0f MVAr  (%s)\n', weak_bus, best_vref, Qstat, cfg.statcom_Qmax, statmsg);


comb_case = critical_case;
comb_case.bus(caprow,BS) = comb_case.bus(caprow,BS) + bestcap.Cap_MVAr;
comb_case.branch(besttap.BranchRow,TAP) = besttap.Tap;
comb_case = apply_demand_response(comb_case, cfg, bestdr.DR_pct/100);
[rcomb, Mcomb] = run_pf_safe(comb_case, mpopt, cfg);

enh_case = apply_demand_response(critical_case, cfg, bestdr.DR_pct/100);
[enh_case, enh_grow] = add_statcom(enh_case, weak_bus, cfg, best_vref);
[renh, Menh] = run_pf_safe(enh_case, mpopt, cfg);
if renh.success, Qenh = renh.gen(enh_grow,QG); else, Qenh = NaN; end

if Mcomb.success && Mcomb.highV_buses > 0
    fprintf(['\nNOTE: stacking capacitor + tap + DR over-corrects. The fixed\n' ...
             '      capacitor cannot reduce its output once demand response has\n' ...
             '      already lowered the reactive demand, so %d load bus(es) rise\n' ...
             '      above %.2f pu (max %.4f pu). A controlled source does not\n' ...
             '      have this failure mode - see the STATCOM + DR row.\n'], ...
             Mcomb.highV_buses, cfg.vmax_accept, Mcomb.Vmax_load);
end


names = {'Critical_NoMitigation';'Capacitor';'TapControl';'DemandResponse'; 'STATCOM';'Combined_Cap_Tap_DR';'STATCOM_plus_DR'};
MM   = {Mcrit;Mcap;Mtap;Mdr;Mstat;Mcomb;Menh};
qval = [NaN;NaN;NaN;NaN;Qstat;NaN;Qenh];
det  = {'-'; sprintf('%.1f MVAr @ bus %d',bestcap.Cap_MVAr,bestcap.Bus); ...
        sprintf('tap %.4f on %d-%d',besttap.Tap,besttap.FromBus,besttap.ToBus); ...
        sprintf('%.0f%% (%.1f MW)',bestdr.DR_pct,dr_shed); ...
        sprintf('Vref %.2f pu @ bus %d',best_vref,weak_bus); ...
        'capacitor + tap + DR'; sprintf('STATCOM %.2f pu + %.0f%% DR',best_vref,bestdr.DR_pct)};

R = NaN(numel(names),8);
for k = 1:numel(names)
    M = MM{k};
    R(k,:) = [M.success M.Vmin_load M.Vmax_load M.Ploss_MW M.Qloss_MVAr ...
              M.lowV_buses M.highV_buses M.max_loading_pct];
end
Tcmp = table(names, det, R(:,1), R(:,2), R(:,3), R(:,4), R(:,5), R(:,6), R(:,7), R(:,8), qval, ...
    'VariableNames',{'Case','Setting','Converged','Vmin_pu','Vmax_load_pu','Ploss_MW', ...
    'Qloss_MVAr','LowVBusCount','HighVBusCount','MaxLoading_pct','STATCOM_Q_MVAr'});
writetable(Tcmp, fullfile(results_dir,'08_final_comparison.csv'));

fprintf('\n---- FINAL COMPARISON (critical case) ----\n');
fprintf('%-22s %-26s %8s %8s %8s %6s\n','Scheme','Setting','Vmin','Vmax','Ploss','nLowV');
for k = 1:numel(names)
    fprintf('%-22s %-26s %8.4f %8.4f %8.2f %6d\n', names{k}, det{k},R(k,2), R(k,3), R(k,4), R(k,6));
end

cases = {rcrit,rcap,rtap,rdr,rstat,rcomb,renh};
fig = figure('Visible','off'); hold on;
for k = 1:numel(cases)
    if isfield(cases{k},'success') && cases{k}.success
        plot(cases{k}.bus(:,BUS_I), cases{k}.bus(:,VM), 'LineWidth',1.2, 'DisplayName',names{k});
    end
end
yline(cfg.vmin_accept,'--','HandleVisibility','off');
yline(cfg.vmax_accept,'--','HandleVisibility','off');
grid on; xlabel('Bus Number'); ylabel('Voltage (pu)');
title('Voltage Profile: Critical Case and Mitigation Options');
legend('Location','bestoutside','Interpreter','none');
saveas(fig, fullfile(results_dir,'08_voltage_comparison.png')); close(fig);

out.bestcap = bestcap;  out.besttap = besttap;  out.bestdr = bestdr;
out.cap_at_weakbus_MVAr = cap_at_weak;
out.dr_shed_MW = dr_shed;
out.statcom_Vref = best_vref;  out.Qstat = Qstat;  out.Qenh = Qenh;
out.cap_case = cap_case; out.tap_case = tap_case; out.dr_case = dr_case;
out.stat_case = stat_case; out.combined_case = comb_case; out.enhanced_case = enh_case;
out.metrics = struct('crit',Mcrit,'cap',Mcap,'tap',Mtap,'dr',Mdr,'stat',Mstat,'comb',Mcomb,'enh',Menh);
out.table = Tcmp;
out.Tstat = Tstat;
end
