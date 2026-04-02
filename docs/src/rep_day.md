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

## Recommended `HOPE_rep_day_settings.yml`

```yaml
time_periods:
  1: [1, 1, 3, 31]
  2: [4, 1, 6, 30]
  3: [7, 1, 9, 30]
  4: [10, 1, 12, 31]

clustering_method: kmedoids
feature_mode: joint_daily
include_load: 1
include_af: 1
include_dr: 1
normalize_features: 1
```

Meaning:

- `time_periods`: seasonal windows used for endogenous representative-day construction
- `clustering_method: kmedoids`: Feature 1 selects one actual medoid day per time period
- `feature_mode: joint_daily`: cluster one combined daily feature vector, not each column independently
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

## Legacy Compatibility

For older cases, HOPE still falls back to `time_periods` from `HOPE_model_settings.yml` if `HOPE_rep_day_settings.yml` is missing.

Feature 1 also keeps a legacy comparison mode:

```yaml
feature_mode: legacy_column_centroid
```

That reproduces the old behavior of building one synthetic centroid day per time period, independently by column.
