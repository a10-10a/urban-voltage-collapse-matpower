function cfg = project_config()
cfg.case_name = 'case_urban30';


cfg.urban_buses = [24 25 26 27 29 30];


cfg.urban_labels = { ...
    'Commercial district (flexible)', ...   % 24
    'Urban sub-transmission node', ...      % 25
    'Hospital campus', ...                  % 26
    'Urban supply node', ...                % 27
    'Residential / communications', ...     % 29
    'Residential + water pumping'};         % 30

% Loads that must never be curtailed by demand response.
cfg.critical_buses = [26 30];

cfg.loading_mode = 'system';

cfg.load_factors = 1.00:0.05:1.50;   % stress sweep
cfg.peak_factor  = 1.20;             % design peak used for contingencies
cfg.extreme_factor = 1.50;           % near the steady-state loadability limit

cfg.cpf_target_factor = 2.0;

cfg.vmin_accept = 0.95;
cfg.vmax_accept = 1.05;

cfg.band_at_load_buses_only = true;

cfg.band_buses = [];

cfg.cap_sizes_MVAr = 2.5:2.5:50;
cfg.cap_candidate_buses = [24 26 29 30];

cfg.dr_levels = [0.05 0.10 0.15];    % 5-15%

cfg.dr_scope = 'system';

% Regulating transformers of the benchmark (from-bus, to-bus).
cfg.transformer_pairs = [6 9; 6 10; 4 12; 28 27];
cfg.tap_values = 0.90:0.0125:1.10;   % +/-10%, 0.0125 pu steps (~16 steps/side)

cfg.statcom_Qmax = 50;               % MVAr
cfg.statcom_Qmin = -50;              % MVAr
cfg.statcom_P    = 0;                % MW

cfg.statcom_Vref_options = [1.00 1.02 1.03 1.05];
cfg.statcom_Vref = 1.00;             

cfg.dyn.t_end     = 5.0;             % s
cfg.dyn.t_event   = 1.0;             % s, contingency instant
cfg.dyn.dt        = 1e-3;            % s
cfg.dyn.Tgrid     = 0.15;            % s, local voltage settling surrogate
cfg.dyn.Tstat     = 0.02;            % s, converter/controller actuator
cfg.dyn.deadband  = 0.002;           % pu
cfg.dyn.Qprobe    = 1.0;             % MVAr probe for local dV/dQ
cfg.dyn.loop_gain = 0.70;            % Kp = loop_gain / (dV/dQ)
cfg.dyn.Ki_ratio  = 3.0;             % Ki = Ki_ratio * Kp


cfg.results_dir = fullfile(pwd,'results');
end
