# MD Holistic Full Pair

Generated on 2026-04-06 20:28:46.

- Built a full-8760 MD holistic pair from the standalone MD GTEP and MD PCM source cases.
- Baseline philosophy: both cases share the same zonedata, linedata, existing generation/storage fleets, chronology, and policy inputs; PCM keeps only operational fields such as UC and reserve parameters.
- Shared baseline files now come from the MD PCM holistic workbook: zonedata, linedata, existing fleets, load, wind, solar, carbon, RPS, and single-parameter tables.
- The rebuilt pair keeps only MD zones (Flag_MD = 1), removes external APS and DPL corridors, and filters existing and candidate assets to the retained MD topology.
- The load chronology now preserves the original MD zonal profile columns and the original NI time series from the PCM workbook while dropping non-MD zones, instead of reconstructing load from NI-derived shares.
- The new realistic benchmark tuning reduces the Maryland RPS target to 0.6, raises the planning reserve margin to 0.15, and turns off the otherwise non-binding carbon policy flag.
- Candidate build envelopes are now scaled to zonal peak demand: SolarPV 0.6x, WindOn 0.5x, WindOff 0.75x, NGCT_CCS 0.5x, NGCC_CCS 0.75x, and battery power 1.0x with 4.0-hour energy duration.
- GTEP representative-day mode was disabled for this pair so the new small case exercises the full 8760 chronology.
- PCM was converted to CSV inputs so the new case has an explicit, inspectable shared baseline rather than a hidden workbook-only baseline.
- PCM gendata.csv intentionally keeps UC and reserve fields that do not exist in the GTEP baseline; those are the allowed operational-only differences.
- Preserved golden regression GTEP clone: `ModelCases/MD_GTEP_holistic_full8760_case_v20260406g_gtep_run_20260406_210316_674`.
- Preserved golden regression PCM clone: `ModelCases/MD_PCM_holistic_full8760_case_v20260406g_pcm_run_20260406_210316_734`.
- These completed `v20260406g` clones should be treated as read-only reference outputs for future holistic regression and handoff checks.
