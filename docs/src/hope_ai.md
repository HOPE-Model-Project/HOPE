# HOPE-AI: Running HOPE with an LLM Agent

HOPE supports agentic AI control via the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/introduction) — a standard that lets LLMs like Claude directly invoke tools, run models, and read results without any manual scripting. This page explains how to set up the HOPE MCP server so that Claude Desktop can warm up Julia, launch HOPE runs, and analyze outputs in natural language.

!!! note "PowerAgent community"
    The HOPE MCP server is part of [PowerAgent](https://poweragent.seas.harvard.edu/) — an open-source community for agentic AI in power systems, maintained by the [Power and AI Initiative (PAI)](https://pai.seas.harvard.edu/) at Harvard SEAS. The HOPE server is also distributed through [PowerMCP](https://github.com/Power-Agent/PowerMCP/tree/main/HOPE), a collection of MCP servers for power system software.

---

## Available Tools

Once configured, Claude Desktop will have access to five HOPE tools:

| Tool | Description |
|------|-------------|
| `hope_warmup` | Pre-compiles the Julia/HOPE environment in the background. Call this once per session before the first run. Returns a `job_id` immediately. |
| `hope_run_hope` | Launches a HOPE optimization run in the background. Returns a `job_id` immediately — the MCP server stays responsive while Julia runs. |
| `hope_job_status` | Polls a background job (warmup or run) for progress. Returns elapsed time, stdout tail, and the full output summary when the job completes. |
| `hope_case_info` | Reads case settings and output file inventory instantly — no Julia required. |
| `hope_output_summary` | Reads and summarizes existing output CSVs (system cost, capacity builds, storage) instantly — no Julia required. |

---

## Prerequisites

- **HOPE** cloned and Julia environment instantiated (see [Installation](@ref))
- **Python** ≥ 3.10 (the MCP server is a Python package)
- **uv** ([astral.sh/uv](https://astral.sh/uv)) — fast Python package manager
- **Claude Desktop** ([claude.ai/download](https://claude.ai/download)) or any MCP-compatible LLM host

---

## One-Time Setup

### Step 1 — Install `uv`

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
    Run `julia -e 'println(Sys.BINDIR)'` in a terminal to print the exact path to your Julia binary directory. The binary is `julia` (macOS/Linux) or `julia.exe` (Windows) inside that directory.

    If `julia` is already on your system PATH, you can omit the `HOPE_JULIA_BIN` key entirely.

Restart Claude Desktop after editing the config.

---

## Typical Claude Desktop Session

Julia's first startup includes precompilation which can take several minutes. The recommended flow is:

**1. Warm up Julia (once per session)**

> *"Warm up Julia for HOPE."*

Claude calls `hope_warmup`, which launches Julia precompilation in the background and returns a `job_id`. Claude then polls `hope_job_status` until precompilation finishes (~3–5 min on first call, much faster on subsequent calls in the same session).

**2. Run a HOPE case**

> *"Run the md_gtep_clean HOPE case."*

Claude calls `hope_run_hope`, which launches HOPE as a background process and returns a `job_id` immediately. Claude polls `hope_job_status` until the run completes. When done, the output summary (system costs, capacity builds) is returned automatically.

**3. Inspect results**

> *"Summarize the generation capacity investments and system cost."*

Claude calls `hope_output_summary` (instant — reads the CSVs, no Julia needed) and presents the analysis.

**4. Explore settings**

> *"What solver and model mode is the md_gtep_clean case using?"*

Claude calls `hope_case_info` which reads `Settings/HOPE_model_settings.yml` and returns the configuration.

---

## Supported Cases

The current server whitelists one case:

| Case ID | Path |
|---------|------|
| `md_gtep_clean` | `ModelCases/MD_GTEP_clean_case` |

The whitelist is defined in `tools/hope_mcp_server/src/hope_mcp_server/core.py` (`CASE_PATHS` dict). To add more cases, extend that dictionary and re-run `uv sync`.

---

## Troubleshooting

**MCP server doesn't appear in Claude Desktop**  
Verify the config JSON is valid (no trailing commas, no syntax errors). Restart Claude Desktop fully (quit and reopen).

**`uv` command not found**  
Restart your terminal after installing `uv`, or manually add `~/.local/bin` (macOS/Linux) or `%USERPROFILE%\.local\bin` (Windows) to your PATH.

**Julia warmup job keeps running for a long time**  
This is expected on the very first call — Julia downloads and compiles ~130 packages. Subsequent warmups in the same session are instant since the cache is warm.

**`hope_run_hope` fails with `hope_environment_not_instantiated`**  
Call `hope_warmup` first and wait for it to complete before calling `hope_run_hope`.

**Job ID not found**  
Job IDs are in-memory and only valid for the current MCP server session. If Claude Desktop was restarted, old job IDs are gone — start a new warmup/run.

---

## Further Resources

- [PowerAgent community](https://poweragent.seas.harvard.edu/)
- [PowerMCP repository](https://github.com/Power-Agent/PowerMCP) — MCP servers for HOPE, PyPSA, OpenDSS, PowerWorld, and more
- [Model Context Protocol docs](https://modelcontextprotocol.io/introduction)
- [PowerMCP Tutorial PDF](https://raw.githubusercontent.com/Power-Agent/PowerMCP/main/PowerMCP_Tutorial.pdf)
