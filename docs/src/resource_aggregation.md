```@meta
CurrentModule = HOPE
```

# Resource Aggregation

HOPE keeps the main resource-aggregation mode switch in `HOPE_model_settings.yml`:

```yaml
resource_aggregation: 1
```

When `resource_aggregation = 1`, HOPE reads the advanced aggregation controls from:

```text
Settings/HOPE_aggregation_settings.yml
```

This keeps `HOPE_model_settings.yml` high-level while leaving the detailed aggregation behavior in a separate advanced settings file.

## Aggregation Design

The current user-facing resource-aggregation design has three main features:

- `Feature 1: Basic Structured Aggregation`
- `Feature 2: Clustered Thermal Commitment for PCM`
- `Feature 3: Planning-Oriented Generator Clustering`

In addition, HOPE writes aggregation audit outputs so users can see exactly how original resources were merged.

## Common Settings

A typical `HOPE_aggregation_settings.yml` starts from:

```yaml
write_aggregation_audit: 1        # 1 write aggregation audit CSVs into output/; 0 disable

# Existing resources are only grouped when all listed fields match.
grouping_keys:
  - Zone
  - Type
  - Flag_RET
  - Flag_mustrun
  - Flag_VRE
  - Flag_thermal

# Additional grouping keys used only in PCM.
pcm_additional_grouping_keys:
  - Flag_UC

# Feature 2: clustered thermal commitment for aggregated PCM UC resources.
# 1 = aggregated thermal UC resources use unit-count clustered commitment
# 0 = aggregated thermal UC resources keep single-unit-style UC behavior
clustered_thermal_commitment: 1

# Feature 3: planning-oriented clustering inside each keyed aggregation group.
# 1 = split large keyed aggregation groups into planning-oriented sub-clusters
# 0 = use keyed grouping only
planning_clustering: 0

# Numeric columns used when planning_clustering: 1
planning_feature_columns:
  - Cost ($/MWh)
  - FOR
  - CC
  - AF
  - RU
  - RD
  - Pmax (MW)
  - Pmin (MW)

# Approximate number of original resources per planning cluster.
planning_target_cluster_size: 4

# Maximum number of planning clusters created inside one keyed group.
# 0 = no cap
planning_max_clusters_per_group: 4

# 1 = z-score normalize planning features before clustering
# 0 = use raw feature values
normalize_planning_features: 1

# If empty, all technologies are eligible for aggregation.
aggregate_technologies: []

# Technologies kept fully separate even when resource_aggregation: 1
keep_separate_technologies: []
```

## Audit Outputs

When `write_aggregation_audit: 1`, HOPE writes the following CSV files into the case `output/` folder:

- `resource_aggregation_mapping.csv`
- `resource_aggregation_summary.csv`
- `resource_aggregation_af_summary.csv` in GTEP when generator AF aggregation is available

These outputs are meant to answer three questions:

1. which original resources were merged into each aggregated resource?
2. what weights were used in the aggregation?
3. what did the aggregated parameters become after the merge?

## Feature 1: Basic Structured Aggregation

### Focus

Feature 1 makes aggregation safer than the old `Zone x Type` merge by using a structured grouping key and selective technology controls.

### Mechanism

HOPE first builds keyed aggregation groups from:

- `grouping_keys`
- `pcm_additional_grouping_keys` in PCM
- `aggregate_technologies`
- `keep_separate_technologies`

Resources are merged only when:

- they are eligible for aggregation, and
- all required grouping-key fields match

Within each merged group, HOPE currently:

- sums `Pmax` and `Pmin`
- uses capacity-weighted averages for parameters such as cost, `FOR`, `CC`, `AF`, `RU`, and `RD`
- uses `any = 1` logic for flags such as `Flag_thermal`, `Flag_VRE`, `Flag_RET`, and `Flag_mustrun`

### Interpretation

Feature 1 should be interpreted as:

- a safer keyed merge than the old hardcoded `Zone x Type` rule
- still a rule-based aggregation method, not a similarity-based clustering method
- the main default aggregation workflow for both GTEP and PCM

### Recommendation

Use Feature 1 when:

- you want a simpler model than the full resource list
- you still want important operational differences like retirement, must-run, VRE, and thermal flags to stay visible
- you want a clear and auditable aggregation mapping

This is the best starting point for most aggregated cases.

### Example

Suppose a case has four existing generators in the same zone:

| Original Resource | Zone | Type | Flag_RET | Flag_mustrun | Flag_VRE | Flag_thermal |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `G1` | `APS_MD` | `NGCT` | `0` | `0` | `0` | `1` |
| `G2` | `APS_MD` | `NGCT` | `0` | `0` | `0` | `1` |
| `G3` | `APS_MD` | `NGCT` | `1` | `0` | `0` | `1` |
| `G4` | `APS_MD` | `SolarPV` | `0` | `0` | `1` | `0` |

With:

```yaml
grouping_keys:
  - Zone
  - Type
  - Flag_RET
  - Flag_mustrun
  - Flag_VRE
  - Flag_thermal
```

HOPE maps them into:

```math
\{G1, G2\} \rightarrow A_1, \qquad
\{G3\} \rightarrow A_2, \qquad
\{G4\} \rightarrow A_3
```

Meaning:

- `G1` and `G2` are merged because all grouping-key fields match
- `G3` stays separate because `Flag_RET = 1`
- `G4` stays separate because it is a different `Type` and resource family

So Feature 1 is really a controlled keyed merge, not a blanket compression of everything in one zone.

## Feature 2: Clustered Thermal Commitment for PCM

### Focus

Feature 2 fixes the biggest PCM weakness of simple thermal aggregation: an aggregated thermal UC row should not behave like one fictional averaged plant.

### Mechanism

When:

```yaml
clustered_thermal_commitment: 1
```

and PCM has:

- `resource_aggregation: 1`
- `unit_commitment != 0`

HOPE carries extra thermal-cluster metadata into the aggregated `Gendata`:

- `NumUnits`
- `ClusteredUnitPmax (MW)`
- `ClusteredUnitPmin (MW)`

The PCM UC formulation then uses:

- `o[g,h]` as the number of online units in the aggregated cluster
- `su[g,h]` as the number of startup actions
- `sd[g,h]` as the number of shutdown actions

instead of treating the aggregated resource as one single unit.

### Interpretation

Feature 2 should be interpreted as:

- a unit-count clustered commitment approximation for aggregated thermal UC resources
- more realistic than single-unit-style UC on an aggregated row
- especially important for startup costs, minimum-run levels, UC upper bounds, and reserve/ramp response

### Recommendation

Use Feature 2 when:

- you run PCM with unit commitment on aggregated thermal fleets
- startup behavior, minimum output, and reserve deliverability matter
- you want aggregation but do not want to collapse a multi-unit cluster into one fake plant

This should usually stay on for aggregated PCM UC studies.

### Example

Suppose two similar thermal UC units are merged:

| Original Resource | `Pmax (MW)` | `Pmin (MW)` | `Flag_UC` |
| :-- | --: | --: | --: |
| `G1` | `100` | `20` | `1` |
| `G2` | `200` | `40` | `1` |

HOPE aggregates them into one clustered thermal resource with:

```math
\text{NumUnits} = 2, \qquad
\text{ClusteredUnitPmax} = 150, \qquad
\text{ClusteredUnitPmin} = 30
```

Meaning:

- the aggregated row still has total `Pmax = 300`
- but UC decisions now see a 2-unit cluster
- `o[g,h]` can move between `0`, `1`, and `2`
- startup cost and UC headroom scale with the number of units actually online

That is a much better approximation than pretending the merged row is one 300 MW unit.

## Feature 3: Planning-Oriented Generator Clustering

### Focus

Feature 3 moves beyond exact-key grouping and lets HOPE split large keyed groups into planning-oriented sub-clusters.

### Mechanism

When:

```yaml
planning_clustering: 1
```

HOPE still starts with the keyed groups from Feature 1. Then, inside each large eligible group, it:

1. builds a numeric feature matrix from `planning_feature_columns`
2. optionally normalizes the feature columns
3. chooses a number of sub-clusters based on:
   - `planning_target_cluster_size`
   - `planning_max_clusters_per_group`
4. runs `kmeans` on that feature matrix
5. creates one aggregated resource per planning sub-cluster

The audit files record these splits in the `GroupingKey` column using a `PlanningCluster=` tag.

### Interpretation

Feature 3 should be interpreted as:

- a second-stage refinement inside the safer keyed groups
- a behavior-oriented split, not just a label-based split
- most useful when one keyed group still contains a wide spread of costs, outages, capacity credits, or ramping behavior

It does not replace Feature 1. It builds on top of it.

### Recommendation

Use Feature 3 when:

- one keyed group still looks too heterogeneous in the audit outputs
- you want more fidelity without going back to the full resource list
- you want HOPE to preserve meaningful cost / `FOR` / `CC` / ramp differences inside large technology fleets

I recommend turning this on selectively after first inspecting the Feature 1 audit outputs.

### Example

Suppose a keyed `Zone x Type x flags` group contains four thermal resources:

| Original Resource | Cost ($/MWh) | FOR | CC |
| :-- | --: | --: | --: |
| `G1` | `25` | `0.05` | `0.95` |
| `G2` | `27` | `0.05` | `0.95` |
| `G3` | `85` | `0.18` | `0.80` |
| `G4` | `87` | `0.18` | `0.80` |

With:

```yaml
planning_clustering: 1
planning_feature_columns:
  - Cost ($/MWh)
  - FOR
  - CC
planning_target_cluster_size: 2
planning_max_clusters_per_group: 2
normalize_planning_features: 1
```

HOPE maps them into two planning clusters:

```math
\{G1, G2\} \rightarrow A_1, \qquad
\{G3, G4\} \rightarrow A_2
```

Meaning:

- the keyed group was still too heterogeneous
- planning clustering split it into a lower-cost / lower-FOR cluster and a higher-cost / higher-FOR cluster
- the final aggregated fleet keeps more planning structure than a single weighted average would

## Recommended Workflow

My recommended workflow for aggregation is:

1. start with `resource_aggregation: 1` and `planning_clustering: 0`
2. inspect:
   - `resource_aggregation_mapping.csv`
   - `resource_aggregation_summary.csv`
   - `resource_aggregation_af_summary.csv` when relevant
3. if some keyed groups still look too heterogeneous, turn on `planning_clustering: 1`
4. for PCM with UC, keep `clustered_thermal_commitment: 1`

That sequence keeps the model understandable and makes it easier to see when additional clustering is actually helping.
