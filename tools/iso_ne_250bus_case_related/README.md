# ISO-NE 250-Bus HOPE PCM Case Workspace

This folder is the preprocessing workspace for an ISO-NE-like nodal PCM case in HOPE.

Current recommendation:
- Network backbone: TAMU synthetic New England 250-bus case
- HOPE zone layer: ISO-NE capacity / RA zones
- HOPE state layer: real state mapping for policy constraints
- HOPE bus layer: synthetic nodal buses

That means the intended geography is:

`Bus -> Zone (ISO-NE capacity zone) -> State`

This matches HOPE PCM's current implementation:
- `busdata.csv` provides `Bus_id -> Zone_id`
- `zonedata.csv` provides `Zone_id -> State`
- state policies are applied through `carbonpolicies.csv` and `rpspolicies.csv`

Important caveat:
- the chosen ISO-NE capacity zones are not all one-state zones
- the first draft case therefore keeps policy switches off
- direct `zonedata.csv` still uses `State = MULTI` for multi-state zones because HOPE expects one state value per `Zone_id`
- preprocessing/reference files should keep explicit repeated state assignments at the bus and load-zone levels
- a later policy-enabled case will need custom treatment if capacity zones remain the HOPE zone layer

## Why TAMU is the preferred backbone

The TAMU EPIGRIDS New England case is the better starting point for a first ISO-NE-like nodal PCM case because it is:
- already New England-shaped
- already synthetic and publicly usable
- at the right scale for a first dashboard-compatible nodal case

The Zenodo record `4538590` may still be useful as a reference source, but it is not the preferred main topology source for this case build.

## Current HOPE PCM target files

The first usable HOPE PCM case should produce these files:

- `zonedata.csv`
- `busdata.csv`
- `branchdata.csv`
- `linedata.csv`
- `gendata.csv`
- `storagedata.csv`
- `wind_timeseries_regional.csv`
- `solar_timeseries_regional.csv`
- `load_timeseries_regional.csv`
- `carbonpolicies.csv`
- `rpspolicies.csv`
- `single_parameter.csv`
- `HOPE_model_settings.yml`

Optional for later:
- `ptdf_matrix_nodal.csv`
- `flexddata.csv`
- `dr_timeseries_regional.csv`

## Proposed case-build sequence

### Step 1. Backbone network

Input source:
- TAMU synthetic New England 250-bus data

Needed outputs:
- bus list with stable HOPE `Bus_id`
- branch table with `from_bus`, `to_bus`, `X`, `Capacity (MW)`
- bus coordinates for plotting / dashboard map support if available

### Step 2. Geography mapping

Build a bus geography map with at least:
- `Bus_id`
- `Zone_id`
- `State`
- `CapacityZone`
- `LoadZone`

Design choice for HOPE:
- `Zone_id` in HOPE should be set equal to the ISO-NE capacity / RA zone
- `State` stays as the policy layer in `zonedata.csv`

`CapacityZone` is kept as an explicit column anyway for traceability, even if it matches `Zone_id`.

### Step 3. Zone table

Build `zonedata.csv` with:
- `Zone_id`
- `Demand (MW)`
- `State`
- optional `Area`

For this case:
- `Zone_id` = ISO-NE capacity zone
- `Demand (MW)` = zone peak demand from the constructed hourly load series

### Step 4. Bus table

Build `busdata.csv` with:
- `Bus_id`
- `Zone_id`
- `Load_share`
- optional bus demand proxy columns for QA

`Load_share` should sum to 1 within each HOPE zone.

### Step 5. Generator fleet

Primary sources:
- EIA-860
- EIA-923

Generator build rules:
- map plants in CT, ME, MA, NH, RI, VT into synthetic buses
- assign each unit a HOPE zone from its ISO-NE capacity zone
- aggregate only if needed later; start with unit-level or plant-level fidelity where practical

Minimum `gendata.csv` fields:
- `Pmax (MW)`
- `Pmin (MW)`
- `Zone`
- `Bus_id`
- `Type`
- `Flag_thermal`
- `Flag_RET`
- `Flag_VRE`
- `Flag_mustrun`
- `Cost ($/MWh)`
- `EF`
- `CC`
- `AF`
- `FOR`
- `RM_SPIN`
- `RU`
- `RD`
- `Flag_UC`
- `Min_down_time`
- `Min_up_time`
- `Start_up_cost ($/MW)`
- `RM_REG_UP`
- `RM_REG_DN`
- `RM_NSPIN`

### Step 6. Storage

Start simple:
- existing storage only
- map by bus / zone / state

Main likely units:
- batteries if present
- pumped hydro in New England where applicable

### Step 7. Load time series

Primary sources:
- ISO-NE zonal/system demand
- ISO-NE nodal load weights where available

Approach:
- use public ISO-NE load zone or state-level demand as the time-series backbone
- allocate from zone to buses using nodal load weights or a proxy load-distribution rule
- generate HOPE `load_timeseries_regional.csv` at the HOPE zone level
- use `busdata.Load_share` to distribute zonal demand to buses internally in nodal PCM

Important:
- the first version does not need true public nodal load for every bus
- zonal hourly load + bus load shares is enough for HOPE

### Step 8. Renewable profiles

Primary preference:
- ISO-NE VER/planning data

Fallback:
- state/zone renewable profiles from public planning datasets if ISO-NE public files are incomplete for direct HOPE use

First version can stay zonal:
- one wind profile per capacity zone
- one solar profile per capacity zone

### Step 9. Policies

State-level policies should be built through:
- `carbonpolicies.csv`
- `rpspolicies.csv`

For the first draft case:
- keep policy switches off
- keep policy CSVs as templates only

Reason:
- `NNE`, `ROP`, and `SENE` are multi-state under the chosen 2023-24 capacity-zone design
- HOPE currently expects one `State` value per `Zone_id`
- so policy activation should wait until the zone-to-state treatment is explicitly settled

### Step 10. Validation

Target is not exact market replication. The first validation pass should check whether the case produces plausible:
- nodal spreads
- recurring congestion corridors
- congestion timing patterns
- state policy interactions

Public reference data:
- nodal LMP reports
- binding constraint reports

## First deliverable target

The first useful deliverable should be:

- one month only
- nodal PCM
- `network_model = 2` or `3`
- `transmission_loss = 0`
- enough output to run the HOPE dashboard

Recommended first model settings:
- `model_mode: PCM`
- `network_model: 2`
- `transmission_loss: 0`
- `unit_commitment: 0` or `2`
- `summary_table: 1`
- `write_shadow_prices: 0` unless dual recovery is needed under integer UC

## Open design choices still to settle

1. Whether to start with:
- 1 month
- 3 months
- full year

Recommendation: 1 month first.

2. Whether to use:
- `network_model = 2` angle-based
- `network_model = 3` PTDF-based

Recommendation: start with `network_model = 2` for easier debugging and broader feature support.

3. How much fleet fidelity to keep in the first pass:
- plant-level
- unit-level
- partially aggregated by bus / technology

Recommendation: plant-level or coarse unit-level first, then aggregate only if solve time becomes a problem.

## Folder contents

- `README.md`
  - this build plan
- `SOURCE_MANIFEST.md`
  - source list and intended use
- `build_iso_ne_250bus_case.jl`
  - scripted scaffold for the eventual conversion pipeline
- `raw_sources/`
  - manually downloaded upstream files
- `intermediate/`
  - cleaned / mapped intermediate tables
- `outputs/`
  - final mapping tables and HOPE-ready draft outputs

## Current OSM workflow

The ISO-NE builder now supports an optional OSM-backed geography pass.

Workflow:
- run `build_isone_osm_priors.py`
- this downloads OSM transmission substations and high-voltage line geometry for New England
- it writes:
  - `references/osm_substations.csv`
  - `references/osm_corridor_points.csv`
  - `references/osm_interface_portal_candidates.csv`
  - `references/osm_interface_portal_summary.csv`
- then run `build_iso_ne_250bus_case.py`

When those files exist, the builder:
- blends bus coordinates toward OSM transmission substations
- reinforces bus geography along mapped high-voltage corridors
- tightens nodal-NI interface search windows where the OSM portal windows are compatible with the synthetic bus geography
- builds an OSM seam scorecard against the synthetic interzonal network
- applies a first seam-level capacity floor for clearly underbuilt OSM-supported seams
- runs a long-branch topology audit
- rewires a small set of the worst synthetic long shortcuts through intermediate `NNE` bridge buses

Topology-audit outputs:
- `references/long_branch_topology_audit.csv`
- `references/topology_rewire_plan.csv`

Current result:
- the second rewire pass is still only modestly positive
- the flexible-NI validation solve improved from about `154.3 GWh` to about `150.4 GWh` load shedding
- average modeled NI stayed essentially unchanged at about `3.12 GW`
- a follow-on `2.425 GW` zonal NGCC rebalance trial across all four synthetic zones produced no measurable change in NI or load shedding, so it was not adopted
- a no-carbon validation run on the same rebuilt case drops load shedding to `0.0 GWh` and average NI to about `1.586 GW`, which identifies the carbon policy inputs as the main remaining blocker in the carbon-constrained variant

OSM is used only as a geography prior. Electrical branch parameters still come from the synthetic TAMU backbone and HOPE-side calibration.
