# ISO-NE 250-Bus Case Notes

This folder stores reference and preprocessing files, not direct HOPE inputs.

The direct HOPE PCM input files for the case live in:
- [Data_ISONE_PCM_250bus](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\ModelCases\ISONE_PCM_250bus_case\Data_ISONE_PCM_250bus)

## Current source choices

- Network backbone:
  - TAMU EPIGRIDS synthetic New England `Summer90Tight`
- Capacity-zone basis:
  - four ISO-NE-style capacity / RA zones used as HOPE `Zone_id`
- Load profile basis:
  - public ISO-NE July 2024 nodal load weights by load zone
  - public EIA balancing-authority hourly demand for the eight ISO-NE load zones
  - public EIA balancing-authority hourly generation by fuel for ISO-NE, used to derive hourly system net imports
  - raw files:
    - `tools/iso_ne_250bus_case_related/raw_sources/nodalloadweights_4001_202407.csv`
    - ...
    - `tools/iso_ne_250bus_case_related/raw_sources/nodalloadweights_4008_202407.csv`
    - `tools/iso_ne_250bus_case_related/raw_sources/EBA.zip`
  - compressed directly to the synthetic 250 buses as hourly nodal load multipliers
  - calibrated to public hourly load-zone demand
  - written as `load_timeseries_nodal.csv`
  - then aggregated to `load_timeseries_regional.csv` for HOPE chronology alignment
  - `load_timeseries_regional.csv` now also includes hourly `NI` derived from public demand minus public generation
- Bus geography basis:
  - load-zone anchor coordinates plus graph-based force-layout embedding
  - public city / load-center anchors inside each ISO-NE load zone
  - public load-zone corridor polylines to strengthen the apparent transmission backbone on the map
  - then blended toward mapped public plant coordinates
- Generator fleet basis:
  - EIA-860 operable public generators for CT/ME/MA/NH/RI/VT
  - mapped to synthetic buses by state, load-zone, plant coordinates, bus strength, corridor proximity, and occupancy penalty
- VRE basis:
  - plant-level AF built from public July 2024 ISO-NE hourly wind / solar generation
  - renewable chronology comes from public EIA balancing-authority series for ISO-NE system wind and solar generation
  - wind plants are adjusted using public EIA-860 wind-sheet attributes such as design wind speed and hub height
  - solar plants are adjusted using public EIA-860 solar-sheet attributes such as tracking mode, bifacial flag, DC/AC ratio, azimuth, and tilt
- Storage basis:
  - EIA-860 2024 operable battery storage mapped to synthetic buses
  - EIA-860 2024 pumped-storage generators converted to explicit long-duration storage
  - written to `storagedata.csv`
  - `Northfield Mountain` uses a `7.5-hour` duration assumption from public FirstLight information
  - `Bear Swamp` uses a public `3028 MWh` energy basis from relicensing materials
  - `Rocky River (CT)` keeps a generic `8-hour` fallback because a plant-specific public duration was not found
  - charging / discharging efficiencies are plant-specific assumptions documented in the builder

## Current geography structure

- `Bus_id`:
  - nodal operating geography
- `Zone_id`:
  - `Maine`, `NNE`, `ROP`, `SENE`
- `LoadZone`:
  - repeated ISO-NE-style load-zone labels used only for preprocessing and map realism
- `State`:
  - explicit bus-level state mapping, with no `MULTI` placeholder at the bus level

For this nodal PCM case, bus state is the important policy geography.

## Coordinate realism note

The TAMU raw case does not include official ISO-NE GIS bus coordinates.

Current `Latitude` / `Longitude` therefore represent an approximate New England embedding:
- buses are electrically partitioned into the four target zones
- then split into proxy ISO-NE load-zone clusters
- then placed by a constrained force layout around real-world load-zone anchors
- then blended toward public city / load-center anchors inside each load zone
- then optionally blended toward public OSM transmission substations and high-voltage corridor samples
- then blended again toward mapped public plant coordinates

This is intended to make the dashboard topology look regionally plausible. It is not an official ISO-NE GIS map.

## Fleet realism note

The current fleet is an EIA-backed public plant mapping, but it is still not a full market replication model.

Useful reference file:
- [generator_mapping.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\generator_mapping.csv)
- [OSM_TRANSMISSION_PROPOSAL.md](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\OSM_TRANSMISSION_PROPOSAL.md)
- [osm_substations.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\osm_substations.csv)
- [osm_corridor_points.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\osm_corridor_points.csv)
- [osm_interface_portal_summary.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\osm_interface_portal_summary.csv)
- [osm_synthetic_seam_scorecard.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\osm_synthetic_seam_scorecard.csv)
- [long_branch_topology_audit.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\long_branch_topology_audit.csv)
- [topology_rewire_plan.csv](e:\MIT Dropbox\Shen Wang\MIT\RA\HOPE_project\tools\iso_ne_250bus_case_related\references\topology_rewire_plan.csv)

It documents:
- bus assignment
- zone / state / load-zone location
- original public plant code, name, and technology
- assigned synthetic bus and mapped HOPE technology

## VRE and AF note

This case now writes:
- `wind_timeseries_regional.csv`
- `solar_timeseries_regional.csv`
- `gen_availability_timeseries.csv`

PCM still uses zonal wind/solar time series in general, but this case now also provides plant-level AF so VRE units can use generator-specific availability informed by public EIA-860 plant attributes and public ISO-NE hourly renewable production chronology.

Thermal generators currently keep hourly AF at `1.0`, so the case remains compatible with future thermal derating studies without forcing them yet.

## Current adequacy note

The rebuilt case now solves with zero load shedding.

The key realism improvements that enabled that were:
- direct `load_timeseries_nodal.csv` from public July 2024 ISO-NE nodal load weights
- public hourly ISO-NE load-zone demand calibration
- public hourly `NI` derived from EIA balancing-authority demand and generation data
- public battery storage from EIA-860
- explicit public pumped-hydro storage from EIA-860 with a documented long-duration assumption

This is still a synthetic-topology case, but it is now materially more useful for nodal dispatch, congestion, and dashboard analysis.

## Policy note

State policy inputs are now active in the current build:

- `carbon_policy = 1`
- `clean_energy_policy = 1`

Current calibration is intentionally conservative:
- carbon allowances are set slightly above the latest unconstrained dispatch emissions by state
- RPS targets are moderate first-pass targets with all-to-all New England REC trading enabled

Purpose:
- validate the nodal bus-state accounting path in PCM
- keep the case policy-ready without forcing an aggressive policy stress test yet

## Validation note

Latest solved build:
- `OPTIMAL`
- `0.0` load shedding
- objective about `2.13694e8`

Observed congestion behavior in the latest run:
- strongest repeated congestion appears on internal `ROP` corridors
- secondary repeated congestion appears on selected `SENE` corridors
- a clearer coastal / southern `NNE` pocket is now repeatedly stressed
- the `NNE` to `ROP` interface is now more visible in repeated congestion
- Maine is still present but no longer carries the main northern stress signal
- top spread hours are concentrated in a smaller subset of July hours rather than being uniformly persistent
- strongest average congestion exposure is concentrated on `ROP` buses `136`, `104`, `102`, `105`, `114`, then on `SENE` buses `164`, `28`, `89`, `77`, and `88`

## Next realism upgrades

1. add more public substation / corridor anchor points for the strongest internal congestion paths
2. keep refining the largest plant-to-bus placements where corridor realism still looks weak
3. calibrate policy inputs only after the physical case structure is stable enough
4. evaluate OSM / OpenInfraMap as a geography prior for bus anchoring, seam checks, and NI portal refinement:
   - `tools/iso_ne_250bus_case_related/references/OSM_TRANSMISSION_PROPOSAL.md`
5. current implemented OSM extraction workflow:
   - download public transmission substations and high-voltage lines with `tools/iso_ne_250bus_case_related/build_isone_osm_priors.py`
   - write `osm_substations.csv`, `osm_corridor_points.csv`, and `osm_interface_portal_summary.csv`
   - let the case builder consume those files as optional priors for bus geography and NI interface search windows
6. current implemented OSM seam workflow:
   - compare `osm_corridor_points.csv` against the live `branchdata.csv`
   - write `osm_synthetic_seam_scorecard.csv`
   - apply a first seam-level capacity floor in the builder
   - current result: `NNE-SENE` is lifted materially, but the flexible-NI solve changes negligibly, so the main realism gap is still broader than that seam alone
7. current implemented long-branch topology workflow:
   - audit synthetic branches by geographic span and cross-zone shortcut pattern
   - write `long_branch_topology_audit.csv`
   - replace a small set of the worst direct `Maine` / `ROP` / `SENE` shortcuts with two-leg paths through `NNE` bridge buses
   - write `topology_rewire_plan.csv`
   - current result: after a second small rewire batch, flexible-NI load shedding improves from about `154.3 GWh` to about `150.4 GWh` with essentially unchanged NI, so the rewires are directionally helpful but still only a limited cleanup
8. failed seam-cleanup trial:
   - capping the unsupported `Maine-ROP` and `Maine-SENE` seams to weak backdoor ties made the flexible-NI case much worse
   - the live case therefore keeps those seams for now, despite their poor geographic realism
9. failed seam-reroute trial:
   - rerouting the removed unsupported-seam capacity onto `Maine-NNE`, `NNE-ROP`, and `NNE-SENE` also left the case much worse
   - this indicates the current synthetic topology is relying on those long seams in a way that cannot be repaired by simple seam-total redistribution
10. failed zonal internal-supply rebalance trial:
   - a derived `2.425 GW` NGCC rebalance across `Maine`, `NNE`, `ROP`, and `SENE` was built from the remaining NI gap plus load-shedding profile
   - the resulting flexible-NI validation solve was numerically unchanged from the topology-rewire baseline
   - this indicates the remaining realism gap is not fixed by broad gas-capacity adders alone
