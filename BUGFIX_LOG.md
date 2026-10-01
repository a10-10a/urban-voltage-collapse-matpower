# Bug Audit — Original Package vs Corrected Package

Every item below is a defect found in the supplied `.m` files or the supplied
case data. Each entry states what was wrong, why it matters, the numerical
evidence, and what was changed.

Severity: **CRITICAL** = the study's conclusion is invalid without the fix.
**MAJOR** = results are wrong or silently missing. **MINOR** = correctness or
robustness improvement.

---

## CRITICAL

### C1 — Generator reactive limits were ±1000 MVAr

**File:** `ieee-30-bus_m.txt` (the supplied case data)

Every generator carried `Qmax = +1000`, `Qmin = -1000` MVAr. The benchmark
values are ±10 to ±50 MVAr.

**Why it matters.** This project is about voltage collapse caused by *running
out of reactive power*. With ±1000 MVAr, reactive power never runs out, so
collapse cannot occur, and `mpoption('pf.enforce_q_lims',1)` — which the
original master script correctly enabled — has nothing to enforce. The
`VIVA_GUIDE.md` question "Why enforce Q limits?" had no valid answer.

**Evidence.** Solving the supplied file, the generator at bus 2 delivers
**175.7 MVAr**. Its benchmark rating is 50 MVAr. The synchronous condenser at
bus 8 delivers 45.7 MVAr against a 40 MVAr rating.

**Fix.** `case_urban30.m` restores the benchmark reactive limits
(bus 2: −40/+50, bus 5: −40/+40, bus 8: −10/+40, buses 11 and 13: −6/+24).
The slack at bus 1 is deliberately left wide (−100/+200 MVAr) — see C2.

**Result of the fix.** The network now behaves like a real one. Under
increasing load the condensers saturate one after another (buses 2, 5, 8 at
base load; bus 11 at 105%; bus 13 at 110%), and once the last reserve is gone
the voltage falls away sharply. That progression *is* the project.

---

### C2 — A binding reactive limit on the slack bus makes results non-monotonic

**File:** case data / `project_config.m`

When the reference-bus generator violates a reactive limit, MATPOWER converts
that bus to PQ and **relocates the reference bus** to another generator.

**Evidence.** With a binding slack limit the load sweep produced
Vmin = 0.884 at 102% load, 0.933 at 105%, no solution at 108–120%, then
0.954 again at 125%. Voltage cannot rise as load increases; the sweep was
numerical nonsense, not physics.

**Fix.** Bus 1 (Glen Lyn) represents the strong external grid connection and is
given non-binding limits, which is documented in the case-file header. Collapse
is then driven by the four condensers, which is the physically correct
mechanism.

---

### C3 — The urban load area is far too small to stress the network

**Files:** `project_config.m`, `scale_urban_load.m`, `study_base_and_peak.m`

The original urban area (buses 10, 20, 19, 18, 15) carries **28.9 MW of the
283.4 MW system load — 10.2%**. Scaling only those buses to 140% adds 11.6 MW,
about 4% of system load.

**Evidence.** Scaling the original urban area from 100% to 150%:

| Urban load | Vmin | Buses below 0.95 |
|---|---|---|
| 100% | 0.9756 | 0 |
| 120% | 0.9713 | 0 |
| 140% | 0.9606 | 0 |
| 150% | 0.9583 | 0 |

Even at **300%** urban load, Vmin is 0.932 pu. There is no collapse, no violated
bus and nothing to mitigate. The proposal slide showing 0.86 pu at 140% cannot
be reproduced from this loading direction.

**Fix.** `cfg.loading_mode = 'system'`. Peak demand is modelled as a city-wide
load increase applied to every load bus, which is both physically correct and
the standard loading direction for voltage-stability work.
`study_base_and_peak.m` still runs the urban-only sweep alongside it and writes
`02b_loading_direction_comparison.csv`, so the report can *show* why the
direction was changed instead of just asserting it.

**Result of the fix.** System-wide scaling: Vmin 0.9756 → 0.8958 at 120% →
0.7612 at 140%, with no solution beyond about 150%. That is a textbook PV nose.

---

### C4 — The urban area did not contain the network's actual weak point

**File:** `project_config.m`

Buses 10, 20, 19, 18 and 15 sit in the meshed 33 kV area close to the
6–9, 6–10 and 4–12 transformers. The genuinely weak part of the IEEE 30-bus
system is the Cloverdale radial tail. The original code therefore selected a
mitigation bus outside the area the report described as "the urban network",
making the narrative incoherent.

**Evidence — weak-bus ranking by dV/dλ (all load buses):**

| Rank | Bus | dV/dλ | V at 120% |
|---|---|---|---|
| 1 | **30** | −0.402 | 0.8958 |
| 2 | **26** | −0.396 | 0.9003 |
| 3 | **29** | −0.383 | 0.9112 |
| 4 | **24** | −0.375 | 0.9201 |
| 5 | **25** | −0.369 | 0.9239 |
| 6 | 19 | −0.362 | 0.9320 |

**Fix.** `cfg.urban_buses = [24 25 26 27 29 30]`. This is a connected
sub-network, it is fed radially from bus 6 through two transformers, and the
top five weak buses all fall inside it. The choice is now *a result of the
analysis* rather than an assumption. Service labels were reassigned
accordingly (hospital at bus 26, water pumping and residential at bus 30,
flexible commercial at bus 24).


---

### C5 — The band check excluded the very bus the STATCOM regulates

**Files:** `case_metrics.m`, `project_config.m` — *found after the first live run*

`case_metrics` identified "load buses" from the solved result, as the buses with
no in-service generator. But `add_statcom` attaches a generator at the weak bus
and converts it to PV. So in every STATCOM case the regulated bus dropped out of
the band check.

**Consequence.** The STATCOM's own bus voltage was never tested against the
1.05 pu upper limit, and the `Vmax_load` column was not comparable between
schemes: the STATCOM row reported 1.0094 pu when the bus it was holding sat at
1.0300 pu. With `cfg.statcom_Vref_options` reaching 1.05 pu the error is
harmless here, but a higher setpoint would have passed an over-voltage
unnoticed.

**Fix.** `cfg.band_buses` is set once by the master script from the original
case, before any STATCOM exists, and `case_metrics` judges every scheme on that
fixed bus set.

---

### C6 — The dynamic capacitor trace initialised at a non-physical voltage

**File:** `study_dynamic_statcom.m` — *found after the first live run*

The capacitor's pre-disturbance state was found by iterating the fixed point
`V = Vpre + kq·Qrated·V²` using the **small-signal probe** value
kq = 0.0183 pu/MVAr. With Qrated = 15 MVAr that iteration converges to
**V = 1.58 pu**, and the printed output showed the bank delivering 37.4 MVAr
from a 15 MVAr rating and "103% of rating lost".

**Root cause.** A 1 MVAr probe measures a local slope. Extrapolating it linearly
across a 15 MVAr injection and a 0.2 pu voltage rise is far outside its range of
validity.

**Fix.** Three changes:
1. `kq` is calibrated so the model reproduces the MATPOWER steady state exactly,
   `kq = (V_with_STATCOM − V_no_STATCOM)/Q_STATCOM = 0.0138 pu/MVAr`.
2. The capacitor trace is anchored to two exact power-flow solutions — bank in
   service, before and after the outage — and interpolated with the network time
   constant, so nothing is extrapolated.
3. The percentage change is computed against the bank's own pre-event output
   instead of its nameplate rating.

---

### C7 — The dynamic study compared devices at different buses and at the wrong setpoint

**Files:** `study_dynamic_statcom.m`, `00_RUN_FULL_PROJECT.m` — *found after the
first live run*

The capacitor screen selects 15 MVAr at **bus 29**, but the dynamic model
applied that rating at **bus 30** using bus 30's sensitivity. It also used
`cfg.statcom_Vref` = 1.00 pu while the mitigation study had selected 1.03 pu, so
the dynamic result did not correspond to the steady-state result being reported
two sections earlier.

**Fix.** The master script passes the selected setpoint and the smallest
acceptable rating **at the weak bus** (`out.cap_at_weakbus_MVAr`), so both
devices sit at the same bus and the comparison measures technology rather than
siting.

---

## MAJOR

### M1 — `add_statcom` broke MATPOWER, and the failure was swallowed silently

**File:** `add_statcom.m`

The function appended a row to `mpc.gen` without appending a matching row to
`mpc.gencost`. MATPOWER's `ext2int` indexes `gencost` with the generator status
vector, so a 7-row `gen` against a 6-row `gencost` throws an index error.

That exception was caught by the blanket `try/catch` in `run_pf_safe.m`, which
returned `success = 0`. **Every STATCOM result and every point of every QV
curve therefore became `NaN`, and the script printed no error.** The final
comparison table would have shown an empty STATCOM row and nobody would have
known why.

**Fix.** `add_statcom.m` now maintains `gencost` consistently (handling both the
`ng`-row and `2·ng`-row conventions), validates the bus number, and accepts
explicit reactive limits so the QV study can use a wide-limit probe source.

---

### M2 — The voltage-band test could never pass, disabling all selection logic

**File:** `study_mitigations.m`

Selection used:

```matlab
acceptable = Converged==1 & Vmin_pu>=cfg.vmin_accept & Vmax_pu<=cfg.vmax_accept;
```

with `cfg.vmax_accept = 1.05`, where `Vmax_pu` was the maximum over **all**
buses. In this benchmark the generator setpoints are **1.060 pu at bus 1** and
**1.082 pu at bus 11**. So `Vmax_pu ≥ 1.082` in every case ever solved,
including the perfectly healthy base case.

**Consequence.** `any(acceptable)` was always false. The "choose the minimum
effective capacitor / smallest tap movement / minimum demand response" logic
never executed once. Every selection silently fell through to the else branch,
"pick whichever case has the highest Vmin" — which ignores over-voltage
entirely.

**Evidence of the damage.** With that fallback, capacitor selection at bus 30
prefers larger and larger banks: 20 MVAr gives **1.12 pu** at bus 30, 30 MVAr
gives **1.34 pu**. Both would have been reported as improvements.

**Fix.** The acceptance band is evaluated at **load (PQ) buses only**
(`cfg.band_at_load_buses_only`). `case_metrics.m` now returns `Vmin_load`,
`Vmax_load`, `highV_buses` and a boolean `in_band`. Over-voltage now disqualifies
a solution instead of being invisible.

---

### M3 — Islanding contingencies were mistaken for voltage-stability events

**File:** `screen_contingencies.m`

The screening loop opened one branch at a time and ran a power flow. It never
checked whether the resulting network was still connected.

**Evidence.** Three single-branch outages disconnect a bus in this system:

| Outage | Effect |
|---|---|
| 9–11 | isolates generator bus 11 |
| 12–13 | isolates generator bus 13 |
| 25–26 | isolates load bus 26 |

A power flow on a disconnected network is ill-posed. It does not fail "because
of voltage collapse", it fails because the problem has no meaning.

**Fix.** New `check_islanding.m` (breadth-first search from the reference bus,
written locally so it does not depend on the MATPOWER version). Screening now
classifies every outage as `ISLANDED`, `COLLAPSE`, `VIOLATION` or `OK`.

---

### M4 — The most severe contingencies were excluded from the ranking

**File:** `screen_contingencies.m`

The ranking rule was "among convergent cases, choose the lowest Vmin".
Contingencies with **no solution at all** — the worst possible outcome — were
dropped.

**Evidence at 120% loading**, outages with no power-flow solution:
**1–2, 1–3, 2–5 and the 28–27 transformer.** The original code would have
ranked all four as less severe than an outage that merely produced a low
voltage.

**Fix.** `COLLAPSE` outcomes are reported first and explicitly, ahead of every
solved case. They are excluded only from the *design* case, because you cannot
size a capacitor against a case that has no operating point — a limitation the
report now states rather than hides.

---

### M5 — The design contingency was a bulk-transmission fault that local VARs cannot fix

**File:** `screen_contingencies.m`

Choosing the globally worst solved outage selects **line 3–4**, a 132 kV bulk
corridor near the slack. The resulting problem is system-wide, and no amount of
reactive support at a 33 kV radial bus repairs it.

**Evidence at 120% loading, outage 1–3, with support added at bus 30:**

| Support at bus 30 | Vmin | Buses below 0.95 |
|---|---|---|
| none | 0.7534 | 29 |
| 50 MVAr capacitor | 0.9488 | 1 |
| STATCOM at 1.00 pu | 0.8766 | 23 |

The mitigation study would have concluded "nothing works".

**Fix.** Screening now produces two design cases: the worst **system-wide**
contingency (which drives a network-reinforcement conclusion) and the worst
**urban** contingency, i.e. one touching the modelled urban area, which is the
correct basis for sizing local reactive support. The urban design case is the
outage of line 27–30.

---

### M6 — The dynamic model responded before the disturbance

**File:** `study_dynamic_statcom.m`

All three traces were initialised at the *uncompensated* pre-event voltage:

```matlab
V0(1)=Vpre; Vc(1)=Vpre; Vs(1)=Vpre;
```

with the capacitor and the STATCOM already in service. At `t = 0` the
controller therefore saw an error of about 0.10 pu and started injecting
reactive power, and the capacitor started boosting the bus — a full second
before the contingency at `t = 1 s`. The published figure would have shown a
large "response" to an event that had not happened yet, and the pre-disturbance
voltage would have differed between the three curves.

**Fix.** Each trace is initialised at its own pre-disturbance steady state:
the capacitor by solving the fixed point `V = Vpre + kq·Qrated·V²`, the STATCOM
by setting `Qs(0) = (Vref − Vpre)/kq` (saturated to ±50 MVAr) with the
integrator state made consistent with that output. The only event in the
simulation is now the outage.

---

### M7 — Capacitor sweep too coarse, and over-voltage never rejected

**File:** `study_mitigations.m`

Sizes were `10:10:50` MVAr. The proposal asks for the **minimum effective**
size, and the answer lies between two grid points.

**Evidence — capacitor at bus 30 in the critical case:**

| Rating | Vmin | V at bus 30 | Verdict |
|---|---|---|---|
| 10 MVAr | 0.9285 | 0.9465 | not enough |
| **15 MVAr** | **0.9501** | **1.0280** | **minimum effective** |
| 20 MVAr | 0.9600 | 1.1198 | over-voltage |
| 30 MVAr | 0.9737 | 1.3392 | severe over-voltage |
| 40–50 MVAr | — | — | no solution |

Bus 30 has a local sensitivity of 0.0183 pu/MVAr, so 20 MVAr swings it by about
0.3 pu. The original code, with its dead acceptance filter (M2), would have
selected 30 MVAr and reported 1.34 pu as a success.

**Fix.** `cfg.cap_sizes_MVAr = 2.5:2.5:50`, several candidate buses, and
selection restricted to ratings that keep every load bus inside the band.

---

### M8 — The QV sweep never reached the QV nose

**File:** `study_qv.m`

The sweep was `0.80:0.01:1.10`. The Q-V minimum at bus 30 in the critical case
occurs near **0.50 pu**, so the sweep stayed entirely on the upper branch and
the reactive-power margin — the whole point of a QV curve — could not be
computed.

**Fix.** Sweep `0.40:0.01:1.10`, locate the minimum, and report the reactive
margin as the distance from the nose up to Q = 0. Verified values for the
critical case: 13.35 MVAr to hold 1.00 pu, nose at −8.32 MVAr at 0.50 pu.

---

### M9 — `runcpf` failed silently and the fallback was reported as the answer

**File:** `study_cpf.m` — *found after the first live run*

`runcpf` returns `success = 0` rather than throwing when its step control cannot
negotiate the nose, so the original single attempt fell through to the bisection
fallback with no explanation. Bisection finds the largest load factor a plain
Newton power flow can still solve — **144%** — which is a lower bound, because
Newton-Raphson loses convergence slightly before the true nose. Reported without
qualification, that understates the loadability margin.

**Fix.** Three option sets are tried in order (adaptive step with Q limits, fine
step with Q limits, then without Q-limit switching along the path), each failure
reason is printed from `results.cpf.done_msg`, and if all fail the fallback is
labelled explicitly as a lower bound in both the console output and the study
output struct.

---

## MINOR

| # | File | Issue | Fix |
|---|---|---|---|
| m1 | `project_config.m` | `cfg.case_name = 'case30'` is ambiguous — MATPOWER ships both `case30` (generators at 1, 2, 22, 27, 23, 13, with cost data) and `case_ieee30` (generators at 1, 2, 5, 8, 11, 13). The supplied data file declares `function mpc = case30` but contains `case_ieee30` topology, so whichever file is first on the path wins and results are not reproducible. | Local `case_urban30.m` with a documented provenance header. |
| m2 | `apply_demand_response.m` | Critical loads were protected only by the caller passing the right bus list. Nothing enforced it. No MW-shed figure returned, so the report could state the benefit without the cost. | Protection enforced inside the function via `setdiff` with `cfg.critical_buses`; returns MW shed. |
| m3 | `study_weak_bus.m` | Generator buses included in the sensitivity ranking. Their voltage is held at a setpoint, so dV/dλ ≈ 0 by construction and they pad the table with meaningless rows. | Ranking restricted to load buses. |
| m4 | case data | The four regulating transformers had `ratio = 0`. Tap screening therefore *introduced* off-nominal ratios where the data had none, and the report could not state how far a tap had moved from nominal. | Benchmark taps restored (6–9: 0.978, 6–10: 0.969, 4–12: 0.932, 28–27: 0.968); screening records `Tap_original`. |
| m5 | `study_mitigations.m` | STATCOM setpoint fixed at 1.00 pu. Holding bus 30 at 1.00 pu still leaves adjacent radial bus 26 at 0.943 pu — the scheme fails the band while appearing to succeed at the regulated bus. | Setpoint swept over `cfg.statcom_Vref_options`; the lowest setpoint meeting the band is selected (1.03 pu). |
| m6 | `run_pf_safe.m` | The `catch` block hand-built a metrics struct duplicating `case_metrics`, so the two could drift apart. Failure reason was lost. | Single source of truth in `case_metrics.m`, with a `reason` field distinguishing islanded / diverged / error. |
| m7 | `case_metrics.m` | `Vmin` reported over all buses, mixing regulated generator buses with load buses. | Separate `Vmin`/`Vmin_load` and `Vmax`/`Vmax_load`. |
| m8 | `study_cpf.m` | `runcpf` failure produced `NaN` and the study continued silently; `cpf.enforce_q_lims` is not accepted by older MATPOWER versions. | Bisection fallback that finds the same nose point, with the method used recorded in the output and printed. |
| m9 | `screen_contingencies.m`, `study_mitigations.m` | Result arrays grown with `end+1` inside loops. | Pre-allocated where the size is known; retained where it is not, with the growth warning suppressed. |
| m10 | `00_RUN_FULL_PROJECT.m` | No check that the case has realistic reactive limits, so bug C1 could be reintroduced by swapping the case file. | Startup check warns if any `Qmax ≥ 500 MVAr`. Run log written to `results/00_run_log.txt`. |

---

## One thing that was *not* a bug

`study_mitigations.m` added capacitance with `bus(row, BS) = bus(row, BS) + q`.
That is correct: in MATPOWER, `BS` is the shunt susceptance expressed as **MVAr
injected at 1.0 pu**, and the injection then scales with V² automatically. This
is exactly the behaviour the STATCOM presentation describes as the capacitor's
weakness, and it is already modelled properly.
