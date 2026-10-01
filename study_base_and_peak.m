function out = study_base_and_peak(cfg, mpopt, results_dir)
define_constants;
mpc = loadcase(cfg.case_name);

[r0, M0] = run_pf_safe(mpc, mpopt, cfg);
if ~r0.success
    error('study_base_and_peak:base','Base case did not solve (%s).', M0.reason);
end

fprintf('\n============ PHASE 1: BASE CASE ============\n');
fprintf('Total load        : %.1f MW, %.1f MVAr\n', sum(mpc.bus(:,PD)), sum(mpc.bus(:,QD)));
fprintf('Vmin (load buses) : %.4f pu at bus %d\n', M0.Vmin_load, M0.weak_load_bus);
fprintf('Vmax (load buses) : %.4f pu\n', M0.Vmax_load);
fprintf('Losses            : %.2f MW, %.2f MVAr\n', M0.Ploss_MW, M0.Qloss_MVAr);
fprintf('Generators at Qmax: %d of %d\n', M0.n_gen_at_Qmax, size(mpc.gen,1));
fprintf('Urban area load   : %.1f MW (%.1f%% of system)\n', ...
    sum(mpc.bus(ismember(mpc.bus(:,BUS_I),cfg.urban_buses),PD)), ...
    100*sum(mpc.bus(ismember(mpc.bus(:,BUS_I),cfg.urban_buses),PD))/sum(mpc.bus(:,PD)));

fig = figure('Visible','off');
plot(r0.bus(:,BUS_I), r0.bus(:,VM), 'o-', 'LineWidth',1.4); hold on;
yline(cfg.vmin_accept,'--','0.95 pu'); yline(cfg.vmax_accept,'--','1.05 pu');
grid on; xlabel('Bus Number'); ylabel('Voltage (pu)');
title('IEEE 30-Bus Base-Case Voltage Profile');
saveas(fig, fullfile(results_dir,'01_base_voltage.png')); close(fig);

% ---------------- system-wide stress sweep ----------------
factors = cfg.load_factors;
nb  = size(mpc.bus,1);
Vm  = NaN(numel(factors), nb);
S   = NaN(numel(factors), 10);

fprintf('\n============ PHASE 2: PEAK-DEMAND SWEEP (%s) ============\n', upper(cfg.loading_mode));
fprintf('  Load%%   Vmin    bus   nV<0.95   Ploss    Qloss   Qmargin  gens@Qmax\n');
for k = 1:numel(factors)
    c = scale_load(mpc, cfg, factors(k));
    [r, M] = run_pf_safe(c, mpopt, cfg);
    if r.success
        Vm(k,:) = r.bus(:,VM)';
        fprintf('  %5.0f  %.4f  %3d   %5d   %7.2f  %7.1f  %7.1f   %d\n',100*factors(k), M.Vmin_load, M.weak_load_bus, M.lowV_buses,M.Ploss_MW, M.Qloss_MVAr, M.Qmargin_MVAr, M.n_gen_at_Qmax);
    else
        fprintf('  %5.0f  NO SOLUTION (%s) - past the steady-state loadability limit\n', 100*factors(k), M.reason);
    end
    S(k,:) = [100*factors(k), M.success, M.Vmin_load, M.weak_load_bus, M.Ploss_MW, M.Qloss_MVAr, M.lowV_buses, M.max_loading_pct, M.Qmargin_MVAr, M.n_gen_at_Qmax];
end

T = array2table(S, 'VariableNames', {'Load_pct','Converged','Vmin_pu','WeakBus','Ploss_MW','Qloss_MVAr', 'LowVBusCount','MaxBranchLoading_pct','Qmargin_MVAr','GensAtQmax'});
writetable(T, fullfile(results_dir,'02_peak_loading_summary.csv'));

% first violation of the 0.95 pu limit
ok = S(:,2)==1;
iv = find(ok & S(:,3) < cfg.vmin_accept, 1);
if isempty(iv)
    first_violation = NaN;
else
    first_violation = S(iv,1);
    fprintf('\nFirst 0.95 pu violation at %.0f%% loading.\n', first_violation);
end

fig = figure('Visible','off'); hold on;
for b = cfg.urban_buses
    row = find(mpc.bus(:,BUS_I)==b,1);
    plot(100*factors, Vm(:,row), '-o', 'LineWidth',1.4, 'DisplayName',sprintf('Bus %d',b));
end
yline(cfg.vmin_accept,'--','0.95 pu','HandleVisibility','off');
grid on; xlabel('System Load Level (%)'); ylabel('Voltage (pu)');
title('Urban Bus Voltages Under Increasing Peak Demand');
legend('Location','southwest');
saveas(fig, fullfile(results_dir,'02_peak_urban_voltage.png')); close(fig);

Ucmp = NaN(numel(factors), 3);
for k = 1:numel(factors)
    c = scale_load(mpc, cfg, factors(k), cfg.urban_buses);
    [~, M] = run_pf_safe(c, mpopt, cfg);
    Ucmp(k,:) = [100*factors(k), M.Vmin_load, M.lowV_buses];
end
Tu = table(Ucmp(:,1), S(:,3), Ucmp(:,2), S(:,7), Ucmp(:,3), 'VariableNames',{'Load_pct','Vmin_systemwide','Vmin_urbanonly','LowV_systemwide','LowV_urbanonly'});
writetable(Tu, fullfile(results_dir,'02b_loading_direction_comparison.csv'));

fprintf('\nLOADING-DIRECTION CHECK (why the study scales the whole system):\n');
klast = find(S(:,2)==1, 1, 'last');    % last system-wide point that solved
fprintf('  System-wide: solves up to %.0f%% (Vmin %.4f pu), no solution beyond.\n',S(klast,1), S(klast,3));
fprintf('  Urban-only : still solves at %.0f%% with Vmin %.4f pu.\n',Ucmp(end,1), Ucmp(end,2));
fprintf('  Across the same sweep, urban-only scaling moves Vmin by %.4f pu\n',Ucmp(1,2)-Ucmp(end,2));
fprintf('  while system-wide scaling moves it by %.4f pu and then loses the solution.\n',S(1,3)-S(klast,3));

fig = figure('Visible','off');
plot(Ucmp(:,1), S(:,3), '-o', 'LineWidth',1.5); hold on;
plot(Ucmp(:,1), Ucmp(:,2), '-s', 'LineWidth',1.5);
yline(cfg.vmin_accept,'--','0.95 pu');
grid on; xlabel('Load Level (%)'); ylabel('Minimum Load-Bus Voltage (pu)');
title('Loading Direction: System-Wide vs Urban-Only Scaling');
legend('System-wide scaling','Urban-area scaling only','Location','southwest');
saveas(fig, fullfile(results_dir,'02b_loading_direction.png')); close(fig);

out.mpc = mpc;
out.base_result = r0;
out.base_metrics = M0;
out.factors = factors;
out.Vm = Vm;
out.summary = T;
out.first_violation_pct = first_violation;
end
