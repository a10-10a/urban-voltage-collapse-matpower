function [mpc2, MW_shed] = apply_demand_response(mpc, cfg, reduction, buses)

define_constants;
mpc2 = mpc;

if nargin < 4 || isempty(buses)
    switch lower(cfg.dr_scope)
        case 'urban'
            buses = intersect(cfg.urban_buses, mpc.bus(mpc.bus(:,PD) ~= 0, BUS_I)');
        otherwise
            buses = mpc.bus(mpc.bus(:,PD) ~= 0, BUS_I)';
    end
end
buses = setdiff(buses, cfg.critical_buses);

MW_shed = 0;
for b = buses(:)'
    row = find(mpc2.bus(:, BUS_I) == b, 1);
    if isempty(row), continue; end
    MW_shed = MW_shed + reduction * mpc2.bus(row, PD);
    mpc2.bus(row, PD) = (1 - reduction) * mpc2.bus(row, PD);
    mpc2.bus(row, QD) = (1 - reduction) * mpc2.bus(row, QD);
end
end
