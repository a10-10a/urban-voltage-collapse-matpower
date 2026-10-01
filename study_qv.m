function out = study_qv(case_for_qv, weak_bus, cfg, mpopt, results_dir, tag)

if nargin < 6, tag = ''; end
define_constants;

Vset = (0.40:0.01:1.10)';
Qreq = NaN(size(Vset));
conv = false(size(Vset));

for k = 1:numel(Vset)
    [c, grow] = add_statcom(case_for_qv, weak_bus, cfg, Vset(k), -9999, 9999);
    [r, ~] = run_pf_safe(c, mpopt, cfg);
    if r.success
        conv(k) = true;
        Qreq(k) = r.gen(grow, QG);
    end
end

T = table(Vset, Qreq, conv, 'VariableNames', {'VoltageSet_pu','RequiredQ_MVAr','Converged'});
fname = sprintf('05_QV_curve_data%s.csv', tag);
writetable(T, fullfile(results_dir, fname));

ok = conv & ~isnan(Qreq);
if any(ok)
    vv = Vset(ok); qq = Qreq(ok);
    [Qnose, ii] = min(qq);
    V_at_nose = vv(ii);
    Q_at_1pu  = interp1(vv, qq, 1.00, 'linear', NaN);
    % reactive margin: distance from the operating point (Q = 0) to the nose
    reactive_margin = -Qnose;
else
    Qnose = NaN; V_at_nose = NaN; Q_at_1pu = NaN; reactive_margin = NaN;
end

fig = figure('Visible','off');
plot(Vset, Qreq, 'LineWidth',1.6); hold on;
if ~isnan(Qnose)
    plot(V_at_nose, Qnose, 'r*', 'MarkerSize',10);
end
xline(cfg.vmin_accept,'--','0.95 pu'); yline(0,'--');
grid on; xlabel('Bus Voltage Setpoint (pu)'); ylabel('Required Reactive Injection (MVAr)');
title(sprintf('Q-V Curve at Bus %d%s', weak_bus, strrep(tag,'_',' ')));
if ~isnan(Qnose), legend('Q-V curve','Nose (minimum)','Location','northwest'); end
saveas(fig, fullfile(results_dir, sprintf('05_QV_curve%s.png', tag))); close(fig);

fprintf('\nQ-V ANALYSIS at bus %d%s\n', weak_bus, strrep(tag,'_',' '));
fprintf('  Q required to hold 1.00 pu : %+.2f MVAr\n', Q_at_1pu);
fprintf('  Q-V nose                   : %+.2f MVAr at %.2f pu\n', Qnose, V_at_nose);
fprintf('  Reactive-power margin      : %.2f MVAr\n', reactive_margin);

out.table = T;
out.Qnose = Qnose;
out.V_at_nose = V_at_nose;
out.Q_at_1pu = Q_at_1pu;
out.reactive_margin_MVAr = reactive_margin;
end
