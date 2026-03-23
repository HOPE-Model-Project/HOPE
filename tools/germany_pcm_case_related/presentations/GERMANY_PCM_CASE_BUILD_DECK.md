# Germany PCM Case Build Deck

## Slide 1. Germany PCM Case Build
- From raw public data to consistent nodal and zonal HOPE cases.

## Slide 2. Executive Summary
- Goal: create one canonical Germany PCM dataset that supports both nodal and zonal analysis.
- Method: freeze every major mapping once, then derive the zonal case from the nodal case.
- Outcome: solved 2-day nodal demo case plus a consistent 4-zone zonal comparison case.

## Slide 3. Source Stack
- Network backbone: OSM Europe transmission dataset plus PyPSA-Eur workflow reference.
- Fleet: powerplantmatching with BNetzA validation layers.
- Chronology: SMARD national load and generation plus four TSO load helper files.
- Map geometry: Germany state-boundary GeoJSON reconstructed into a dashboard TSO layer.

## Slide 4. Integration Architecture
- Raw sources feed cleaned staging tables, frozen maps, the nodal master case, and the zonal derivative case.
- The zonal case is produced by aggregation from the nodal master case.

## Slide 5. Build Steps
- 1. Network backbone
- 2. Bus-zone mapping
- 3. Generator mapping
- 4. Chronology
- 5. Case assembly
- 6. Dashboard geometry

## Slide 6. Case Snapshot
- Nodal master case: 783 buses, 1174 lines, 4135 generators.
- Zonal derivative case: 4 zones, 5 interfaces, 46 generators.

## Slide 7. Assumptions And Caveats
- The 4-zone Germany setup is a research zoning, not the real DE-LU bidding zone.
- The dashboard TSO overlay is reconstructed, not an official public shapefile.
- The nodal case is the canonical truth source and the zonal case is derived from it.

## Slide 8. Debugging Journey
- Initial nodal failures were caused by topology and reactance-scaling issues.
- Fixes: transformer connectivity, largest connected component, and HOPE-scale reactance normalization.
- Result: stable 1-day and 2-day full-nodal debug runs.

## Slide 9. Solved Demo Outcome
- 2-day January nodal demo total cost: $10.00M.
- Load shedding: 0.0.
- The 2-day nodal case is now the dashboard default.

## Slide 10. Next Steps
- Deepen validation and benchmarking.
- Extend nodal solve horizon.
- Upgrade geometry if official GIS becomes available.
- Strengthen nodal-vs-zonal storytelling in the dashboard.

## Slide 11. Key Files In The Repo
- E:/MIT Dropbox/Shen Wang/MIT/RA/HOPE_project/tools/germany_pcm_case_related
- E:/MIT Dropbox/Shen Wang/MIT/RA/HOPE_project/tools/hope_dashboard/data/germany_tso_zones.geojson
- E:/MIT Dropbox/Shen Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_nodal_case
- E:/MIT Dropbox/Shen Wang/MIT/RA/HOPE_project/ModelCases/GERMANY_PCM_zonal4_case

## Slide 12. Raw Input Snapshot
- Raw network files: 12,936 buses, 16,050 line rows, 1,949 transformers, and 35 links.
- Raw fleet file: 165,064 Germany plant rows from powerplantmatching.
- Raw SMARD inputs: 8,766 rows in the national generation file and 8,766 rows in each TSO load helper file before normalization.
- Clean staging outputs: 791 buses, 1,019 lines, 155 transformers, 141,420 cleaned generator rows, and 8,760 canonical chronology rows.

## Slide 13. Processing To The Current Case
- Ingest raw network, fleet, chronology, and reference geometry files.
- Normalize schemas and filter to Germany-relevant records.
- Repair topology and electrical scaling for HOPE compatibility.
- Freeze bus-zone and generator-bus mapping tables.
- Normalize chronology and zonal helper shares.
- Build the nodal master case first and derive the zonal case from it.

## Slide 14. Open-Source Case Comparison
- HOPE Germany case: focused on matched nodal-vs-zonal PCM comparison.
- PyPSA-Eur: strong Europe-wide workflow and clustering reference.
- eTraGo/open_eGo: strong Germany-specific nodal and planning context.
- POMATO DE example: strong market-coupling and redispatch framing.

## Slide 15. Comparison: Pros And Trade-Offs
- HOPE Germany case: best for direct comparison under consistent assumptions, but still being scaled to longer nodal horizons.
- PyPSA-Eur: best open workflow backbone, but not a drop-in HOPE PCM case.
- eTraGo/open_eGo: rich German system detail, but heavier and broader than the focused HOPE comparison build.
- POMATO DE example: very strong for zonal market design, but a different modeling stack and study objective.

## Extra Slide. Raw Input Snapshot
- Raw network files: 12,936 buses, 16,050 line rows, 1,949 transformers, 35 links.
- Raw fleet file: 165,064 Germany plant rows from powerplantmatching.
- Raw SMARD inputs: 8,766 rows in the national generation file and 8,766 rows in each TSO load helper file before normalization.
- Clean staging outputs: 791 buses, 1,019 lines, 155 transformers, 141,420 cleaned generator rows, and 8,760 canonical chronology rows.

## Extra Slide. Processing To The Current Case
- Ingest raw network, fleet, chronology, and reference geometry files.
- Normalize schemas and filter to Germany-relevant records.
- Repair topology and electrical scaling for HOPE compatibility.
- Freeze bus-zone and generator-bus mapping tables.
- Normalize chronology and zonal helper shares.
- Build the nodal master case first and derive the zonal case from it.

## Extra Slide. Open-Source Case Comparison
- HOPE Germany case: focused on matched nodal-vs-zonal PCM comparison.
- PyPSA-Eur: strong Europe-wide workflow and clustering reference.
- eTraGo/open_eGo: strong Germany-specific nodal and planning context.
- POMATO DE example: strong market-coupling and redispatch framing.

## Extra Slide. Comparison: Pros And Trade-Offs
- HOPE Germany case: best for direct comparison under consistent assumptions, but still being scaled to longer nodal horizons.
- PyPSA-Eur: best open workflow backbone, but not a drop-in HOPE PCM case.
- eTraGo/open_eGo: rich German system detail, but heavier and broader than the focused HOPE comparison build.
- POMATO DE example: very strong for zonal market design, but a different modeling stack and study objective.
