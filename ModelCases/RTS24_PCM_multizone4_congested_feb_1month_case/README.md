# RTS24_PCM_multizone4_congested_feb_1month_case

Derived from `RTS24_PCM_multizone4_congested_1month_case` with the same 4-zone tightened network, but using February hourly profiles sliced from `RTS24_PCM_fullfunc_case`.

Created: 2026-03-14 19:39:33

Key characteristics:
- 24-bus nodal PTDF PCM with buses mapped into 4 reporting zones
- Tightened inter-zone transfer limits to preserve congestion visibility
- February-only hourly load, wind, solar, and DR profiles
- Same solver/settings workflow as the original dashboard case
