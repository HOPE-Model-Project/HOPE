# HOPE MCP Server

This package provides a small stdio MCP server for local HOPE workflows in Claude Desktop.

## Tools

- `hope_case_info`
- `hope_run_hope`
- `hope_output_summary`

The v1 server intentionally supports only one whitelisted case id:

- `md_gtep_clean` -> `/Users/qianzhang/Documents/GitHub/HOPE/ModelCases/MD_GTEP_clean_case`

## One-time setup

1. Sync the Python package with `uv`:

```bash
uv --directory /Users/qianzhang/Documents/GitHub/HOPE/tools/hope_mcp_server sync
```

2. Make sure the HOPE Julia environment is instantiated:

```bash
/Users/qianzhang/.julia/juliaup/julia-1.11.6+0.aarch64.apple.darwin14/bin/julia --project=/Users/qianzhang/Documents/GitHub/HOPE -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
```

## Claude Desktop config

Add this server entry to your Claude Desktop MCP config:

```json
{
  "mcpServers": {
    "hope": {
      "command": "uv",
      "args": [
        "--directory",
        "/Users/qianzhang/Documents/GitHub/HOPE/tools/hope_mcp_server",
        "run",
        "hope-mcp-server"
      ],
      "env": {
        "HOPE_REPO_ROOT": "/Users/qianzhang/Documents/GitHub/HOPE",
        "HOPE_JULIA_BIN": "/Users/qianzhang/.julia/juliaup/julia-1.11.6+0.aarch64.apple.darwin14/bin/julia"
      }
    }
  }
}
```

## Local run

```bash
HOPE_JULIA_BIN=/Users/qianzhang/.julia/juliaup/julia-1.11.6+0.aarch64.apple.darwin14/bin/julia \
uv --directory /Users/qianzhang/Documents/GitHub/HOPE/tools/hope_mcp_server run hope-mcp-server
```

## Test

```bash
uv --directory /Users/qianzhang/Documents/GitHub/HOPE/tools/hope_mcp_server run \
  python -m unittest discover -s tests -v
```
