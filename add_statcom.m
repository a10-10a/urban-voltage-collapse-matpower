function [mpc2, gen_row] = add_statcom(mpc, bus_no, cfg, Vset, Qmin, Qmax)

define_constants;

if nargin < 4 || isempty(Vset), Vset = cfg.statcom_Vref;  end
if nargin < 5 || isempty(Qmin), Qmin = cfg.statcom_Qmin;  end
if nargin < 6 || isempty(Qmax), Qmax = cfg.statcom_Qmax;  end

mpc2 = mpc;
row  = find(mpc2.bus(:, BUS_I) == bus_no, 1);
if isempty(row)
    error('add_statcom:bus','Bus %d does not exist in this case.', bus_no);
end

g = zeros(1, size(mpc2.gen, 2));
g(GEN_BUS)    = bus_no;
g(PG)         = cfg.statcom_P;
g(QG)         = 0;
g(QMAX)       = Qmax;
g(QMIN)       = Qmin;
g(VG)         = Vset;
g(MBASE)      = mpc2.baseMVA;
g(GEN_STATUS) = 1;
g(PMAX)       = 0;
g(PMIN)       = 0;

mpc2.gen = [mpc2.gen; g];
gen_row  = size(mpc2.gen, 1);

% Keep gencost consistent with gen.
if isfield(mpc2, 'gencost') && ~isempty(mpc2.gencost)
    ng0 = gen_row - 1;
    if size(mpc2.gencost,1) == ng0                 % active-power costs only
        mpc2.gencost = [mpc2.gencost; mpc2.gencost(end,:)];
    elseif size(mpc2.gencost,1) == 2*ng0           % active + reactive costs
        P = mpc2.gencost(1:ng0, :);
        Q = mpc2.gencost(ng0+1:end, :);
        mpc2.gencost = [P; P(end,:); Q; Q(end,:)];
    else
        warning('add_statcom:gencost', ...
            'Unexpected gencost size; removing it (power flow does not use it).');
        mpc2 = rmfield(mpc2, 'gencost');
    end
end

if mpc2.bus(row, BUS_TYPE) == PQ
    mpc2.bus(row, BUS_TYPE) = PV;
end
mpc2.bus(row, VM) = Vset;
end
