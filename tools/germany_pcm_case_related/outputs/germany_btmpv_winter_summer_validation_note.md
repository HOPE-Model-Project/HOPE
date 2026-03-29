## Calibrated BTM-PV Winter and Summer Check

This note compares the accelerated calibrated BTM-PV validation runs against the preserved no-BTM seasonal baseline for:

- `winter`: `GERMANY_PCM_nodal_jan_week3_baseline_case`
- `summer`: `GERMANY_PCM_nodal_jul_week3_baseline_case`

Reference files:

- `germany_seasonal_week_cost_summary_pre_btmpv.csv`
- `germany_btmpv_winter_summer_comparison.csv`
- `germany_btmpv_winter_summer_post_metrics.csv`

### Main result

The calibrated BTM-PV effect looks directionally credible.

- In winter, realized BTM-PV stays small at about `0.70%` of gross load and changes congestion only marginally.
- In summer, realized BTM-PV rises to about `4.11%` of gross load and reduces cost, emissions, LMPs, binding hours, and congestion rent while preserving the same broad hotspot geography.

### Winter (`jan_week3`)

- Total cost: `178.647M -> 176.145M` (`-1.40%`)
- Emissions: `2.788 Mt -> 2.724 Mt` (`-63.98 kt`)
- Mean load-weighted LMP: `35.36 -> 35.39 $/MWh` (`+0.02`)
- Average nodal spread: `26.02 -> 26.24 $/MWh`
- Max nodal spread: `55.43 -> 61.97 $/MWh`
- Binding hours: `536 -> 537`
- Absolute congestion rent: `9.10M -> 9.15M`
- Curtailment: `131.07 GWh -> 131.16 GWh`

Interpretation:

- The winter effect is modest, which is what we would expect from a conservative BTM-PV correction in a low-solar week.
- Cost and emissions improve, while congestion metrics stay almost unchanged.
- That is a healthy sign that the BTM-PV layer is not overpowering the winter system.

### Summer (`jul_week3`)

- Total cost: `63.328M -> 58.616M` (`-7.44%`)
- Emissions: `222.6 kt -> 176.9 kt` (`-45.7 kt`)
- Mean load-weighted LMP: `19.21 -> 18.29 $/MWh`
- Average nodal spread: `28.24 -> 27.11 $/MWh`
- Max nodal spread: `83.77 -> 81.80 $/MWh`
- Binding hours: `326 -> 308`
- Absolute congestion rent: `11.42M -> 10.59M`
- Curtailment: `197.70 GWh -> 215.90 GWh`

Interpretation:

- The summer effect is materially larger, which is again what we would expect.
- Net load falls most in the season when rooftop PV should matter most.
- Congestion and prices soften, but they do not collapse.
- Curtailment rises by about `18.2 GWh`, which is also directionally plausible because more behind-the-meter solar can deepen midday surplus conditions.

### Summer hotspot continuity

The summer hotspot geography remains stable before and after BTM-PV.

Top recurring post-BTM summer lines are still dominated by:

- `TransnetBW` internal lines `4`, `9`, and `828`
- `Amprion` internal line `627`
- `50Hertz` internal line `772`

Compared with the archived pre-BTM summer output:

- line `4`: `105 -> 96` binding hours
- line `9`: `73 -> 62`
- line `627`: `58 -> 77`
- line `828`: `38 -> 37`
- line `772`: `15 -> 13`

So the BTM-PV correction changes intensity more than geography.

### Recommendation

The calibrated BTM-PV layer is strong enough to matter and conservative enough to look believable.

Recommended next step:

- keep the no-BTM and BTM versions both available for now
- promote calibrated BTM-PV as the preferred experimental baseline for further validation
- if later validation still looks good, make it the default Germany nodal load treatment
