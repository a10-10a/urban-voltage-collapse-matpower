function out = study_weak_bus(baseout, cfg, results_dir)

define_constants;
mpc = baseout.mpc;
f   = baseout.factors(:);
Vm  = baseout.Vm;
busno = mpc.bus(:,BUS_I);

gen_on  = mpc.gen(:,GEN_STATUS) > 0;
is_load = ~ismember(busno, mpc.gen(gen_on, GEN_BUS));

nb = numel(busno);
slope = NaN(nb,1);
drop  = NaN(nb,1);
for j = 1:nb
    ok = ~isnan(Vm(:,j));
    if sum(ok) >= 2
        p = polyfit(f(ok), Vm(ok,j), 1);
        slope(j) = p(1);
        drop(j)  = Vm(find(ok,1,'first'),j) - Vm(find(ok,1,'last'),j);
    end
end

kpeak = find(abs(f - cfg.peak_factor) < 1e-9, 1);
if isempty(kpeak), kpeak = find(~all(isnan(Vm),2), 1, 'last'); end
Vpeak = Vm(kpeak,:)';

idx = find(is_load & ~isnan(slope));
[~, ord] = sort(slope(idx), 'ascend');       % most negative first
idx = idx(ord);

T = table((1:numel(idx))', busno(idx), Vpeak(idx), slope(idx), drop(idx), 'VariableNames', {'Rank','Bus','V_at_peak_pu','dV_dLoadFactor','VoltageDrop_pu'});
writetable(T, fullfile(results_dir,'03_weak_bus_ranking.csv'));

% Selected weak bus: lowest voltage at the design peak, among load buses.
cand = find(is_load);
[~, jm] = min(Vpeak(cand));
weak_bus = busno(cand(jm));

fprintf('\n============ PHASE 3: WEAK-BUS IDENTIFICATION ============\n');
fprintf('Ranking at %.0f%% loading (load buses only):\n', 100*f(kpeak));
fprintf('  Rank  Bus   V(peak)   dV/dlambda\n');
for k = 1:min(6,height(T))
    fprintf('  %3d   %3d   %.4f    %+.4f\n', T.Rank(k), T.Bus(k), T.V_at_peak_pu(k), T.dV_dLoadFactor(k));
end
fprintf('Weak bus selected (lowest voltage at peak): Bus %d\n', weak_bus);
if ismember(weak_bus, cfg.urban_buses)
    fprintf('Confirmed: the weak bus lies inside the modelled urban area.\n');
else
    fprintf('NOTE: the weak bus lies OUTSIDE the modelled urban area - check cfg.urban_buses.\n');
end

fig = figure('Visible','off');
bar(busno(idx), -slope(idx));
grid on; xlabel('Bus Number'); ylabel('-dV/d\lambda (pu per load factor)');
title('Voltage Sensitivity Ranking (taller bar = weaker bus)');
saveas(fig, fullfile(results_dir,'03_voltage_sensitivity.png')); close(fig);

out.table = T;
out.weak_bus = weak_bus;
out.slope = slope;
out.is_load = is_load;
end
