function idx = find_branch_by_pair(mpc, pair)

define_constants;
f = mpc.branch(:, F_BUS);
t = mpc.branch(:, T_BUS);
idx = find((f == pair(1) & t == pair(2)) |(f == pair(2) & t == pair(1)), 1);
end
