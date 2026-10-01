function [is_islanded, n_isolated] = check_islanding(mpc)

define_constants;

nb   = size(mpc.bus,1);
busi = mpc.bus(:,BUS_I);
e2i  = sparse(busi, 1, (1:nb)', max(busi), 1);

on = mpc.branch(:,BR_STATUS) > 0;
f  = full(e2i(mpc.branch(on,F_BUS)));
t  = full(e2i(mpc.branch(on,T_BUS)));

adj = sparse([f;t],[t;f],1,nb,nb);

root = find(mpc.bus(:,BUS_TYPE)==REF,1);
if isempty(root), root = 1; end

seen = false(nb,1); seen(root) = true;
stack = root;
while ~isempty(stack)
    n = stack(end); stack(end) = [];
    nb_next = find(adj(n,:));
    new = nb_next(~seen(nb_next));
    seen(new) = true;
    stack = [stack, new]; 
end

n_isolated  = nb - sum(seen);
is_islanded = n_isolated > 0;
end
