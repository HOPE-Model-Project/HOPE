using HOPE

case_path = length(ARGS) >= 1 ? ARGS[1] : error("expected case path")
HOPE.run_hope(case_path)
