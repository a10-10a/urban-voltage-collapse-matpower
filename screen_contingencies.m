function out = screen_contingencies(peak_case, cfg, mpopt, results_dir)

define_constants;

nl = size(peak_case.branch,1);

tx_rows = [];
for p = 1:size(cfg.transformer_pairs,1)
    idx = find_branch_by_pair(peak_case, cfg.transformer_pairs(p,:));
    if ~isempty(idx), tx_rows(end+1) = idx; end 
end
tx_rows  = unique(tx_rows);
line_rows = setdiff((1:nl)', tx_rows(:));

fprintf('\n============ PHASE 4: N-1 CONTINGENCY SCREENING ============\n');
fprintf('Loading = %.0f%% of base. %d lines + %d transformers + %d reactive sources.\n', 100*cfg.peak_factor, numel(line_rows), numel(tx_rows), size(peak_case.gen,1));

[Tline, line_class] = screen_branches(peak_case, line_rows, cfg, mpopt, 'Line');
writetable(Tline, fullfile(results_dir,'06_line_contingencies.csv'));

[Ttx, tx_class] = screen_branches(peak_case, tx_rows, cfg, mpopt, 'Transformer');
writetable(Ttx, fullfile(results_dir,'06_transformer_contingencies.csv'));

% ---- loss of generator reactive support -------------------------------------
ng = size(peak_case.gen,1);
gD = NaN(ng,6);
for g = 1:ng
    c = peak_case;
    c.gen(g,QMAX) = 0; c.gen(g,QMIN) = 0;
    [~,M] = run_pf_safe(c, mpopt, cfg);
    gD(g,:) = [g, peak_case.gen(g,GEN_BUS), M.success, M.Vmin_load, M.Ploss_MW, M.lowV_buses];
end
Tg = array2table(gD,'VariableNames', {'GeneratorRow','Bus','Converged','Vmin_pu','Ploss_MW','LowVBusCount'});
writetable(Tg, fullfile(results_dir,'06_reactive_source_outages.csv'));

% ---- rank -------------------------------------------------------------------
Tall = [Tline; Ttx];
cls  = [line_class; tx_class];

report_group(Tall, cls, 'ISLANDED',  'Islanding outages (excluded from severity ranking)');
report_group(Tall, cls, 'COLLAPSE',  'Voltage-collapse outages (no power-flow solution)');

solved = strcmp(cls,'VIOLATION') | strcmp(cls,'OK');
Ts = Tall(solved,:);
[~,ord] = sort(Ts.Vmin_pu,'ascend');
Ts = Ts(ord,:);
fprintf('\nWorst solved outages by minimum load-bus voltage:\n');
for k = 1:min(6,height(Ts))
    fprintf('   %-11s row %2d  %2d-%-2d  Vmin = %.4f pu  (%d buses below %.2f)\n', ...
        Ts.Type{k}, Ts.BranchRow(k), Ts.FromBus(k), Ts.ToBus(k), Ts.Vmin_pu(k), ...
        Ts.LowVBusCount(k), cfg.vmin_accept);
end

% worst overall (solved)
worst_system_row = Ts.BranchRow(1);

in_urban = ismember(Ts.FromBus, cfg.urban_buses) | ismember(Ts.ToBus, cfg.urban_buses);
if any(in_urban)
    Tu = Ts(in_urban,:);
    worst_urban_row = Tu.BranchRow(1);
    fprintf('\nWorst URBAN outage (design case for local reactive support):\n');
    fprintf('   %s row %d  %d-%d  Vmin = %.4f pu\n', Tu.Type{1}, Tu.BranchRow(1), Tu.FromBus(1), Tu.ToBus(1), Tu.Vmin_pu(1));
else
    worst_urban_row = worst_system_row;
    warning('screen_contingencies:nourban','No solved urban contingency found.');
end

critical_case = peak_case;
critical_case.branch(worst_urban_row, BR_STATUS) = 0;
[rcrit, Mcrit] = run_pf_safe(critical_case, mpopt, cfg);

fprintf('\nCRITICAL DESIGN CASE = %.0f%% load + outage of branch %d (%d-%d)\n', 100*cfg.peak_factor, worst_urban_row, ...
    peak_case.branch(worst_urban_row,F_BUS), peak_case.branch(worst_urban_row,T_BUS));
fprintf('   Vmin = %.4f pu at bus %d | %d load buses below %.2f pu | losses %.1f MW\n', Mcrit.Vmin_load, Mcrit.weak_load_bus, Mcrit.lowV_buses, cfg.vmin_accept, Mcrit.Ploss_MW);

out.line_table = Tline;
out.tx_table   = Ttx;
out.qsource_table = Tg;
out.all_table  = Tall;
out.classes    = cls;
out.worst_system_branch = worst_system_row;
out.worst_urban_branch  = worst_urban_row;
out.critical_case    = critical_case;
out.critical_result  = rcrit;
out.critical_metrics = Mcrit;
end

function [T, cls] = screen_branches(base, rows, cfg, mpopt, typestr)
define_constants;
n = numel(rows);
D = NaN(n,7);
cls = cell(n,1);
Type = cell(n,1);
for ii = 1:n
    k = rows(ii);
    c = base; c.branch(k,BR_STATUS) = 0;
    if check_islanding(c)
        cls{ii} = 'ISLANDED';
        D(ii,:) = [k, base.branch(k,F_BUS), base.branch(k,T_BUS), 0, NaN, NaN, NaN];
    else
        [~,M] = run_pf_safe(c, mpopt, cfg);
        if ~M.success
            cls{ii} = 'COLLAPSE';
        elseif ~M.in_band
            cls{ii} = 'VIOLATION';
        else
            cls{ii} = 'OK';
        end
        D(ii,:) = [k, base.branch(k,F_BUS), base.branch(k,T_BUS), M.success, M.Vmin_load, M.Ploss_MW, M.lowV_buses];
    end
    Type{ii} = typestr;
end
T = table(Type, D(:,1), D(:,2), D(:,3), D(:,4), D(:,5), D(:,6), D(:,7), cls, 'VariableNames', {'Type','BranchRow','FromBus','ToBus','Converged', ...
                      'Vmin_pu','Ploss_MW','LowVBusCount','Outcome'});
end

function report_group(T, cls, key, header)
sel = strcmp(cls, key);
if ~any(sel), return; end
fprintf('\n%s:\n', header);
S = T(sel,:);
for k = 1:height(S)
    fprintf('   %-11s row %2d  %d-%d\n', S.Type{k}, S.BranchRow(k), S.FromBus(k), S.ToBus(k));
end
end
