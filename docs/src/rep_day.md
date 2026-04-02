```@meta
CurrentModule = HOPE
```

# Representative Days

HOPE keeps the representative-day mode switch in `HOPE_model_settings.yml`:

```yaml
endogenous_rep_day: 1
external_rep_day: 0
```

When `endogenous_rep_day = 1`, HOPE now reads advanced endogenous representative-day controls from:

```text
Settings/HOPE_rep_day_settings.yml
```

This keeps `HOPE_model_settings.yml` high-level while leaving the chronology-reduction details in a separate advanced settings file.

## Representative-Day Feature Roadmap

The planned user-facing representative-day feature set is:

- `Feature 1: Joint Medoid Representative-Day Selection`
- `Feature 2: Multiple Representative Days per Time Period`
- `Feature 3: Extreme-Day Augmentation`
- `Feature 4: Planning-Focused Feature Engineering`
- `Feature 5: Iterative Representative-Day Refinement`
- `Feature 6: Linked Representative Days for Storage`

## Feature 1: Joint Medoid Representative-Day Selection

Feature 1 improves the old endogenous representative-day process in two ways:

- HOPE builds one joint daily feature vector using aligned load, generator availability, and optional DR profiles.
- HOPE selects one actual observed representative day per time period using a 1-medoid rule, instead of building a synthetic day column by column.

This means load and VRE are now taken from the same real day, which preserves cross-series consistency better than the legacy centroid construction.

## Feature 2: Multiple Representative Days per Time Period

Feature 2 extends Feature 1 by allowing HOPE to select more than one actual representative day inside each seasonal window.

- HOPE still builds one joint daily feature vector using aligned load, generator availability, and optional DR profiles.
- Instead of selecting just one medoid day for each time period, HOPE now selects `k` medoid days.
- Each selected day receives its own weight equal to the number of real days assigned to that medoid cluster.

This reduces the amount of smoothing inside each season and lets HOPE keep multiple characteristic daily patterns, such as a milder day and a more stressed day within the same seasonal window.

## Feature 3: Extreme-Day Augmentation

Feature 3 adds explicitly selected extreme days on top of the clustered medoid days.

- HOPE first selects the medoid-based representative days from Features 1-2.
- HOPE then scans each seasonal window for user-requested extreme days such as peak load, peak net load, minimum wind, minimum solar, and maximum ramp.
- Each added extreme day is treated as an actual observed day with weight `1`.
- To keep the total number of represented days unchanged, HOPE subtracts that weight from the cluster-medoid weight that originally covered the extreme day.

This is especially useful for adequacy and stress-event studies, where pure clustering can miss rare but important days.

## Recommended `HOPE_rep_day_settings.yml`

```yaml
time_periods:
  1: [1, 1, 3, 31]
  2: [4, 1, 6, 30]
  3: [7, 1, 9, 30]
  4: [10, 1, 12, 31]

clustering_method: kmedoids
feature_mode: joint_daily
representative_days_per_period: 1
add_extreme_days: 0
extreme_day_metrics:
  - peak_load
  - peak_net_load
  - min_wind
  - min_solar
  - max_ramp
include_load: 1
include_af: 1
include_dr: 1
normalize_features: 1
```

Meaning:

- `time_periods`: seasonal windows used for endogenous representative-day construction
- `clustering_method: kmedoids`: Feature 1 selects one actual medoid day per time period
- `feature_mode: joint_daily`: cluster one combined daily feature vector, not each column independently
- `representative_days_per_period`: number of representative days to select inside each seasonal window
- `add_extreme_days: 1`: turn on Feature 3 extreme-day augmentation
- `extreme_day_metrics`: choose which extreme-day rules to add; supported values are `peak_load`, `peak_net_load`, `min_wind`, `min_solar`, and `max_ramp`
- `include_load`, `include_af`, `include_dr`: control which data streams enter the feature vector
- `normalize_features: 1`: standardize feature dimensions before distance calculations

## Understanding `time_periods`

Each `time_periods` entry uses the format:

```yaml
period_id: [start_month, start_day, end_month, end_day]
```

So the example above means:

- `1: [1, 1, 3, 31]` means January 1 to March 31
- `2: [4, 1, 6, 30]` means April 1 to June 30
- `3: [7, 1, 9, 30]` means July 1 to September 30
- `4: [10, 1, 12, 31]` means October 1 to December 31

In endogenous representative-day mode, HOPE uses these windows like this:

1. collect all full-chronology days that fall inside each window
2. build one daily feature vector for each real day in that window
3. choose the representative day from only that window
4. assign the selected representative day a weight equal to the number of real days in that window

So `time_periods` does not define optimization hours directly. It defines the seasonal buckets inside which HOPE searches for representative days.

Year-wrapping windows are also supported. For example:

```yaml
time_periods:
  1: [11, 1, 2, 28]
```

means November 1 through February 28.

## Concrete Example

Using the existing case `MD_GTEP_clean_case`, with its seasonal windows:

```yaml
time_periods:
  1: [3, 20, 6, 20]
  2: [6, 21, 9, 21]
  3: [9, 22, 12, 20]
  4: [12, 21, 3, 19]
```

HOPE Feature 1 selected these actual representative days:

| Time Period | Seasonal Window | Selected Representative Day | Weight (Days Represented) |
| :-- | :-- | :-- | :-- |
| `1` | Mar 20 to Jun 20 | May 19 | `93` |
| `2` | Jun 21 to Sep 21 | Aug 31 | `93` |
| `3` | Sep 22 to Dec 20 | Dec 7 | `90` |
| `4` | Dec 21 to Mar 19 | Jan 13 | `89` |

![Representative-day selection in MD_GTEP_clean_case](assets/rep_day_md_case_example.png)

So for this case, HOPE reduces the full year to 4 representative days, but each representative day is an actual observed day from the corresponding seasonal window. For example:

- all days from March 20 to June 20 are compared in the joint feature space
- HOPE selects May 19 as the medoid day for that window
- that selected day gets weight `93`, meaning it represents 93 real days in the model objective and annual accounting

How to read the figure:

- left column: daily total load across each seasonal window, with the selected representative day highlighted
- right column: all 24-hour total load profiles in that season shown in gray, the selected representative day in red, and the seasonal mean profile in dashed blue

This helps users see both:

- where the selected day sits within the season, and
- what the selected 24-hour profile looks like compared with the rest of the season

## Feature 2 Example

If the same `MD_GTEP_clean_case` uses:

```yaml
representative_days_per_period: 2
```

then HOPE selects two actual representative days inside each seasonal window instead of one.

For this case, the selected days and weights are:

| Time Period | Seasonal Window | Representative Day 1 | Weight 1 | Representative Day 2 | Weight 2 |
| :-- | :-- | :-- | :-- | :-- | :-- |
| `1` | Mar 20 to Jun 20 | Apr 22 | `45` | May 7 | `48` |
| `2` | Jun 21 to Sep 21 | Jul 29 | `54` | Aug 15 | `39` |
| `3` | Sep 22 to Dec 20 | Oct 28 | `38` | Nov 26 | `52` |
| `4` | Dec 21 to Mar 19 | Jan 28 | `64` | Mar 18 | `25` |

![Feature 2 representative-day selection in MD_GTEP_clean_case](assets/rep_day_md_case_feature2.png)

So the four seasonal windows now become eight representative periods in the model:

- time period `1` maps to representative periods `1` and `2`
- time period `2` maps to representative periods `3` and `4`
- time period `3` maps to representative periods `5` and `6`
- time period `4` maps to representative periods `7` and `8`

The cluster weights no longer have to be equal. For example, in time period `4`, January 28 represents `64` real days while March 18 represents only `25` real days. This is exactly what Feature 2 is designed to capture: more than one characteristic day shape inside the same season.

How to read the Feature 2 figure:

- left column: daily total load across each seasonal window, with both selected representative days highlighted
- right column: all 24-hour total load profiles in that season shown in gray, with the two selected representative days highlighted separately

For users, the main practical interpretation is:

- `representative_days_per_period: 1` gives one representative day per seasonal window
- `representative_days_per_period: 2` gives two representative days per seasonal window, each with its own weight
- increasing this setting trades more chronology detail for longer solve times

## Feature 3 Example

If the same `MD_GTEP_clean_case` uses:

```yaml
representative_days_per_period: 1
add_extreme_days: 1
extreme_day_metrics:
  - peak_load
  - peak_net_load
  - max_ramp
```

then HOPE keeps one medoid day per seasonal window and adds three explicit extreme days.

For this case, the selected days are:

| Time Period | Seasonal Window | Medoid Day | Medoid Weight | Peak Load Day | Peak Net Load Day | Max Ramp Day |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| `1` | Mar 20 to Jun 20 | May 27 | `90` | Mar 20 | Apr 1 | Apr 11 |
| `2` | Jun 21 to Sep 21 | Sep 17 | `90` | Jun 21 | Sep 10 | Aug 4 |
| `3` | Sep 22 to Dec 20 | Nov 3 | `87` | Sep 22 | Oct 8 | Dec 5 |
| `4` | Dec 21 to Mar 19 | Feb 12 | `86` | Jan 1 | Mar 11 | Jan 19 |

![Feature 3 representative-day selection in MD_GTEP_clean_case](assets/rep_day_md_case_feature3.png)

So the four seasonal windows now become sixteen representative periods in the model:

- one medoid day per time period
- plus one day each for `peak_load`, `peak_net_load`, and `max_ramp`

The medoid weights shrink because those extreme days are carved out explicitly. For example, in time period `1`, the medoid weight is `90` instead of `93`, because three extreme days are represented separately with weight `1` each.

How to read the Feature 3 figure:

- each panel is one seasonal window
- the blue marker is the medoid representative day
- the colored markers are the added extreme days
- each added extreme day gets weight `1`

Two practical notes for users:

- if two extreme metrics point to the same real day, HOPE adds that day only once
- if a metric such as `min_wind` or `min_solar` does not create a new distinct day, it will not increase the number of representative periods

## Legacy Compatibility

For older cases, HOPE still falls back to `time_periods` from `HOPE_model_settings.yml` if `HOPE_rep_day_settings.yml` is missing.

Feature 1 also keeps a legacy comparison mode:

```yaml
feature_mode: legacy_column_centroid
```

That reproduces the old behavior of building one synthetic centroid day per time period, independently by column.
