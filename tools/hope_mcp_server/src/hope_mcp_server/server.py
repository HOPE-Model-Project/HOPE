from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP

from .core import hope_case_info, hope_job_status, hope_output_summary, hope_run_hope, hope_warmup

mcp = FastMCP(
    "hope-mcp",
    instructions=(
        "HOPE proof-of-concept MCP server for the local Julia repository. "
        "Use the whitelisted case id md_gtep_clean."
    ),
)


@mcp.tool(
    name="hope_warmup",
    description=(
        "Pre-compile the HOPE Julia environment in the background so subsequent hope_run_hope calls "
        "start fast. Returns a job_id immediately. Call hope_job_status to check progress. "
        "Run this once per Claude Desktop session before the first hope_run_hope."
    ),
)
def hope_warmup_tool() -> dict[str, Any]:
    return hope_warmup()


@mcp.tool(
    name="hope_job_status",
    description=(
        "Poll the status of a background Julia job launched by hope_warmup or hope_run_hope. "
        "Returns status ('running' or 'done'), elapsed time, stdout tail, and on success the "
        "output summary. Call repeatedly until status is 'done'."
    ),
)
def hope_job_status_tool(job_id: str) -> dict[str, Any]:
    return hope_job_status(job_id)


@mcp.tool(
    name="hope_case_info",
    description="Return metadata and output inventory for the whitelisted HOPE case.",
)
def hope_case_info_tool(case_id: str = "md_gtep_clean") -> dict[str, Any]:
    return hope_case_info(case_id)


@mcp.tool(
    name="hope_output_summary",
    description="Summarize existing HOPE output CSVs for the whitelisted case without running Julia.",
)
def hope_output_summary_tool(case_id: str = "md_gtep_clean") -> dict[str, Any]:
    return hope_output_summary(case_id)


@mcp.tool(
    name="hope_run_hope",
    description="Run HOPE synchronously for the whitelisted case and return a compact summary.",
)
def hope_run_hope_tool(case_id: str = "md_gtep_clean") -> dict[str, Any]:
    return hope_run_hope(case_id)


def main() -> None:
    mcp.run("stdio")


if __name__ == "__main__":
    main()
