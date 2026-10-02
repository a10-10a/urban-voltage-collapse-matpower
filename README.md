# Urban Voltage Collapse Prevention Under Peak Demand

A MATLAB/MATPOWER voltage-stability study of the IEEE 30-bus system. It stresses the network with rising demand, finds the weak buses, screens N-1 contingencies, and compares four mitigation options: a switched capacitor bank, transformer tap control, demand response and a STATCOM.

Course project for EEE 306 (Power System I Laboratory).

## What the study does

| Phase | Description | Main outputs |
|---|---|---|
| 1 | Validate the base case against published benchmark values | `01_base_voltage.png` |
| 2 | Raise system load from 100% to 150%, with an urban-only sweep for comparison | `02_*.csv`, `02b_*` |
| 3 | Rank weak buses (voltage, dV/dλ, total drop); PV curve by continuation power flow; Q-V curve | `03_*`, `04_*`, `05_*` |
| 4 | N-1 screening of lines, transformers and reactive sources; islanding events separated from voltage collapse | `06_*` |
| 5 | Capacitor, tap, demand response and STATCOM screened and compared | `07_*`, `08_*` |
| 6 | Reduced-order time-domain STATCOM response to the outage | `09_*` |

## Requirements

- MATLAB
- [MATPOWER](https://matpower.org) (tested with version 8.1), added to the MATLAB path

## How to run

1. Install MATPOWER and run `install_matpower`.
2. Download or clone this repository.
3. In MATLAB, set the **Current Folder** to the repository folder.
4. Run:

```matlab
RUN_FULL_PROJECT
```

Everything is written to a new `results/` folder: CSV tables, PNG figures and a full console log. Runtime is a minute, mostly in the contingency and capacitor screens.

## Repository layout

| File | Purpose |
|---|---|
| `RUN_FULL_PROJECT.m` | Master script that runs all six phases |
| `project_config.m` | All study parameters (nothing else hard-codes a bus or rating) |
| `case_urban30.m` | IEEE 30-bus case with three documented corrections |
| `study_*.m`, `screen_contingencies.m` | One module per study phase |
| `run_pf_safe.m`, `case_metrics.m`, `check_islanding.m` | Power flow wrapper, metrics and connectivity check |
| `scale_load.m`, `apply_demand_response.m`, `add_statcom.m`, `find_branch_by_pair.m` | Case-modification helpers |
| `BUGFIX_LOG.md` | Defects found in the first version, with numerical evidence |


## Key modelling decisions

- **Case corrections.** The supplied data file had ±1000 MVAr generator reactive limits, which makes voltage collapse impossible. Benchmark limits, voltage setpoints and transformer taps were restored. The slack bus keeps wide limits because it represents the strong external grid.
- **System-wide loading.** Peak demand scales every load bus. The urban area is only 8.9% of system load, and scaling it alone to 150% never violates a limit (`02b_loading_direction_comparison.csv` shows this).
- **Urban area = buses 24, 25, 26, 27, 29, 30.** This is a connected radial tail fed from bus 6 through two transformers, and it holds the top five places in the weak-bus ranking.
- **Voltage band judged at load buses only** (0.95 to 1.05 pu), on a fixed bus set so every scheme is compared like for like.
- **Design contingency.** Local reactive support is sized against the worst *urban* outage (line 27-30). The worst system-wide outage (line 3-4) is a bulk-corridor problem that local VARs cannot fix.

## Headline results

- Base case: Vmin 0.9756 pu at bus 30, active loss 17.85 MW.
- First 0.95 pu violation at 110% load. Steady-state loadability is at least 144% (a lower bound from bisection if `runcpf` does not converge).
- Weak bus: **bus 30**. Indicators (minimum voltage, dV/dλ, Q-V) all agree.
- Critical case (120% load + outage of line 27-30): Vmin 0.8090 pu, 17 load buses below 0.95 pu.

| Scheme | Vmin (pu) | Buses < 0.95 | Buses > 1.05 | P loss (MW) |
|---|---|---|---|---|
| No mitigation | 0.8090 | 17 | 0 | 30.30 |
| Capacitor, 15 MVAr at bus 29 | 0.9505 | 0 | 0 | 29.01 |
| Tap control (28-27 at 0.900) | 0.8722 | 13 | 0 | 29.98 |
| Demand response, 15% (48.5 MW) | 0.8844 | 2 | 0 | 20.20 |
| STATCOM, 1.03 pu at bus 30 | 0.9506 | 0 | 0 | 29.48 |
| Capacitor + tap + DR | 0.9991 | 0 | **5** | 20.29 |
| STATCOM + 15% DR | 0.9913 | 0 | 0 | 19.98 |

Two findings stand out:

1. **Stacking the classical measures over-corrects.** Capacitor + tap + DR has the highest minimum voltage but pushes five load buses above 1.05 pu (up to 1.128 pu), because a fixed capacitor cannot reduce its output once demand falls.
2. **The STATCOM self-adjusts.** With the same demand response added, its output drops from 16.04 to 11.31 MVAr and both band limits are still met.

The 28-27 transformer outage has no power-flow solution at all, and none of the studied mitigations can fix it. It needs redundancy or automatic load shedding.

## Limitations

- The IEEE 30-bus system is a transmission benchmark, not a real urban distribution network.
- Service labels (hospital at bus 26, water pumping at bus 30, and so on) are **synthetic study labels**, not real facilities.
- Load growth is uniform across the system, whereas real peaks are uneven.
- The dynamic study (`study_dynamic_statcom.m`) is a **reduced-order control-level model**, not an electromagnetic-transient simulation. It shows regulator action and response speed, but not converter switching or DC-link behaviour.
- Cost comparisons are qualitative; no equipment prices were used.

## References

1. R. D. Zimmerman, C. E. Murillo-Sánchez and R. J. Thomas, "MATPOWER: Steady-State Operations, Planning and Analysis Tools for Power Systems Research and Education," *IEEE Trans. Power Systems*, vol. 26, no. 1, 2011.
2. IEEE 30-bus test system data, American Electric Power, December 1961.
