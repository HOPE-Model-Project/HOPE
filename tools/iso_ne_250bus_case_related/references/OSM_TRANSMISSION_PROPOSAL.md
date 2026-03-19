# OSM / OpenInfraMap Proposal For ISO-NE 250-Bus Transmission Refinement

## Purpose

This proposal recommends a limited, practical use of OpenStreetMap-based power data to improve the geographic and corridor realism of the synthetic ISO-NE 250-bus case without pretending that OSM is a full electrical-model source.

The goal is not to rebuild the HOPE transmission network from OSM. The goal is to use public map data to improve:

- substation anchoring
- corridor existence and routing
- seam and interface geography
- NI portal placement
- branch and bus realism checks

## Current problem

The current case is already workable for nodal PCM, but the transmission backbone still inherits a synthetic topology from the TAMU `Summer90Tight` test system. That is acceptable for a test case, but several realism gaps remain:

- bus coordinates are approximate rather than substation-based
- seam and corridor strength is still being tuned partly by synthetic judgment
- NI portal buses are only proxy border injections
- branch-level geometry is not tied to public transmission routes

This means the next network improvements should target geographic plausibility and corridor structure, not full physical replication.

## Recommendation

Use OSM and OpenInfraMap as a transmission geography layer, not as the electrical parameter source.

Recommended use:

- identify real transmission substations and switchyards
- identify major transmission corridors and border crossings
- identify approximate corridor voltage classes and circuit multiplicity where tagged
- improve zone-to-zone seam structure
- improve external interface bus placement

Do not use OSM alone for:

- branch reactance
- thermal ratings
- transformer electrical parameters
- breaker-level topology
- full market-network replication

## Why this is the right scope

OpenStreetMap power data is strongest on geometry and network landmarks. It is much weaker on electrical attributes that HOPE needs for DC power flow quality. This implies a clean division of labor:

- TAMU / existing HOPE branch data continue to provide the electrical backbone
- OSM provides geography and corridor-validation priors

That matches the project goal of building a strong test case rather than a one-for-one ISO-NE market replica.

## Proposed data sources

Primary public map sources:

- Open Infrastructure Map overview: `https://openinframap.org/about`
- OSM power line tagging: `https://wiki.openstreetmap.org/wiki/Power_lines`
- OSM power-line guidelines: `https://wiki.openstreetmap.org/wiki/Power_networks/Guidelines/Power_lines`
- OSM transmission substations: `https://wiki.openstreetmap.org/wiki/Tag%3Apower%3Dsubstation`
- OSM transmission substation subtype: `https://wiki.openstreetmap.org/wiki/Tag%3Asubstation%3Dtransmission`
- OSM route relation for power corridors: `https://wiki.openstreetmap.org/wiki/Tag%3Aroute%3Dpower`
- OSM power QA guidance: `https://wiki.openstreetmap.org/wiki/Power_networks/Quality_Assurance`

Expected useful tags:

- `power=substation`
- `substation=transmission`
- `substation=generation`
- `substation=transition`
- `power=line`
- `power=cable`
- `voltage=*`
- `circuits=*`
- `operator=*`
- `name=*`
- `ref=*`

## Proposed workflow

### Phase 1: Build a transmission geography layer

Create a preprocessing step that extracts:

- transmission substations and switchyards in the six New England states
- major lines and cables
- border substations near NY, Quebec, and New Brunswick interfaces

Output proposed reference files:

- `osm_substations.csv`
- `osm_lines.geojson`
- `osm_border_interfaces.csv`

These are reference files only, not direct HOPE inputs.

### Phase 2: Bus anchoring and corridor scoring

Use the OSM layer to score each synthetic bus on:

- nearest real transmission substation distance
- zone-consistent corridor density
- proximity to major 345-kV and 230-kV corridors where tagged
- proximity to border interface substations

Use those scores to refine:

- bus latitude / longitude
- corridor pull forces in the map embedding
- NI interface bus clusters

This should replace some of the current hand-tuned corridor intuition with a public geographic prior.

### Phase 3: Seam validation

Build a seam scorecard for the synthetic network versus the OSM geography:

- `Maine <-> NNE`
- `NNE <-> ROP`
- `ROP <-> SENE`
- west-facing NY interfaces
- north-facing Quebec interfaces
- east-facing New Brunswick interface

For each seam, compare:

- number of synthetic tie branches
- sum of branch capacities in the synthetic case
- number of mapped real corridors
- presence of high-voltage corridor clusters

The purpose is not to force exact equality. The purpose is to identify obvious seam underbuild or overbuild.

### Phase 4: NI portal refinement

Use OSM border substations and transition yards to tighten the current NI bus mapping. This is probably the highest-value near-term use.

Deliverables:

- a cleaner set of interface portal bus clusters
- better split between NY North, Cross Sound, Northport-Norwalk, Phase II, Highgate, and New Brunswick proxies
- less arbitrary localization of nodal NI

### Phase 5: Optional branch-geometry refinement

For the most important repeatedly binding corridors, use OSM line geometry to check whether the current synthetic routing is directionally plausible.

This can justify:

- retaining a corridor-capacity floor
- moving a line to a nearby bus pair
- increasing or decreasing corridor emphasis in the force-layout embedding

This phase should be selective. It should only target a small number of persistent high-impact corridors.

## Proposed implementation in this repo

### New scripts

Add a small OSM preprocessing chain under `tools/iso_ne_250bus_case_related/`, for example:

- `extract_isone_osm_power.py`
- `build_isone_osm_corridor_priors.py`
- `score_isone_synthetic_vs_osm.py`

### New reference outputs

Write derived reference files under `tools/iso_ne_250bus_case_related/references/`, for example:

- `osm_substations.csv`
- `osm_lines.geojson`
- `osm_corridor_priors.csv`
- `osm_interface_portals.csv`
- `osm_synthetic_seam_scorecard.csv`

### Builder integration

Integrate only the stable outputs into the existing builder:

- bus coordinate anchoring priors
- NI portal cluster refinement
- optional corridor-strength priors

Do not directly overwrite branch reactance or branch ratings from OSM.

## Acceptance criteria

This work should be considered successful if it produces:

- more realistic bus geography around major substations and interfaces
- more defensible NI portal placement
- cleaner justification for seam and corridor calibration
- fewer purely hand-tuned transmission adjustments
- no degradation in model solvability

It is not necessary for this work to produce:

- official ISO-NE branch electrical parameters
- exact line-by-line replication
- market-grade network validation

## Risks and limits

- OSM coverage is uneven; some corridors are better mapped than others.
- Voltage and circuit tags are incomplete in some areas.
- OSM geometry may reflect visible infrastructure but not operating topology.
- Some substations are mapped without enough detail to distinguish transmission from distribution.
- OpenInfraMap is a visualization layer over OSM and not an authoritative operator dataset.

These risks are acceptable because the intended use is as a geography prior, not a final electrical truth source.

## Recommended next step

Start with a narrow pilot:

1. extract OSM substations and lines for the six New England states plus border regions
2. build an interface and seam reference layer
3. use that only to refine NI portal clusters and bus coordinate anchoring
4. rerun the ISO-NE scorecard and congestion review before touching branch ratings again

This is the highest-value, lowest-risk way to use OSM in the current case.
