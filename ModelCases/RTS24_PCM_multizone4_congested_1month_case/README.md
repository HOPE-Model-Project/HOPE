# RTS24_PCM_fullfunc_case

Derived from `RTS24_PCM_case` and upgraded for full PCM nodal feature testing.

Created: 2026-03-09 12:42:14

Key upgrades:
- Mixed generator fleet (Coal / NGCC / NGCT / Hydro / WindOn / SolarPV)
- Expanded storage fleet across multiple buses
- Added DR inputs (`flexddata.csv`, `dr_timeseries_regional.csv`)
- Enabled nodal PTDF network mode (`network_model: 3`)
- Enabled UC, operating reserves, DR, and RPS switch for workflow testing
