This folder holds benchmark-only assets used to generate the resource aggregation comparison examples in the docs.

Contents:
- `scripts/`
  - Julia helpers that create and run the final GTEP and PCM comparison cases saved under `ModelCases/`
- `seed_cases/`
  - small PCM seed cases reused by the comparison generators

These files are not required for normal HOPE model usage. They are kept under `tools/` so the main `ModelCases/` directory stays focused on user-facing examples and shipped study cases.
