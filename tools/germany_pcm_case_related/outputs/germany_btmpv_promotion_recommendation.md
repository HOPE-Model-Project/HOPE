## Germany BTM-PV Promotion Recommendation

This note summarizes the winter/summer low-base-high sensitivity check for the calibrated Germany BTM-PV correction.

Reference outputs:

- `germany_btmpv_sensitivity_metrics.csv`
- `germany_btmpv_sensitivity_comparison.csv`
- `germany_btmpv_winter_summer_validation_note.md`

Sensitivity design:

- `low`: `0.75x` calibrated BTM-PV
- `base`: `1.00x` calibrated BTM-PV
- `high`: `1.25x` calibrated BTM-PV

### Main result

The calibrated BTM-PV layer is robust enough to promote as the preferred Germany baseline.

The sensitivity pattern is stable:

- winter responds only mildly across low/base/high
- summer responds more strongly, but smoothly and monotonically
- congestion geography does not collapse or jump to implausible new regions

### Winter (`jan_week3`)

Realized BTM-PV share of gross load:

- low: `0.523%`
- base: `0.697%`
- high: `0.872%`

Cost:

- no-BTM: `178.647M`
- low: `176.768M`
- base: `176.145M`
- high: `175.525M`

Other effects:

- emissions fall monotonically as BTM-PV increases
- mean load-weighted LMP changes only slightly
- binding hours and congestion rent stay almost flat
- curtailment is essentially unchanged

Interpretation:

- In winter the BTM-PV layer behaves conservatively.
- This is what we want: it improves cost and emissions a bit without materially reshaping congestion.

### Summer (`jul_week3`)

Realized BTM-PV share of gross load:

- low: `3.082%`
- base: `4.109%`
- high: `5.136%`

Cost:

- no-BTM: `63.328M`
- low: `59.708M`
- base: `58.616M`
- high: `57.570M`

Other effects:

- mean load-weighted LMP falls monotonically: `19.21 -> 18.64 -> 18.29 -> 18.01`
- average nodal spread falls monotonically: `28.24 -> 27.73 -> 27.11 -> 26.90`
- binding hours fall from `326` to `321`, then `308`, then `308`
- absolute congestion rent falls from `11.42M` to `10.92M`, then `10.59M`, then `10.43M`
- emissions fall monotonically
- curtailment rises monotonically: `197.7 GWh -> 207.6 GWh -> 215.9 GWh -> 228.9 GWh`

Interpretation:

- Summer is where BTM-PV matters most, and the response is smooth rather than erratic.
- The increase in curtailment is directionally plausible because more behind-the-meter solar deepens midday surplus.
- The high case is still physically plausible, but it is more aggressive than we need for a default baseline.

### Recommendation

Promote the calibrated `base` BTM-PV case as the preferred Germany nodal baseline.

Keep:

- `no-BTM` as a reference benchmark
- `low` and `high` as sensitivity bounds for research robustness checks

Recommended operating rule:

- use `base` BTM-PV for primary Germany results
- rerun `low` and `high` only when reporting sensitivity or uncertainty

### Why `base` and not `high`

The `high` case still behaves reasonably, but it pushes summer further into surplus and curtailment.

The `base` case is the best balance of:

- externally anchored calibration
- realistic seasonal behavior
- meaningful net-load improvement
- conservative research posture

### Suggested next follow-up

If we want to move from a strong research prototype toward a more frozen research-ready benchmark, the next step should be documentation and validation packaging rather than another major model redesign:

- freeze the preferred Germany baseline as `base` BTM-PV
- keep the no-BTM and low/high cases as reference sensitivity cases
- write one concise Germany model-validation memo that documents:
  - load allocation method
  - offshore mapping fix
  - empirical congestion benchmark
  - BTM-PV promotion decision
