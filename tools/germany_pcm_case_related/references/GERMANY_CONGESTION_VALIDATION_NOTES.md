# Germany Congestion Validation Notes

## External benchmark

Official German sources consistently describe a structural north-to-south congestion problem:

- Bundesnetzagentur states that if high wind generation and imports into northern Germany coincide with high demand and low solar generation in southern Germany, the resulting north-to-south transfers can overload the grid.
  - Source: https://www.bundesnetzagentur.de/SharedDocs/Pressemitteilungen/EN/2020/20200504_Reservebedarf.html
- Bundesnetzagentur describes SuedOstLink as a key project for expanding electricity transmission capacity between northern and southern Germany.
  - Source: https://www.bundesnetzagentur.de/SharedDocs/Pressemitteilungen/EN/2024/20240429_SuedOst_Pa.html
- SMARD reports ongoing congestion-management volumes and costs and defines redispatch, grid reserve, and countertrading as active measures used to avoid or remove congestion.
  - Source: https://www.smard.de/page/en/topic-article/212250/214060/congestion-management

Academic and applied research lines up with the same story:

- Energies (2020), "Insights on Germany's Future Congestion Management from a Multi-Model Approach", analyzes future German congestion management under high-renewable conditions.
  - Source: https://www.mdpi.com/1996-1073/13/16/4176
- FfE (2026) argues that more wind generation in southern Germany can reduce redispatch costs, which is consistent with congestion being driven by spatial imbalance between renewable supply and southern demand.
  - Source: https://www.ffe.de/en/publications/wind-energy-in-the-south-systemic-savings-through-avoided-redispatch-costs/

## What the HOPE 2-day dynamic case shows

Case checked:

- `ModelCases/GERMANY_PCM_nodal_jan_2day_egon_dynamic_case`

Observed pattern from `output/line_shadow_price.csv`:

- Highest binding lines are internal to `TenneT` and `TransnetBW`, with smaller internal congestion in `Amprion` and `50Hertz`.
- The strongest `TenneT` binding lines in this 48-hour run sit in the northwest / north-central footprint.
- The strongest `TransnetBW` binding lines sit in southwest Germany.

Interpretation:

- This is directionally compatible with the real German congestion story, because bottlenecks often emerge inside large TSO footprints rather than only at zonal borders.
- A short 48-hour January run is not enough to validate the full annual German congestion climatology.
- If future longer runs show persistent stress in northern export areas plus southern/southwestern receiving areas, that would be a stronger validation signal.

## Practical validation checklist for future runs

For a Germany nodal case to look broadly realistic, we should expect at least some of the following:

- Congestion clustering in northern or northwestern wind-heavy areas and along transfer paths toward the south.
- Congestion or scarcity signals in southern / southwestern Germany, especially `TransnetBW` and southern `TenneT`.
- Redispatch-like behavior where generation is reduced "in front of" congestion and raised "behind" it.
- Better south-located renewable supply reducing, rather than increasing, north-to-south transport stress.

If a long Germany run instead shows congestion dominated by unrelated east-west corridors or by only a few isolated local artifacts, that would be a warning sign to revisit the network and nodal-load assumptions.
