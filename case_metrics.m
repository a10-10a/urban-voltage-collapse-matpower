function M = case_metrics(r, cfg)

define_constants;

M = blank_metrics();

if ~isstruct(r) || ~isfield(r,'success') || ~r.success
    if isstruct(r) && isfield(r,'reason'), M.reason = r.reason; else, M.reason = 'diverged'; end
    return;
end

M.success = true;
M.reason  = 'ok';

V = r.bus(:, VM);

if ~cfg.band_at_load_buses_only
    is_load = true(size(V));
elseif isfield(cfg,'band_buses') && ~isempty(cfg.band_buses)
    % Fixed bus set, so every scheme is judged on exactly the same buses.
    is_load = ismember(r.bus(:, BUS_I), cfg.band_buses);
else
    gen_on   = r.gen(:, GEN_STATUS) > 0;
    gen_bus  = r.gen(gen_on, GEN_BUS);
    is_load  = ~ismember(r.bus(:, BUS_I), gen_bus);
end
gen_on = r.gen(:, GEN_STATUS) > 0;

M.Vmin_load = min(V(is_load));
M.Vmax_load = max(V(is_load));

[M.Vmin, k] = min(V);
M.Vmax      = max(V);
M.weak_bus  = r.bus(k, BUS_I);

lb = r.bus(is_load, BUS_I);
[~, kl]      = min(V(is_load));
M.weak_load_bus = lb(kl);

M.lowV_buses  = sum(V(is_load) < cfg.vmin_accept);
M.highV_buses = sum(V(is_load) > cfg.vmax_accept);
M.in_band     = (M.Vmin_load >= cfg.vmin_accept) && (M.Vmax_load <= cfg.vmax_accept);

% ---- losses ----------------------------------------------------------------
M.Ploss_MW   = sum(r.branch(:, PF) + r.branch(:, PT));
M.Qloss_MVAr = sum(r.branch(:, QF) + r.branch(:, QT));

% ---- branch loading --------------------------------------------------------
rate  = r.branch(:, RATE_A);
valid = rate > 0 & r.branch(:, BR_STATUS) > 0;
Sf = sqrt(r.branch(:, PF).^2 + r.branch(:, QF).^2);
St = sqrt(r.branch(:, PT).^2 + r.branch(:, QT).^2);
ld = zeros(size(rate));
ld(valid) = 100 .* max(Sf(valid), St(valid)) ./ rate(valid);
M.max_loading_pct = max([ld; 0]);
M.n_overloaded    = sum(ld > 100);

% ---- reactive reserve ------------------------------------------------------
M.Qgen_MVAr    = sum(r.gen(gen_on, QG));
M.Qmargin_MVAr = sum(r.gen(gen_on, QMAX) - r.gen(gen_on, QG));
M.n_gen_at_Qmax = sum(r.gen(gen_on, QG) >= r.gen(gen_on, QMAX) - 1e-3);

gi  = r.gen(gen_on, :);
vb  = zeros(size(gi,1),1);
for j = 1:size(gi,1)
    vb(j) = r.bus(r.bus(:,BUS_I) == gi(j,GEN_BUS), VM);
end
M.qlim_artifact = any(gi(:,QG) >= gi(:,QMAX) - 1e-3 & vb > gi(:,VG) + 1e-4);
end

function M = blank_metrics()
M.success = false;      M.reason = 'unknown';
M.Vmin = NaN;           M.Vmax = NaN;
M.Vmin_load = NaN;      M.Vmax_load = NaN;
M.weak_bus = NaN;       M.weak_load_bus = NaN;
M.lowV_buses = NaN;     M.highV_buses = NaN;    M.in_band = false;
M.Ploss_MW = NaN;       M.Qloss_MVAr = NaN;
M.max_loading_pct = NaN;M.n_overloaded = NaN;
M.Qgen_MVAr = NaN;      M.Qmargin_MVAr = NaN;   M.n_gen_at_Qmax = NaN;
M.qlim_artifact = false;
end
