# PJM Holistic Mixed Pair

Generated on 2026-04-05 19:32:14.

- Built mixed holistic baseline pair from the existing canonical zonal pair.
- Selection logic: PCM existing fleet tables; GTEP zonedata/network/policies/chronology; GTEP candidate resource tables.
- GTEP existing gendata.csv replaced with PCM canonical fleet and derived Flag_RPS.
- GTEP existing storagedata.csv replaced with PCM canonical storage fleet.
- GTEP base case inherits zonedata/network/policy/chronology/candidate tables directly from the copied GTEP canonical case.
- GTEP VRE AF values were reset to zonal mean wind/solar availability by zone, and gen_availability_timeseries.csv was reduced to time columns only so GTEP uses those static AF values without a large generator-level AF matrix.
- PCM existing gendata.csv and storagedata.csv kept from PCM canonical fleet tables.
- PCM zonedata/network/policy/chronology refreshed from GTEP canonical case for baseline harmonization.
- PCM does not add a generator-level AF override in the mixed baseline case; it will use the shared zonal wind/solar profiles directly.
