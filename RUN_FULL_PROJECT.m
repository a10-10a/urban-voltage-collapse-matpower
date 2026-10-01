clc; clear; close all;

fprintf('============================================================\n');
fprintf(' EEE 306 - URBAN VOLTAGE COLLAPSE PREVENTION UNDER PEAK DEMAND\n');
fprintf(' IEEE 30-bus | MATPOWER | capacitor / tap / DR / STATCOM\n');
fprintf('============================================================\n');

if exist('runpf','file') ~= 2
    error(['MATPOWER is not on the MATLAB path. Install MATPOWER, run ' ...
           'install_matpower, then rerun this script.']);
end
if exist('case_urban30','file') ~= 2
    error(['case_urban30.m is missing. Set the MATLAB Current Folder to the ' ...
           'project folder containing all the .m files.']);
end
try
    v = mpver('all');
    fprintf('MATPOWER version: %s\n', v(1).Version);
catch
    fprintf('MATPOWER found.\n');
end

define_constants;
cfg = project_config();

results_dir = cfg.results_dir;
if ~exist(results_dir,'dir'), mkdir(results_dir); end

% Full Newton-Raphson AC power flow with generator reactive-limit enforcement.
mpopt = mpoption('pf.alg','NR', 'pf.enforce_q_lims',1, 'verbose',0, 'out.all',0);

diary(fullfile(results_dir,'00_run_log.txt')); diary on;
tic;

mpc_chk = loadcase(cfg.case_name);

cfg.band_buses = setdiff(mpc_chk.bus(:,BUS_I),mpc_chk.gen(mpc_chk.gen(:,GEN_STATUS)>0, GEN_BUS));
fprintf('Voltage band judged on %d load buses (generator buses excluded).\n',numel(cfg.band_buses));

if any(mpc_chk.gen(:,QMAX) >= 500)
    warning(['Generator reactive limits of +/-500 MVAr or wider were found. With effectively unlimited reactive support this network cannot collapse and the whole study is meaningless. Check the case file.']);
end

baseout = study_base_and_peak(cfg, mpopt, results_dir);

weakout = study_weak_bus(baseout, cfg, results_dir);
weak_bus = weakout.weak_bus;

cpfout = study_cpf(baseout.mpc, cfg, mpopt, results_dir, weak_bus);

peak_case = scale_load(baseout.mpc, cfg, cfg.peak_factor);
[rpeak, Mpeak] = run_pf_safe(peak_case, mpopt, cfg);
if ~rpeak.success
    error('The %.0f%% peak case has no solution. Reduce cfg.peak_factor - it is above the loadability limit of %.0f%%.' ,100*cfg.peak_factor, 100*cpfout.max_load_factor);
end

qvpeak = study_qv(peak_case, weak_bus, cfg, mpopt, results_dir, '_peak');

contout = screen_contingencies(peak_case, cfg, mpopt, results_dir);

weak_bus_crit = contout.critical_metrics.weak_load_bus;
if weak_bus_crit ~= weak_bus
    fprintf('\nWeak bus moves from %d (peak) to %d (peak + outage).\n', weak_bus, weak_bus_crit);
end
weak_bus = weak_bus_crit;

qvcrit = study_qv(contout.critical_case, weak_bus, cfg, mpopt, results_dir, '_critical');

mitout = study_mitigations(contout.critical_case, weak_bus, cfg, mpopt, results_dir);

dynout = study_dynamic_statcom(peak_case, contout.critical_case, weak_bus,mitout.cap_at_weakbus_MVAr, weak_bus, mitout.statcom_Vref, cfg, mpopt, results_dir);

%% ---- headline summary ------------------------------------------------------
fprintf('\n============================================================\n');
fprintf(' HEADLINE RESULTS (copy these into the report)\n');
fprintf('============================================================\n');
fprintf('Base case Vmin              : %.4f pu at bus %d\n', ...
    baseout.base_metrics.Vmin_load, baseout.base_metrics.weak_load_bus);
fprintf('First 0.95 pu violation at  : %.0f%% loading\n', baseout.first_violation_pct);
fprintf('Steady-state loadability    : %.0f%% of base load\n', 100*cpfout.max_load_factor);
fprintf('Weak bus                    : %d\n', weak_bus);
fprintf('Reactive margin at weak bus : %.1f MVAr (critical case)\n', qvcrit.reactive_margin_MVAr);
fprintf('Critical case Vmin          : %.4f pu\n', mitout.metrics.crit.Vmin_load);
fprintf('Minimum capacitor           : %.1f MVAr at bus %d\n', ...
    mitout.bestcap.Cap_MVAr, mitout.bestcap.Bus);
fprintf('STATCOM steady-state output : %.2f MVAr at %.2f pu\n', ...
    mitout.Qstat, mitout.statcom_Vref);
fprintf('Best scheme Vmin            : %.4f pu (STATCOM + %.0f%% DR)\n', ...
    mitout.metrics.enh.Vmin_load, mitout.bestdr.DR_pct);
if isfield(dynout,'settling_time_s')
    fprintf('STATCOM recovery time       : %.2f s\n', dynout.settling_time_s);
end

save(fullfile(results_dir,'project_workspace.mat'));
fprintf('\nElapsed: %.1f s\n', toc);
fprintf('Open the "results" folder for all CSV tables and PNG figures.\n');
fprintf('Read RESULTS_REFERENCE.md to confirm your numbers, then REPORT_TEMPLATE.md.\n');
diary off;
