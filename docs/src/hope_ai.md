# HOPE-AI: Running HOPE with an LLM Agent

HOPE supports agentic AI control via the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/introduction) — a standard that lets LLMs like Claude directly invoke tools, run models, and read results without any manual scripting. This page explains how to set up the HOPE MCP server so that Claude Desktop can warm up Julia, launch HOPE runs, modify settings, inspect outputs, and compare scenarios in natural language.

!!! note "PowerAgent community"
    The HOPE MCP server is part of [PowerAgent](https://poweragent.seas.harvard.edu/) — an open-source community for agentic AI in power systems, maintained by the [Power and AI Initiative (PAI)](https://pai.seas.harvard.edu/) at Harvard SEAS. The HOPE server is also distributed through [PowerMCP](https://github.com/Power-Agent/PowerMCP/tree/main/HOPE), a collection of MCP servers for power system software.

---

## Available Tools

Once configured, Claude Desktop will have access to **16 HOPE tools** organized into six groups:

### Job Execution

| Tool | Description |
|------|-------------|
| `hope_warmup` | Pre-compiles the Julia/HOPE environment in the background. Call once per session before the first run. Returns a `job_id` immediately. |
| `hope_run_hope` | Launches a HOPE single-case optimization run (GTEP or PCM) in the background. Returns a `job_id` immediately. |
| `hope_run_holistic` | Launches a two-stage GTEP→PCM holistic workflow: Stage 1 solves capacity expansion; Stage 2 fixes the built fleet and runs production-cost dispatch. Returns a `job_id` immediately. |
| `hope_run_erec` | Launches EREC (Equivalent Reliability Enhancement Capability) postprocessing on a completed run to quantify each resource's reliability contribution. Returns a `job_id` immediately. |
| `hope_job_status` | Polls any background job for progress. Returns elapsed time, stdout tail, and the full output summary when the job completes. |

### Settings Management

| Tool | Description |
|------|-------------|
| `hope_update_settings` | Patches any field in `HOPE_model_settings.yml` — e.g., change `carbon_policy`, `solver`, `network_model`, or `unit_commitment`. Validates each value, backs up the original file, and warns on contradictions. |
| `hope_validate_case` | Checks settings for contradictions and missing files (e.g., `write_shadow_prices=1` without `network_model > 0`, or a missing solver settings file). Returns a warning list and `is_valid` flag. |

### Output Reading

| Tool | Description |
|------|-------------|
| `hope_case_info` | Reads case settings and output file inventory instantly — no Julia required. |
| `hope_output_summary` | Reads and summarizes existing output CSVs (system cost, capacity builds, storage builds) instantly — no Julia required. |
| `hope_read_output` | Reads any specific output CSV with optional column filters — e.g., dispatch for a single zone, or capacity for one technology. |
| `hope_emission_compliance` | Parses `carbon_emissions.csv` and `rps_target.csv` to report per-state compliance status, violation amounts, and penalty costs. |
| `hope_nodal_prices` | Reads locational marginal prices (LMPs) from `nodal_prices.csv`, optionally filtered by bus/zone and hour range. |

### Scenario Comparison

| Tool | Description |
|------|-------------|
| `hope_compare_cases` | Compares system cost, capacity builds (MW by technology), storage builds (MWh), and CO2 emissions across two or more cases. Returns side-by-side tables and diffs relative to a baseline. |

### Audit Tools

| Tool | Description |
|------|-------------|
| `hope_rep_day_audit` | Summarizes representative-period clustering: period assignments, weights, total representative hours, and compression ratio vs. a full 8760-hour year. |
| `hope_aggregation_audit` | Summarizes resource aggregation: raw-to-cluster mapping, reduction ratio (e.g., 120 generators to 30 clusters), and per-cluster capacity. |

### Dashboard

| Tool | Description |
|------|-------------|
| `hope_open_dashboard` | Launches the local HOPE Dash dashboard for a completed case run and returns its URL. Automatically picks the GTEP dashboard (port 8051) or the PCM dashboard (port 8050) based on `model_mode`. If a dashboard is already running on the target port, returns the existing URL immediately. |
| `hope_close_dashboard` | Stops a dashboard launched by `hope_open_dashboard`. Pass `port=8051` or `port=8050` to stop a specific dashboard, or omit `port` to stop all dashboards tracked in the current session. |

---

## Prerequisites

- **HOPE** cloned and Julia environment instantiated (see [Installation](@ref))
- **Python** >= 3.10 (the MCP server is a Python package)
- **uv** ([astral.sh/uv](https://astral.sh/uv)) — fast Python package manager
- **Claude Desktop** ([claude.ai/download](https://claude.ai/download)) or any MCP-compatible LLM host

---

## One-Time Setup

### Step 1 — Install uv

**Windows (PowerShell):**

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

**macOS / Linux:**

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Restart your terminal after installation so `uv` is on your PATH.

### Step 2 — Sync the MCP server Python package

```bash
uv --directory /path/to/HOPE/tools/hope_mcp_server sync
```

This creates a local `.venv` inside `tools/hope_mcp_server/` with all dependencies (including the `mcp` package).

### Step 3 — Configure Claude Desktop

Locate your Claude Desktop config file:

- **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
  (typically `C:\Users\<user>\AppData\Roaming\Claude\claude_desktop_config.json`)
- **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`

Add the `hope` server entry:

**Windows example:**

```json
{
  "mcpServers": {
    "hope": {
      "command": "uv",
      "args": [
        "--directory",
        "C:\\path\\to\\HOPE\\tools\\hope_mcp_server",
        "run",
        "hope-mcp-server"
      ],
      "env": {
        "HOPE_REPO_ROOT": "C:\\path\\to\\HOPE",
        "HOPE_JULIA_BIN": "C:\\Users\\<user>\\.julia\\juliaup\\julia-1.x.y+0.x64.w64.mingw32\\bin\\julia.exe"
      }
    }
  }
}
```

**macOS / Linux example:**

```json
{
  "mcpServers": {
    "hope": {
      "command": "uv",
      "args": [
        "--directory",
        "/path/to/HOPE/tools/hope_mcp_server",
        "run",
        "hope-mcp-server"
      ],
      "env": {
        "HOPE_REPO_ROOT": "/path/to/HOPE",
        "HOPE_JULIA_BIN": "/path/to/.julia/juliaup/julia-1.x.y+0.aarch64.apple.darwin14/bin/julia"
      }
    }
  }
}
```

!!! tip "Finding your Julia binary path"
    Run `julia -e 'println(Sys.BINDIR)'` in a terminal to print the exact path to your Julia binary directory. The binary is `julia` (macOS/Linux) or `julia.exe` (Windows) inside that directory. If `julia` is already on your system PATH, you can omit the `HOPE_JULIA_BIN` key entirely.

Restart Claude Desktop after editing the config.

---

## Typical Claude Desktop Session

Julia's first startup includes precompilation which can take several minutes. The recommended flow is:

**1. Warm up Julia (once per session)**

> *"Warm up Julia for HOPE."*

Claude calls `hope_warmup`, which launches Julia precompilation in the background and returns a `job_id`. Claude then polls `hope_job_status` until precompilation finishes (~3-5 min on first call, much faster on subsequent calls in the same session).

**2. Validate and optionally update settings**

> *"Check the md_gtep_clean case settings and enable the carbon cap."*

Claude calls `hope_validate_case` to detect any contradictions, then `hope_update_settings` to patch `carbon_policy: 1` into `HOPE_model_settings.yml`. The original file is backed up automatically.

**3. Run a HOPE case**

> *"Run the md_gtep_clean HOPE case."*

Claude calls `hope_run_hope` (or `hope_run_holistic` for a two-stage GTEP-PCM run), which launches HOPE as a background process and returns a `job_id` immediately. Claude polls `hope_job_status` until the run completes. When done, the output summary is returned automatically.

**4. Inspect results**

> *"Summarize the capacity investments. Are we in compliance with the carbon cap?"*

Claude calls `hope_output_summary` for the cost and build summary, then `hope_emission_compliance` to check carbon and RPS policy compliance — all instant, reading only the output CSVs.

**5. Drill into specifics**

> *"Show me the hourly dispatch for solar in zone MD."*

Claude calls `hope_read_output` with `filename="dispatch.csv"` and `filters={"Zone": "MD", "Technology": "SolarPV"}`.

**6. Compare scenarios**

> *"How does cost and emissions change if I also enable the RPS target? Run that version and compare."*

Claude calls `hope_update_settings` to enable `clean_energy_policy: 1`, re-runs with `hope_run_hope`, then calls `hope_compare_cases` to get a side-by-side diff of cost, capacity, and CO2.

---

## Supported Cases

The server reads the `CASE_PATHS` registry in `tools/hope_mcp_server/src/hope_mcp_server/core.py`:

```python
CASE_PATHS = {
    "md_gtep_clean": Path("ModelCases/MD_GTEP_clean_case"),
}
```

To add more cases, extend this dictionary with additional `case_id: relative_path` entries and restart Claude Desktop.

---

## Example Prompts

The prompts below demonstrate what you can ask Claude in a typical session. Copy them verbatim or adapt them to your case.

### Job Execution

**`hope_warmup` — Pre-compile Julia before the first run**

> "Warm up Julia for HOPE."
> "Initialize the HOPE Julia environment and let me know when it's ready."
> "Pre-compile HOPE so the first model run starts fast."

**`hope_run_hope` — Launch a single-case HOPE optimization**

> "Run the `md_gtep_clean` HOPE case."
> "Start a HOPE GTEP run for the Maryland clean energy case."
> "Launch a HOPE model run and tell me when it finishes."

**`hope_run_holistic` — Two-stage GTEP→PCM workflow**

> "Run the holistic two-stage analysis: first solve capacity expansion, then re-run production cost with the built fleet fixed."
> "Execute a holistic HOPE run for the `md_gtep_clean` case using the `md_pcm_clean` case for the PCM stage."

**`hope_run_erec` — EREC reliability postprocessing**

> "Run EREC on the completed `md_gtep_clean` run to compute each resource's reliability contribution."
> "After the GTEP run finishes, quantify how much capacity credit each new solar and wind plant earns."

**`hope_job_status` — Poll a background job**

> "What's the status of job `a3f8c21b`?"
> "Is the HOPE run still going? Give me the latest output."
> "Check whether the warmup job has finished."

---

### Settings Management

**`hope_update_settings` — Patch model settings**

> "Enable the carbon cap in the `md_gtep_clean` case."
> "Switch the solver to HiGHS for the Maryland case."
> "Turn on unit commitment and nodal network modeling."
> "Set the carbon price to \$50/ton in `md_gtep_clean`."
> "Disable the RPS target and enable the clean energy standard instead."
> "Enable shadow price output and make sure the network model is set to nodal."

**`hope_validate_case` — Check for contradictions before running**

> "Validate the `md_gtep_clean` case settings before I run it."
> "Check whether there are any contradictions or missing files in this case."
> "Is this case configured correctly to produce nodal prices?"

---

### Output Reading

**`hope_case_info` — Inspect settings and output file inventory**

> "What settings is the `md_gtep_clean` case using?"
> "List all the output files from the last HOPE run."

**`hope_output_summary` — Summarize cost and capacity results**

> "Summarize the results from the `md_gtep_clean` run."
> "What are the total system costs, new capacity builds, and storage investments?"
> "Give me a high-level overview of the capacity expansion results."

**`hope_read_output` — Read any specific output CSV**

> "Show me the dispatch for solar PV in zone MD."
> "Read the `capacity.csv` output and filter for wind technologies."
> "What does the `transmission_flows.csv` file look like for the first 24 hours?"
> "Show me storage charge/discharge for the BESS resources in zone PJM."

**`hope_emission_compliance` — Check carbon and RPS compliance**

> "Are we in compliance with the carbon cap? How close are we to the limit?"
> "Summarize per-state carbon and RPS compliance from the latest run."
> "Did any state violate its RPS target? What are the penalty costs?"

**`hope_nodal_prices` — Read locational marginal prices**

> "What are the average nodal prices across all buses?"
> "Show me the LMPs for buses in zone MD for hours 1–48."
> "Which bus had the highest LMP during the peak demand period?"

---

### Scenario Comparison

**`hope_compare_cases` — Side-by-side scenario comparison**

> "Compare costs and emissions between the baseline and the carbon cap cases."
> "How does capacity investment change if I enable the RPS target? Run that version and compare."
> "Show me a side-by-side table of capacity builds, system cost, and CO2 across the three Maryland scenarios."
> "What's the cost difference between the nodal and zonal network models?"

---

### Audit Tools

**`hope_rep_day_audit` — Representative period summary**

> "Summarize the representative-day clustering for the `md_gtep_clean` case."
> "How many representative periods are used, and what's the compression ratio versus a full year?"
> "Which weeks are mapped to each representative day?"

**`hope_aggregation_audit` — Resource aggregation summary**

> "How many generator clusters were created from the raw resource data?"
> "Summarize the resource aggregation: how many generators were grouped into how many clusters?"
> "Show me the per-cluster capacity for the wind aggregation."

---

### Dashboard

**`hope_open_dashboard` / `hope_close_dashboard` — Local interactive dashboard**

> "Open the dashboard for the `md_gtep_clean` case."
> "Launch the GTEP dashboard so I can explore capacity builds interactively."
> "Close the dashboard when I'm done."
> "Stop all running dashboards."

---

## Troubleshooting

**MCP server does not appear in Claude Desktop**
Verify the config JSON is valid (no trailing commas, no syntax errors). Restart Claude Desktop fully (quit and reopen).

**`uv` command not found**
Restart your terminal after installing `uv`, or manually add `~/.local/bin` (macOS/Linux) or `%USERPROFILE%\.local\bin` (Windows) to your PATH.

**Julia warmup job keeps running for a long time**
This is expected on the very first call — Julia downloads and compiles ~130 packages. Subsequent warmups in the same session are instant since the cache is warm.

**`hope_run_hope` fails with `hope_environment_not_instantiated`**
Call `hope_warmup` first and wait for it to complete before calling `hope_run_hope`.

**`hope_run_erec` fails with `snapshot_not_found`**
Set `save_postprocess_snapshot: 1` in `HOPE_model_settings.yml` (use `hope_update_settings`) and re-run the case before calling `hope_run_erec`.

**`hope_nodal_prices` returns `price_file_not_found`**
LMP output requires `network_model > 0` and `write_shadow_prices: 1` in settings. Use `hope_update_settings` to enable both, then re-run.

**Job ID not found**
Job IDs are in-memory and only valid for the current MCP server session. If Claude Desktop was restarted, old job IDs are gone — start a new warmup/run.

---

## Further Resources

- [PowerAgent community](https://poweragent.seas.harvard.edu/)
- [PowerMCP repository](https://github.com/Power-Agent/PowerMCP) — MCP servers for HOPE, PyPSA, OpenDSS, PowerWorld, and more
- [Model Context Protocol docs](https://modelcontextprotocol.io/introduction)
- [PowerMCP Tutorial PDF](https://raw.githubusercontent.com/Power-Agent/PowerMCP/main/PowerMCP_Tutorial.pdf)
