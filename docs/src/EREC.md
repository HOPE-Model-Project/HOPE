```@meta
CurrentModule = HOPE
```

# EREC Postprocessing

HOPE supports Equivalent Reliability Enhancement Capability (`EREC`) as a postprocessing workflow for `GTEP` cases.

The intended baseline setup for EREC calculation is:
- `planning_reserve_mode: 0`
- a sufficiently high `VOLL` in the baseline energy-only run
- user-selected settings for chronology, `UC`, transmission, aggregation, and other model options

## How to Use EREC

For a normal `GTEP` study, the recommended baseline setup is:

```yaml
planning_reserve_mode: 0
```

Then choose one of the three workflows below:

1. use `calculate_erec(case_path)` if you want HOPE to solve the baseline and calculate `EREC` in one step
2. use `calculate_erec(results)` if you already ran `run_hope()` in the same Julia session
3. use `calculate_erec_from_output(output_path)` if you solved the baseline earlier and saved the HOPE output

Recommended default `HOPE_erec_settings.yml`:

```yaml
enabled: 1
voll_override: null
resource_types:
  - generator
  - storage
resource_scope: built_only
write_outputs: 1
write_cc_to_tables: 0
output_dir_name: output_erec
```

Recommended interpretation:
- `voll_override: null`
  preserve the `VOLL` already used by the baseline case or solved output; this is the recommended default, especially for `calculate_erec(results)` and `calculate_erec_from_output(...)`
- `resource_types: [generator, storage]`
  run generators and storage together by default
- `resource_scope: built_only`
  report `EREC` for the solved fleet: existing resources plus any newly built candidate resources
- use `resource_scope: all` if you also want unbuilt candidates

Important note on `voll_override`:
- `EREC` is sensitive to the `VOLL` used in the baseline energy-limited redispatch.
- When you reuse a solved case with `calculate_erec(results)` or `calculate_erec_from_output(output_path)`, the safest default is to keep the same `VOLL` used in the original solved baseline.
- HOPE now preserves that baseline `VOLL` by default when `voll_override` is omitted or set to `null`.
- If you explicitly set `voll_override` to a different value, HOPE warns because the resulting `EREC` values may no longer be directly comparable to the original solved case.

## Main Functions

### 1. One-step workflow

Use this when you want HOPE to solve the baseline case and then calculate EREC in one call.

```julia
using HOPE
res = HOPE.calculate_erec("ModelCases/my_case")
```

### 2. Reuse an in-memory solved case

Use this when you already ran `run_hope()` in the same Julia session and do not want to solve the baseline again.

```julia
using HOPE
r = HOPE.run_hope("ModelCases/my_case")
erec = HOPE.calculate_erec(r)
```

`run_hope()` returns the solved model together with the loaded inputs, resolved settings, case path, and output path, so `calculate_erec(r)` can reuse that solved baseline directly.

### 3. Reuse a saved output later

Use this when the baseline run was completed earlier and saved to disk.

```julia
using HOPE
erec = HOPE.calculate_erec_from_output("ModelCases/my_case/output")
```

This workflow uses the machine-readable snapshot saved under:

```text
output/postprocess_snapshot/
```

and does **not** re-solve the baseline expansion model.

## Snapshot Saving

Add this line to `HOPE_model_settings.yml` when you want `run_hope()` to save a reusable baseline snapshot:

```yaml
save_postprocess_snapshot: 1       #Int, 0 do not save; 1 save minimal snapshot for later postprocessing such as EREC; 2 save full snapshot with additional solved-run details
```

Recommended meaning:
- `0`: do not save a postprocess snapshot
- `1`: save the minimal snapshot needed for later EREC/postprocessing
- `2`: save the minimal snapshot plus extra solved-run details for debugging/reproducibility

Typical delayed workflow:

```julia
using HOPE
res = HOPE.run_hope("ModelCases/my_case")
erec = HOPE.calculate_erec_from_output("ModelCases/my_case/output")
```

## EREC Settings File

`EREC` uses a separate optional settings file:

```text
Settings/HOPE_erec_settings.yml
```

The optional EREC settings file is read from:

```text
Settings/HOPE_erec_settings.yml
```

Recommended defaults for normal studies are:

```yaml
enabled: 1
voll_override: null
resource_types:
  - generator
  - storage
resource_scope: built_only
write_outputs: 1
write_cc_to_tables: 0
output_dir_name: output_erec
```

If you want unbuilt candidates as well, use:

```yaml
resource_scope: all
```

## Output Files

Typical EREC outputs are:

```text
output/output_erec/erec_results.csv
output/output_erec/erec_summary.csv
```

If `write_cc_to_tables: 1`, HOPE also writes:

```text
output/output_erec/gendata_with_erec_cc.csv
output/output_erec/storagedata_with_erec_cc.csv
```

The returned EREC result dictionary also includes the baseline `EUE`, the detailed `erec_table`, and any exported input tables written during the workflow.

## Suggested Workflow

For larger research studies, the recommended pattern is:

1. run the baseline model once with `run_hope()`
2. save `output/postprocess_snapshot/`
3. later run `calculate_erec_from_output(output_path)` as needed

This avoids repeating the expensive baseline expansion solve.
