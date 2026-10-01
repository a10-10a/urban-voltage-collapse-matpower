function out = study_cpf(base_mpc, cfg, mpopt, results_dir, weak_bus)

define_constants;

target = scale_load(base_mpc, cfg, cfg.cpf_target_factor);
out.method = 'runcpf';
success = 0; r = []; used = '';

attempts = { ...
    struct('name','adaptive step, Q limits enforced', ...
           'opts',{{'cpf.enforce_q_lims',1,'cpf.adapt_step',1,'cpf.step',0.05}}), ...
    struct('name','fine step, Q limits enforced', ...
           'opts',{{'cpf.enforce_q_lims',1,'cpf.adapt_step',1,'cpf.step',0.01,'cpf.step_min',1e-4}}), ...
    struct('name','Q limits NOT enforced along the path', ...
           'opts',{{'cpf.enforce_q_lims',0,'cpf.adapt_step',1,'cpf.step',0.025}}) };

for a = 1:numel(attempts)
    try
        cpfopt = mpoption('verbose',0,'out.all',0,'pf.alg','NR','cpf.stop_at','NOSE');
        o = attempts{a}.opts;
        for k = 1:2:numel(o)
            try
                cpfopt = mpoption(cpfopt, o{k}, o{k+1});
            catch
            end
        end
        r = runcpf(base_mpc, target, cpfopt);
        if isfield(r,'success') && r.success
            success = 1; used = attempts{a}.name;
            fprintf('CPF succeeded: %s\n', used);
            break;
        else
            msg = 'no message';
            if isfield(r,'cpf') && isfield(r.cpf,'done_msg'), msg = r.cpf.done_msg; end
            fprintf('CPF attempt %d (%s) did not reach the nose: %s\n', a, attempts{a}.name, msg);
        end
    catch ME
        fprintf('CPF attempt %d (%s) errored: %s\n', a, attempts{a}.name, ME.message);
    end
end
out.cpf_options_used = used;

if success
    lambda = r.cpf.lam(:);
    V      = abs(r.cpf.V);
    busrow = find(base_mpc.bus(:,BUS_I) == weak_bus, 1);
    actual = 1 + lambda * (cfg.cpf_target_factor - 1);

    out.max_lambda       = max(lambda);
    out.max_load_factor  = 1 + out.max_lambda*(cfg.cpf_target_factor-1);
    out.V_at_nose        = V(busrow, find(lambda==max(lambda),1));

    T = table(lambda, actual, V(busrow,:)', 'VariableNames', ...
        {'Lambda_CPF','LoadFactor','WeakBusVoltage_pu'});
    writetable(T, fullfile(results_dir,'04_cpf_data.csv'));

    fig = figure('Visible','off');
    plot(100*actual, V(busrow,:), 'LineWidth',1.6); hold on;
    plot(100*out.max_load_factor, out.V_at_nose, 'r*','MarkerSize',10);
    yline(cfg.vmin_accept,'--','0.95 pu');
    grid on; xlabel('System Load Level (%)'); ylabel(sprintf('Bus %d Voltage (pu)',weak_bus));
    title(sprintf('PV Curve at Bus %d (Continuation Power Flow)', weak_bus));
    legend('PV curve','Nose point','Location','southwest');
    saveas(fig, fullfile(results_dir,'04_PV_CPF_curve.png')); close(fig);
    out.table = T;
else
    out.method = 'bisection';
    fprintf(['All CPF attempts failed. Falling back to bisection on the largest\n' ...
             'load factor a plain Newton power flow can still solve. NOTE: this is\n' ...
             'a LOWER BOUND on the true nose, because Newton-Raphson loses\n' ...
             'convergence slightly before the nose is reached. Report it as such.\n']);
    lo = 1.0; hi = cfg.cpf_target_factor;
    for k = 1:30
        mid = 0.5*(lo+hi);
        [rr,~] = run_pf_safe(scale_load(base_mpc,cfg,mid), mpopt, cfg);
        if rr.success, lo = mid; else, hi = mid; end
    end
    out.max_load_factor = lo;
    out.max_lambda = (lo-1)/(cfg.cpf_target_factor-1);
    [rr,~] = run_pf_safe(scale_load(base_mpc,cfg,lo), mpopt, cfg);
    out.V_at_nose = rr.bus(rr.bus(:,BUS_I)==weak_bus, VM);

    % upper branch only
    fs = linspace(1, lo, 25); Vv = NaN(size(fs));
    for k = 1:numel(fs)
        [rr,~] = run_pf_safe(scale_load(base_mpc,cfg,fs(k)), mpopt, cfg);
        if rr.success, Vv(k) = rr.bus(rr.bus(:,BUS_I)==weak_bus, VM); end
    end
    T = table(fs(:), Vv(:), 'VariableNames', {'LoadFactor','WeakBusVoltage_pu'});
    writetable(T, fullfile(results_dir,'04_cpf_data.csv'));
    fig = figure('Visible','off');
    plot(100*fs, Vv, 'LineWidth',1.6); grid on;
    xlabel('System Load Level (%)'); ylabel(sprintf('Bus %d Voltage (pu)',weak_bus));
    title(sprintf('PV Curve at Bus %d (upper branch, bisection)', weak_bus));
    saveas(fig, fullfile(results_dir,'04_PV_CPF_curve.png')); close(fig);
    out.table = T;
end

out.success = true;
out.loadability_margin_pct = 100*(out.max_load_factor - 1);

fprintf('\n============ PHASE 3b: PV / CONTINUATION POWER FLOW ============\n');
if strcmp(out.method,'runcpf')
    fprintf('Method                     : continuation power flow (%s)\n', out.cpf_options_used);
else
    fprintf('Method                     : bisection fallback - LOWER BOUND on the nose\n');
end
fprintf('Maximum load factor (nose) : %.4f (%.1f%%)\n', out.max_load_factor, 100*out.max_load_factor);
fprintf('Loadability margin         : %.1f%% above base load\n', out.loadability_margin_pct);
fprintf('Bus %d voltage at the nose  : %.4f pu\n', weak_bus, out.V_at_nose);
end
