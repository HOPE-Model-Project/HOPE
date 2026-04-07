# HOPE Version Differences

This note is a short release-style guide to the practical differences between the legacy `master` branch and the newer `master-dev` branch.

## Executive Summary

- `master` is the older HOPE baseline.
- `master-dev` is the expanded next-generation branch.
- The change is not a minor patch. It adds new workflows, broader APIs, stronger docs, more tests, and a much larger case-building surface.

## Highlights In master-dev

### Expanded modeling workflow surface

`master-dev` adds major new workflow layers on top of the older `master` baseline:

- representative-day support in `src/rep_day.jl`
- resource aggregation support in `src/aggregation.jl`
- EREC postprocessing in `src/erec.jl`
- shared network and utility helpers in `src/network_utils.jl`, `src/utils.jl`, and `src/constants.jl`
- fresh-clone holistic execution through `HOPE.run_hope_holistic_fresh(...)`

### Larger public API

Compared with `master`, `master-dev` exports additional user-facing functionality, including:

- `calculate_erec`
- `calculate_erec_from_output`
- `default_aggregation_settings`
- `default_erec_settings`
- `default_rep_day_settings`
- `load_aggregation_settings`
- `load_erec_settings`
- `load_postprocess_snapshot`
- `load_rep_day_settings`
- `resolve_rep_day_time_periods`
- `run_hope_holistic_fresh`

That means more workflows can be executed directly from the HOPE module instead of relying only on case-specific scripts.

### Stronger documentation and examples

`master-dev` broadens the user-facing documentation substantially:

- dedicated documentation for representative days, resource aggregation, and EREC
- richer example-case pages for Maryland holistic, PJM MD100, USA64, RTS24, Germany PCM, and ISO-NE 250-bus
- expanded run instructions for direct and fresh-clone holistic workflows
- added developer, contributing, and reference pages

### Stronger test and automation surface

`master-dev` also adds:

- a dedicated `test/Project.toml`
- targeted tests for aggregation, representative days, holistic execution, EREC, and regressions
- GitHub workflows for tests, docs, linting, and repo maintenance
- issue templates and maintenance automation

### Broader case-building utility layer

Compared with `master`, `master-dev` introduces or materially expands support for:

- Maryland full-year holistic benchmark construction
- Germany PCM build and validation workflows
- ISO-NE 250-bus workflows
- USA 64-zone GTEP conversion and mapping helpers
- repo-level holistic audit and case-build tooling under `tools/repo_utils/`

## What Stayed Stable

The core HOPE model identity is still shared across both branches:

- Julia + JuMP model stack
- primary `run_hope(...)` entry point
- `GTEP` and `PCM` remain the main production model modes
- YAML-driven case settings and the `ModelCases/` directory structure

So `master-dev` should be treated as an expanded HOPE branch, not a separate project.

## Migration Notes For Existing Users

If you worked from `master`, the most visible changes in `master-dev` are:

- more built-in workflows beyond a single case solve
- more documented example cases to start from
- direct support for representative-day and resource-aggregation experiments
- a more reusable `GTEP -> PCM` holistic workflow
- built-in EREC postprocessing support

## Current Self-Consistency Status

At the source level, `master-dev` is internally consistent in the main feature areas reviewed here:

- new public workflows are exported from `src/HOPE.jl`
- those workflows are documented in `docs/src/`
- the expanded `tools/repo_utils/` surface is documented
- workspace diagnostics are currently clean

One caveat remains environment-specific rather than code-specific:

- generated docs can lag `docs/src/` until the documentation site is rebuilt successfully in an environment where Julia package cache loading is not blocked

## Recommendation

For new work, use `master-dev` as the active HOPE branch. Treat `master` as the older reference surface for historical comparison, legacy workflows, or backward-looking validation.