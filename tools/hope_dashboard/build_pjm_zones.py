"""
Download PJM utility service territories from HIFLD and build a zone-level GeoJSON
for use in the HOPE dashboard.

Zone mapping: HIFLD (NAME, STATE) -> model zone ID (e.g., AEP_OH, CE_IL, ...)
"""
import json
import urllib.request
import urllib.parse
from pathlib import Path

# ---------------------------------------------------------------------------
# Utility-name -> zone mapping for PJM_MD100 model zones
# Keys are (substring_in_NAME, STATE) matched case-insensitively.
# First match wins. Based on HIFLD Electric Retail Service Territories.
#
# HIFLD quirks discovered:
#   - Many utilities are stored under their HQ state, not their served state.
#   - Kingsport Power (AEP_TN), Kentucky Power (AEP_KY), Wheeling Power (AEP_WV),
#     Jersey Central (JC_NJ), Metropolitan Edison (ME_PA), and
#     Pennsylvania Electric (PN_PA) all appear under STATE='OH' in HIFLD.
#   - Monongahela Power (AP_WV) and Potomac Edison appear under STATE='PA'.
#   - Rockland Electric (RECO_NJ) appears under STATE='NY'.
#   - Indiana Michigan Power (AEP_IN/MI) appears under STATE='IN' only.
#   - Delmarva Power appears only under STATE='DE' (DPL_MD, DPL_VA unavailable).
#   - Virginia Electric (DOM_NC) does not appear in NC records.
# ---------------------------------------------------------------------------
_NAME_STATE_TO_ZONE: dict[tuple[str, str], str] = {
    # AE_NJ -- Atlantic City Electric (Exelon)
    ("ATLANTIC CITY ELECTRIC",    "NJ"): "AE_NJ",
    # AEP sub-zones
    ("OHIO POWER CO",             "OH"): "AEP_OH",
    ("COLUMBUS SOUTHERN",         "OH"): "AEP_OH",
    ("APPALACHIAN POWER CO",      "OH"): "AEP_OH",   # small AEP enclave in OH
    ("INDIANA MICHIGAN POWER",    "IN"): "AEP_IN",
    # AEP_MI: Indiana Michigan Power only appears under IN in HIFLD -- no polygon
    # AEP_KY: "KENTUCKY POWER CO" appears only under OH in HIFLD (not KY)
    ("KENTUCKY POWER CO",         "OH"): "AEP_KY",
    # AEP_TN: "KINGSPORT POWER CO" appears under OH in HIFLD (not TN)
    ("KINGSPORT POWER CO",        "OH"): "AEP_TN",
    # AEP_VA: Appalachian Power does not appear in VA records -- no polygon
    # AEP_WV: "WHEELING POWER CO" appears under OH in HIFLD (not WV)
    ("WHEELING POWER CO",         "OH"): "AEP_WV",
    # AP sub-zones -- Allegheny Power (FirstEnergy)
    ("WEST PENN POWER",           "PA"): "AP_PA",
    ("THE POTOMAC EDISON",        "PA"): "AP_PA",    # Potomac Edison PA portion
    ("MONONGAHELA POWER",         "WV"): "AP_WV",
    ("MONONGAHELA POWER",         "PA"): "AP_WV",    # shows in PA in HIFLD
    ("THE POTOMAC EDISON",        "WV"): "AP_WV",
    ("THE POTOMAC EDISON",        "MD"): "AP_MD",
    ("THE POTOMAC EDISON",        "VA"): "AP_VA",
    # ATSI sub-zones -- FirstEnergy ATSI areas
    ("OHIO EDISON CO",            "OH"): "ATSI_OH",
    ("CLEVELAND ELECTRIC ILLUM",  "OH"): "ATSI_OH",
    ("TOLEDO EDISON",             "OH"): "ATSI_OH",
    ("PENNSYLVANIA POWER",        "OH"): "ATSI_PA",  # Penn Power (HQ in OH)
    ("PENNSYLVANIA POWER",        "PA"): "ATSI_PA",
    # BC_MD -- BGE
    ("BALTIMORE GAS & ELECTRIC",  "MD"): "BC_MD",
    # CE_IL -- ComEd
    ("COMMONWEALTH EDISON",       "IL"): "CE_IL",
    # DAY_OH -- Dayton Power & Light
    ("DAYTON POWER & LIGHT",      "OH"): "DAY_OH",
    # DEOK -- Duke Energy Ohio / Kentucky
    ("DUKE ENERGY OHIO",          "OH"): "DEOK_OH",
    ("DUKE ENERGY KENTUCKY",      "KY"): "DEOK_KY",
    ("UNION LIGHT HEAT & POWER",  "KY"): "DEOK_KY",
    # DOM sub-zones -- Dominion
    ("VIRGINIA ELECTRIC & POWER", "VA"): "DOM_VA",
    ("DOMINION VIRGINIA POWER",   "VA"): "DOM_VA",
    # DOM_NC: Virginia Electric does not appear in NC records -- no polygon
    # DPL sub-zones -- Delmarva Power (only DE available in HIFLD)
    ("DELMARVA POWER",            "DE"): "DPL_DE",
    # DUQ_PA -- Duquesne Light
    ("DUQUESNE LIGHT",            "PA"): "DUQ_PA",
    # EKPC_KY -- East KY Power Coop (must appear BEFORE generic KENTUCKY POWER)
    ("EAST KENTUCKY POWER",       "KY"): "EKPC_KY",
    # JC_NJ -- Jersey Central P&L (appears under OH in HIFLD)
    ("JERSEY CENTRAL POWER",      "OH"): "JC_NJ",
    ("JERSEY CENTRAL POWER",      "NJ"): "JC_NJ",
    # ME_PA -- Metropolitan Edison (appears under OH in HIFLD)
    ("METROPOLITAN EDISON",       "PA"): "ME_PA",
    ("METROPOLITAN EDISON",       "OH"): "ME_PA",
    # OVEC_OH -- Ohio Valley Electric
    ("OHIO VALLEY ELECTRIC",      "OH"): "OVEC_OH",
    # PE_PA -- PECO Energy (Exelon)
    ("PECO ENERGY",               "PA"): "PE_PA",
    # PEP_MD -- PEPCO
    ("POTOMAC ELECTRIC POWER",    "MD"): "PEP_MD",
    ("POTOMAC ELECTRIC POWER",    "DC"): "PEP_MD",
    # PL_PA -- PPL Electric
    ("PPL ELECTRIC UTILITIES",    "PA"): "PL_PA",
    # PN_PA -- Pennsylvania Electric (appears under OH in HIFLD)
    ("PENNSYLVANIA ELECTRIC",     "PA"): "PN_PA",
    ("PENNSYLVANIA ELECTRIC",     "OH"): "PN_PA",
    # PS_NJ -- PSE&G
    ("PUBLIC SERVICE ELEC & GAS", "NJ"): "PS_NJ",
    # RECO_NJ -- Rockland Electric (appears under NY in HIFLD)
    ("ROCKLAND ELECTRIC",         "NY"): "RECO_NJ",
    ("ROCKLAND ELECTRIC",         "NJ"): "RECO_NJ",
}


def _lookup_zone(name: str, state: str) -> str | None:
    name_up = (name or "").upper()
    state_up = (state or "").upper()
    for (frag, st), zone in _NAME_STATE_TO_ZONE.items():
        if st == state_up and frag in name_up:
            return zone
    return None


def _query_state(base: str, state: str) -> list[dict]:
    """Download all HIFLD service territory features for one state."""
    page_size = 500
    offset = 0
    features: list[dict] = []
    where = f"STATE='{state}'"
    while True:
        params = {
            "where": where,
            "outFields": "NAME,STATE",
            "outSR": "4326",
            "geometryPrecision": "4",   # ~11 m -- greatly reduces payload size
            "resultOffset": offset,
            "resultRecordCount": page_size,
            "f": "geojson",
        }
        url = base + "/query?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 HOPE-Dashboard/1.0"})
        with urllib.request.urlopen(req, timeout=90) as r:
            page = json.loads(r.read())
        page_features = page.get("features", [])
        features.extend(page_features)
        if len(page_features) < page_size:
            break
        offset += page_size
    return features


def build_pjm_geojson(out_path: Path) -> None:
    base = "https://services3.arcgis.com/OYP7N6mAJJCyH6hd/arcgis/rest/services/Electric_Retail_Service_Territories_HIFLD/FeatureServer/0"

    # NY included because Rockland Electric (RECO_NJ) appears there in HIFLD.
    pjm_states = ("DC", "DE", "IL", "IN", "KY", "MD", "MI", "NC", "NJ", "NY", "OH", "PA", "TN", "VA", "WV")

    features_out: list[dict] = []
    unmapped: list[tuple[str, str]] = []

    print("Downloading HIFLD Electric Retail Service Territories (PJM states)...")
    for state in pjm_states:
        try:
            raw = _query_state(base, state)
            mapped = 0
            for feat in raw:
                props = feat.get("properties", {})
                name  = props.get("NAME") or ""
                zone  = _lookup_zone(name, state)
                if zone is None:
                    unmapped.append((name, state))
                    continue
                feat["properties"] = {"zone_id": zone, "utility": name, "state": state}
                features_out.append(feat)
                mapped += 1
            print(f"  {state}: {len(raw)} utilities, {mapped} mapped")
        except Exception as exc:
            print(f"  {state}: ERROR -- {exc}")

    print(f"\nMapped {len(features_out)} polygons to zones.")
    if unmapped:
        print(f"Skipped {len(set(unmapped))} distinct unmapped utilities.")

    from collections import Counter
    zone_counts = Counter(f["properties"]["zone_id"] for f in features_out)
    print("\nPolygons per zone:")
    for zone, cnt in sorted(zone_counts.items()):
        print(f"  {zone}: {cnt}")

    geojson = {"type": "FeatureCollection", "features": features_out}
    out_path.parent.mkdir(exist_ok=True, parents=True)
    with open(out_path, "w") as fh:
        json.dump(geojson, fh, separators=(",", ":"))
    size_kb = out_path.stat().st_size // 1024
    print(f"\nSaved to {out_path} ({size_kb} KB)")


if __name__ == "__main__":
    out = Path(__file__).parent / "data" / "pjm_utility_zones.geojson"
    build_pjm_geojson(out)
