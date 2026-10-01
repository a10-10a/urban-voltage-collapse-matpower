function [r, M] = run_pf_safe(mpc, mpopt, cfg)

r = mpc;
r.success = 0;

if check_islanding(mpc)
    [~, niso] = check_islanding(mpc);
    r.reason = sprintf('islanded (%d bus isolated)', niso);
    M = case_metrics(r, cfg);
    M.reason = 'islanded';
    return;
end

ws = warning('off','all');
try
    r = runpf(mpc, mpopt);
    warning(ws);
    if ~r.success, r.reason = 'diverged'; end
    M = case_metrics(r, cfg);
catch ME
    warning(ws);
    r = mpc;
    r.success = 0;
    r.reason  = 'error';
    M = case_metrics(r, cfg);
    M.reason  = sprintf('error: %s', ME.message);
end
end
