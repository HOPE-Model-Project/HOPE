# ISONE_PCM_250bus_case

Synthetic but geographically grounded HOPE PCM case for a 250-bus ISO-NE-like nodal system.

## Current scope

- `Bus_id` is the primary operating geography for PCM dispatch and congestion.
- `Zone_id` uses four ISO-NE capacity / RA style zones:
  - `Maine`
  - `NNE`
  - `ROP`
  - `SENE`
- `State` is retained at the bus level for nodal policy accounting.
- The case is currently designed for:
  - nodal PCM analysis
  - dashboard workflow testing
  - later RA-style zonal analysis

## Data basis in the current build

- Network backbone:
  - TAMU EPIGRIDS synthetic New England `Summer90Tight` MATPOWER case
- Bus geography:
  - synthetic electrical partition into four ISO-NE-like zones
  - bus coordinates generated from a force-layout embedding around real New England load-zone anchors
  - bus coordinates are additionally blended toward public city / load-center anchor points inside each ISO-NE load zone
  - bus coordinates then blended toward mapped plant locations to improve New England-shaped geography
  - bus coordinates are now also blended toward public OSM transmission substations and high-voltage corridor sample points when those reference files are present
- Generator fleet:
  - public EIA-860 operable generators for the six New England states
  - filtered to units available during July 2024 using EIA-860 operating and planned-retirement month/year fields
  - mapped to the synthetic 250-bus network by state, load-zone, public plant coordinates, bus strength, corridor proximity, and occupancy penalty
  - TAMU generator buses are not used as a direct capacity-share allocator; they remain only an indirect structural prior through the synthetic network itself
- Transmission:
  - branch reactance and topology still come from the TAMU synthetic backbone
  - a small set of targeted branch-capacity floors is now applied in the builder to relax clearly over-tight synthetic corridors in the `ROP` and `SENE` pockets plus one `NNE` to `ROP` tie
- Generator hourly availability:
  - `gen_availability_timeseries.csv`
  - VRE units use plant-level hourly AF built from public July 2024 ISO-NE hourly wind / solar generation, then adjusted by public EIA-860 plant attributes
  - the hourly renewable chronology is based on public EIA balancing-authority `EBA.ISNE-ALL.NG.SUN.H` and `EBA.ISNE-ALL.NG.WND.H` series
  - wind AF refinement uses plant-level design wind speed and hub height from the EIA-860 wind sheet
  - solar AF refinement uses plant-level tracking, bifacial, DC/AC ratio, azimuth, and tilt information from the EIA-860 solar sheet
  - non-VRE units currently use generator-specific AF values of `1.0`, so thermal derating can still be added later if desired
- Load:
  - public ISO-NE July 2024 nodal load weights by load zone
  - public EIA balancing-authority hourly demand for the eight ISO-NE load zones
  - public EIA balancing-authority hourly generation by fuel for ISO-NE, used to derive the case-level hourly system net imports in `load_timeseries_regional.csv`
  - public ISO-NE July 2024 external-interface metered interchange, used to shape nodal NI geography in `ni_timeseries_nodal.csv`
  - source files:
    - `tools/iso_ne_250bus_case_related/raw_sources/nodalloadweights_4001_202407.csv`
    - ...
    - `tools/iso_ne_250bus_case_related/raw_sources/nodalloadweights_4008_202407.csv`
    - `tools/iso_ne_250bus_case_related/raw_sources/EBA.zip`
    - `tools/iso_ne_250bus_case_related/raw_sources/smd_interchange_2024.xlsx`
  - report window: `07/01/2024` to `07/31/2024` (`744` hours)
  - compressed from public ISO-NE load nodes to the synthetic 250-bus network by load zone
  - public ISO-NE nodal weights remain the primary allocator; TAMU `PD` and local generation access are used only as weak priors to keep the synthetic 250-bus demand placement internally consistent
  - calibrated to public hourly load-zone demand
  - written directly as:
    - `load_timeseries_nodal.csv`
  - then aggregated back to:
    - `load_timeseries_regional.csv`
    for chronology alignment and zonal fallback inputs
  - `load_timeseries_regional.csv` now carries a calibrated system NI blend:
    - official July 2024 ISO-NE control-area interchange chronology
    - plus a retained synthetic energy-balance component so the case remains workable
    - the current live case is approximately a `0.5` blend between the original synthetic NI and the official ISO-NE NI series
  - `ni_timeseries_nodal.csv` is generated separately from:
    - official ISO-NE interface chronology and signs
    - scaled to the case-level hourly `NI`
    - distributed with interface-centered geographic weights plus a small hourly load-share balancing tail
    - optionally constrained by OSM-derived interface search windows when those windows still leave valid synthetic bus candidates
  - flexible NI inputs are now also supported:
    - `ni_timeseries_nodal_target.csv`
    - `ni_timeseries_nodal_cap.csv`
  - in the current ISO-NE workflow:
    - the target file uses official July 2024 ISO-NE control-area interchange magnitude with the same nodal interface-centered geography
    - the cap file uses the higher synthetic case NI magnitude on that same geography
  - finalized nodal-NI preprocessing defaults:
    - `LOCALIZED_NI_SHARE = 0.70`
    - demand weight exponent `0.50`
    - distance decay exponent `0.75`
    - distance floor `5` miles
  - the nodal NI workflow is now generated automatically inside:
    - `tools/iso_ne_250bus_case_related/build_iso_ne_250bus_case.py`
    - via `tools/iso_ne_250bus_case_related/isone_nodal_ni.py`
- Wind / solar regional files:
  - derived from the same public July 2024 ISO-NE wind / solar production chronology used for generator AF
- Storage:
  - public EIA-860 2024 operable battery storage mapped to the synthetic buses
  - filtered to battery units operating during July 2024
  - public EIA-860 2024 pumped-storage generators converted to explicit long-duration storage
  - written as `storagedata.csv`
  - pumped hydro now uses plant-specific assumptions where public information was found:
    - `Northfield Mountain`: `7.5` hours, based on the public FirstLight description
    - `Bear Swamp`: `3028 MWh` energy basis, based on public relicensing materials
    - `Rocky River (CT)`: generic `8-hour` fallback because a plant-specific public duration was not found
  - pumped hydro charging / discharging efficiencies are also plant-specific assumptions documented in the preprocessing notes

## Current solved status

- Solver used for the latest build:
  - `Gurobi`
- Current solve result:
  - default reference settings:
    - `HOPE_model_settings.yml`
    - `carbon_policy: 0`
    - dashboard output pointer:
      - `dashboard_output.txt -> output_nocarbon_check`
  - default reference output folder:
    - `output_nocarbon_check`
  - default reference result:
    - `OPTIMAL`
    - load shedding `0.0 GWh`
    - average modeled NI about `1.586 GW`
    - objective about `2.83345e8`
    - interpretation: this is the finalized nodal demo configuration
  - preserved flexible-NI comparison output folder:
    - `output_flexible_ni_v2`
  - preserved flexible-NI comparison result:
    - `OPTIMAL`
    - average modeled NI about `3.12 GW`
    - load shedding about `154.3 GWh`
    - interpretation: useful as a comparison run showing why the no-carbon reference settings were adopted for the demo case
- Current policy status:
  - default reference case:
    - `carbon_policy: 0`
    - `clean_energy_policy: 1`
  - interpretation:
    - the current RPS inputs are workable in the finalized default settings
    - the current carbon cap inputs were binding enough to force excess NI and load shedding, so the finalized demo case keeps `carbon_policy: 0`

## Current calibration workflow

- The finalized default case is built to run directly with:
  - `HOPE_model_settings.yml`
  - `dashboard_output.txt`
- The flexible-NI comparison case is prepared by:
  - `tools/isone_workflows/prepare_isone_flexible_ni.py`
  - which writes `ni_timeseries_nodal_target.csv` and `ni_timeseries_nodal_cap.csv`
  - and uses `PT_NI_DEV` from `single_parameter.csv` to penalize deviation from the NI target
- The retained internal-supply helper files are:
  - `tools/iso_ne_250bus_case_related/raw_sources/internal_supply_adders_live_case.csv`
- The builder also retains targeted capacity floors on a small set of persistent synthetic corridors:
  - `19-110`, `28-77`, `28-203`, `28-204`, `77-217`, `102-114`, `114-136`, `117-164`, `131-152`, and `217-218`
- No trial calibration units are active in the finalized default `gendata.csv`.

## Important modeling notes

- This is still a proxy case, not a market replication case.
- `busdata.State` is the authoritative state geography for nodal policy accounting.
- `zonedata.State` is only a nominal zone tag in this case and is not the main policy geography.
- The current generator fleet mapping is documented in:
  - [generator_mapping.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\generator_mapping.csv)

## Current caveats

- This is still a public-data hybrid case, not a market replication case.
- The 250-bus network backbone remains synthetic.
- The new OSM layer is used only as a geography and corridor prior; branch reactance and ratings do not come from OSM.
- The builder now also includes a first long-branch topology cleanup pass:
  - it audits synthetic branches by geographic span
  - it rewires a small set of the worst `Maine` / `ROP` / `SENE` shortcuts through intermediate `NNE` bridge buses
  - reference files:
    - `tools/iso_ne_250bus_case_related/references/long_branch_topology_audit.csv`
    - `tools/iso_ne_250bus_case_related/references/topology_rewire_plan.csv`
- VRE hourly AF now uses a public July 2024 ISO-NE production chronology and is then shaped at generator level using public plant attributes from EIA-860.
- Storage now includes both public battery units and explicit pumped-hydro storage (`PHS`).
- The case now has a dedicated nodal NI layer for nodal PCM, built from official ISO-NE interface chronology and calibrated to the synthetic case energy balance.
- The case now also supports a flexible nodal NI layer with target/cap inputs and a deviation penalty.
- The finalized default demo case uses the no-carbon settings, and `dashboard_output.txt` points the dashboard to `output_nocarbon_check`.
- Public-data validation now shows:
  - case average load is close to July 2024 ISO-NE actual load
  - the default no-carbon reference run reaches about `1.59 GW` average NI, aligned with the official July 2024 NI target used in the case
  - the preserved flexible-NI comparison run still sits near `3.12 GW` average NI and sheds load, which is why it is kept only as a comparison case
  - after the LMP sign fix and the network cleanups, the dominant remaining realism gap is fuel mix and broader market realism, not outright infeasibility
- The policy inputs are deliberately conservative first-pass values meant to validate the nodal bus-state accounting path, not to replicate current ISO-NE policy requirements exactly.

## Case inputs

Direct HOPE input files live in:
- [Data_ISONE_PCM_250bus](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\ModelCases\ISONE_PCM_250bus_case\Data_ISONE_PCM_250bus)

Reference and preprocessing files live in:
- [tools/iso_ne_250bus_case_related/references](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references)
- OSM transmission proposal:
  - [OSM_TRANSMISSION_PROPOSAL.md](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\OSM_TRANSMISSION_PROPOSAL.md)
- OSM extraction outputs:
  - [osm_substations.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\osm_substations.csv)
  - [osm_corridor_points.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\osm_corridor_points.csv)
  - [osm_interface_portal_summary.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\osm_interface_portal_summary.csv)
  - [osm_synthetic_seam_scorecard.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\osm_synthetic_seam_scorecard.csv)

## Validation snapshot

- Top load-shedding hours in the current calibrated live build are concentrated around:
  - `188`, `189`, `212`, `233` to `237`, and `354`
- Repeatedly binding lines in the current calibrated live build are concentrated in:
  - `28-203`
  - `102-114`
  - `77-217`
  - `117-164`
  - `131-152`
- The remaining scarcity pattern is concentrated in:
  - `ROP`, especially the CT interior / CT-to-NNE path
  - coastal and Boston-facing `SENE`
  - while `Maine` and `NNE` no longer shed load in the current calibrated live case
- The current map now uses:
  - force-layout electrical embedding
  - public city/load-center anchors
  - load-zone corridor pulls
  - plant-coordinate blending

## Immediate next realism upgrades

1. Calibrate the most persistent seam/internal corridor capacities instead of adding more arbitrary local gas.
2. Prioritize `ROP` and coastal `SENE` around the repeatedly binding lines `102-114`, `117-164`, `131-152`, `28-203`, and `77-217`.
3. After corridor tuning, reduce NI further toward the official July 2024 level and rerun the July scorecard.
4. Only then revisit fuel-group trimming for `Wind` and `Other`, which are still high relative to public July 2024 totals.
5. Use public OSM / OpenInfraMap transmission geometry as a corridor and interface prior, not as a direct electrical-parameter source:
   - `tools/iso_ne_250bus_case_related/references/OSM_TRANSMISSION_PROPOSAL.md`
6. The first implemented OSM seam retune raised the synthetic `NNE-SENE` seam from about `792.6 MW` to about `1341.2 MW` using the OSM scorecard, but the flexible-NI validation solve remained essentially unchanged.
   - Interpretation: current realism limits are still dominated by broader internal energy balance / NI dependence rather than that seam alone.
7. A follow-on cleanup trial capped the unsupported nonadjacent seams `Maine-ROP` and `Maine-SENE` to weak backdoor ties, but that made the flexible-NI solve much worse, raising load shedding to about `431.8 GWh`.
   - That cleanup was not kept in the live case data.
8. A second follow-on trial rerouted that removed unsupported-seam capacity onto the adjacent supported seams `Maine-NNE`, `NNE-ROP`, and `NNE-SENE`, but it still left load shedding at about `430.9 GWh`.
   - Interpretation: the issue is deeper than seam-capacity bookkeeping alone.
