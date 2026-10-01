function mpc2 = scale_load(mpc, cfg, factor, buses)

define_constants;
mpc2 = mpc;

if nargin < 4 || isempty(buses)
    switch lower(cfg.loading_mode)
        case 'system'
            buses = mpc.bus(mpc.bus(:,PD) ~= 0 | mpc.bus(:,QD) ~= 0, BUS_I)';
        case 'urban'
            buses = cfg.urban_buses;
        otherwise
            error('scale_load:mode','cfg.loading_mode must be ''system'' or ''urban''.');
    end
end

for b = buses(:)'
    row = find(mpc2.bus(:, BUS_I) == b, 1);
    if isempty(row)
        warning('scale_load:missing','Bus %d not found; skipped.', b);
        continue;
    end
    mpc2.bus(row, PD) = factor * mpc.bus(row, PD);
    mpc2.bus(row, QD) = factor * mpc.bus(row, QD);
end
end
