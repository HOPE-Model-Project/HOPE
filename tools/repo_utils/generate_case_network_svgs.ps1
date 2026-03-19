param(
    [string]$RootDir = ".",
    [string]$OutDir = "docs/src/assets"
)

$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$path) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

function Write-TextFile([string]$path, [string]$content) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

function Add-Line([System.Text.StringBuilder]$sb, [string]$line) {
    [void]$sb.AppendLine($line)
}

function Escape-Xml([string]$text) {
    if ($null -eq $text) { return "" }
    $t = $text
    $t = $t.Replace("&", "&amp;")
    $t = $t.Replace("<", "&lt;")
    $t = $t.Replace(">", "&gt;")
    $t = $t.Replace('"', "&quot;")
    $t = $t.Replace("'", "&apos;")
    return $t
}

function Build-PjmZoneMapSvg([string]$rootDir, [string]$outPath) {
    $zonePath = Join-Path $rootDir "ModelCases/PJM_MD100_GTEP_case/Data_PJM_GTEP_subzones/zonedata.csv"
    $linePath = Join-Path $rootDir "ModelCases/PJM_MD100_GTEP_case/Data_PJM_GTEP_subzones/linedata.csv"
    $zones = Import-Csv $zonePath
    $lines = Import-Csv $linePath

    $stateCenters = @{
        "IL" = [pscustomobject]@{X=120.0; Y=230.0}
        "MI" = [pscustomobject]@{X=280.0; Y=120.0}
        "IN" = [pscustomobject]@{X=250.0; Y=250.0}
        "OH" = [pscustomobject]@{X=360.0; Y=255.0}
        "PA" = [pscustomobject]@{X=560.0; Y=205.0}
        "NJ" = [pscustomobject]@{X=785.0; Y=235.0}
        "DE" = [pscustomobject]@{X=760.0; Y=300.0}
        "MD" = [pscustomobject]@{X=700.0; Y=330.0}
        "WV" = [pscustomobject]@{X=510.0; Y=335.0}
        "VA" = [pscustomobject]@{X=610.0; Y=430.0}
        "NC" = [pscustomobject]@{X=640.0; Y=530.0}
        "KY" = [pscustomobject]@{X=260.0; Y=430.0}
        "TN" = [pscustomobject]@{X=320.0; Y=520.0}
    }

    $utilityName = @{
        "AP"   = "Allegheny Power (AP)"
        "AEP"  = "American Electric Power (AEP)"
        "ATSI" = "ATSI"
        "AE"   = "Atlantic Electric (AE)"
        "BC"   = "Baltimore Gas and Electric (BGE)"
        "CE"   = "ComEd"
        "DAY"  = "Dayton (DAY)"
        "DEOK" = "Duke/DEOK"
        "DOM"  = "Dominion"
        "DPL"  = "Delmarva (DPL)"
        "DUQ"  = "Duquesne Light (DLCO)"
        "EKPC" = "East Kentucky Power Coop (EKPC)"
        "JC"   = "Jersey Central (JCPL)"
        "ME"   = "Met-Ed (METED)"
        "OVEC" = "Ohio Valley Electric (OVEC)"
        "PE"   = "Pennsylvania Electric (PENELEC)"
        "PEP"  = "PEPCO"
        "PL"   = "PPL"
        "PN"   = "Penelec/Penn Power (PN)"
        "PS"   = "PSE&G"
        "RECO" = "Rockland Electric (RECO)"
    }

    $utilityColor = @{
        "AP"   = "#4CAF50"
        "AEP"  = "#7FB3D5"
        "ATSI" = "#F4C542"
        "AE"   = "#B39DDB"
        "BC"   = "#AED581"
        "CE"   = "#BA68C8"
        "DAY"  = "#B0BEC5"
        "DEOK" = "#FB8C00"
        "DOM"  = "#8E44AD"
        "DPL"  = "#C5CAE9"
        "DUQ"  = "#8D4E2A"
        "EKPC" = "#E53935"
        "JC"   = "#F57C00"
        "ME"   = "#0097A7"
        "OVEC" = "#CFD8DC"
        "PE"   = "#D4E157"
        "PEP"  = "#9C27B0"
        "PL"   = "#1E3A8A"
        "PN"   = "#FDD835"
        "PS"   = "#90A4AE"
        "RECO" = "#64B5F6"
    }

    $zoneInfo = @{}
    $zonesByState = @{}
    foreach ($z in $zones) {
        $zone = [string]$z.Zone_id
        $state = [string]$z.State
        $parts = $zone.Split("_")
        $util = if ($parts.Count -gt 0) { $parts[0] } else { $zone }
        $zoneInfo[$zone] = [pscustomobject]@{
            Zone = $zone
            State = $state
            Utility = $util
            DemandMW = [double]$z.'Demand (MW)'
        }
        if (-not $zonesByState.ContainsKey($state)) { $zonesByState[$state] = @() }
        $zonesByState[$state] += $zone
    }

    $zonePos = @{}
    foreach ($state in $zonesByState.Keys) {
        $stateCenter = if ($stateCenters.ContainsKey($state)) { $stateCenters[$state] } else { [pscustomobject]@{X=480.0; Y=340.0} }
        $zoneList = @($zonesByState[$state] | Sort-Object)
        $m = $zoneList.Count
        $radius = if ($m -le 1) { 0.0 } elseif ($m -eq 2) { 16.0 } elseif ($m -le 4) { 24.0 } else { 33.0 }
        for ($i = 0; $i -lt $m; $i++) {
            $theta = -1.57079632679 + 2.0 * [math]::PI * $i / [math]::Max($m, 1)
            $x = $stateCenter.X + $radius * [math]::Cos($theta)
            $y = $stateCenter.Y + $radius * [math]::Sin($theta)
            $zonePos[$zoneList[$i]] = [pscustomobject]@{X=$x; Y=$y}
        }
    }

    # Aggregate lines by unordered zone pair.
    $edgeByPair = @{}
    foreach ($e in $lines) {
        $a = [string]$e.From_zone
        $b = [string]$e.To_zone
        if ($a -eq $b) { continue }
        if ($a -gt $b) { $tmp = $a; $a = $b; $b = $tmp }
        $k = "$a|$b"
        if (-not $edgeByPair.ContainsKey($k)) {
            $edgeByPair[$k] = [pscustomobject]@{
                A = $a
                B = $b
                Lines = 0
                CapMW = 0.0
            }
        }
        $edgeByPair[$k].Lines += 1
        $edgeByPair[$k].CapMW += [double]$e.'Capacity (MW)'
    }
    $edges = @($edgeByPair.Values)
    $maxCap = ($edges | Measure-Object -Property CapMW -Maximum).Maximum
    if (-not $maxCap) { $maxCap = 1.0 }

    $sb = New-Object System.Text.StringBuilder
    Add-Line $sb '<svg xmlns="http://www.w3.org/2000/svg" width="1180" height="830" viewBox="0 0 1180 830">'
    Add-Line $sb '<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#f7fbff"/><stop offset="100%" stop-color="#eef3f7"/></linearGradient></defs>'
    Add-Line $sb '<rect x="0" y="0" width="1180" height="830" fill="url(#bg)"/>'
    Add-Line $sb '<rect x="26" y="80" width="860" height="710" rx="12" fill="#ffffff" stroke="#d6dde5"/>'
    Add-Line $sb '<text x="32" y="40" font-size="28" font-family="Arial, sans-serif" fill="#1f2937">PJM_MD100_GTEP_case: Zone-Level Network Map</text>'
    Add-Line $sb '<text x="32" y="64" font-size="13" font-family="Arial, sans-serif" fill="#4b5563">Geography-style schematic using state anchors, zone IDs, and existing corridor capacities.</text>'

    foreach ($state in ($zonesByState.Keys | Sort-Object)) {
        if (-not $stateCenters.ContainsKey($state)) { continue }
        $c = $stateCenters[$state]
        $stateZoneCount = $zonesByState[$state].Count
        $r = 45 + 4 * [math]::Min($stateZoneCount, 5)
        Add-Line $sb ('<circle cx="{0:F1}" cy="{1:F1}" r="{2:F1}" fill="#f3f4f6" stroke="#d1d5db" stroke-dasharray="3 3"/>' -f $c.X, $c.Y, $r)
        Add-Line $sb ('<text x="{0:F1}" y="{1:F1}" font-size="12" text-anchor="middle" font-family="Arial, sans-serif" fill="#6b7280">{2}</text>' -f $c.X, ($c.Y + $r + 16.0), (Escape-Xml $state))
    }

    foreach ($e in $edges) {
        if (-not $zonePos.ContainsKey($e.A) -or -not $zonePos.ContainsKey($e.B)) { continue }
        $a = $zonePos[$e.A]
        $b = $zonePos[$e.B]
        $w = 0.6 + 4.8 * ($e.CapMW / $maxCap)
        $op = 0.24 + 0.42 * ($e.CapMW / $maxCap)
        Add-Line $sb ('<line x1="{0:F1}" y1="{1:F1}" x2="{2:F1}" y2="{3:F1}" stroke="#51606f" stroke-width="{4:F2}" opacity="{5:F2}"/>' -f $a.X, $a.Y, $b.X, $b.Y, $w, $op)
    }

    # Edge labels for the strongest interstate links.
    $labelEdges = @($edges | Sort-Object CapMW -Descending | Select-Object -First 18)
    foreach ($e in $labelEdges) {
        if (-not $zonePos.ContainsKey($e.A) -or -not $zonePos.ContainsKey($e.B)) { continue }
        $a = $zonePos[$e.A]
        $b = $zonePos[$e.B]
        $mx = ($a.X + $b.X) / 2.0
        $my = ($a.Y + $b.Y) / 2.0
        $txt = "{0}/{1} MW" -f $e.Lines, [math]::Round($e.CapMW,0)
        Add-Line $sb ('<rect x="{0:F1}" y="{1:F1}" width="78" height="14" rx="3" fill="#ffffff" stroke="#e5e7eb"/>' -f ($mx - 39.0), ($my - 8.0))
        Add-Line $sb ('<text x="{0:F1}" y="{1:F1}" font-size="9" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" fill="#4b5563">{2}</text>' -f $mx, ($my - 1.0), (Escape-Xml $txt))
    }

    foreach ($z in ($zoneInfo.Keys | Sort-Object)) {
        $info = $zoneInfo[$z]
        if (-not $zonePos.ContainsKey($z)) { continue }
        $p = $zonePos[$z]
        $color = if ($utilityColor.ContainsKey($info.Utility)) { $utilityColor[$info.Utility] } else { "#90a4ae" }
        Add-Line $sb ('<circle cx="{0:F1}" cy="{1:F1}" r="8.2" fill="{2}" stroke="#263238" stroke-width="0.9"/>' -f $p.X, $p.Y, $color)
        Add-Line $sb ('<text x="{0:F1}" y="{1:F1}" font-size="9.5" text-anchor="middle" font-family="Arial, sans-serif" fill="#111827">{2}</text>' -f $p.X, ($p.Y - 12.0), (Escape-Xml $z))
    }

    # Legend.
    Add-Line $sb '<rect x="900" y="90" width="255" height="700" rx="10" fill="#ffffff" stroke="#d6dde5"/>'
    Add-Line $sb '<text x="915" y="116" font-size="18" font-family="Arial, sans-serif" fill="#1f2937">Utilities</text>'
    Add-Line $sb '<text x="915" y="134" font-size="11" font-family="Arial, sans-serif" fill="#6b7280">Color keyed by zone utility prefix.</text>'

    $presentUtilities = @($zoneInfo.Values | ForEach-Object { $_.Utility } | Sort-Object -Unique)
    $row = 0
    foreach ($u in $presentUtilities) {
        $y = 160 + 28 * $row
        if ($y -gt 770) { break }
        $color = if ($utilityColor.ContainsKey($u)) { $utilityColor[$u] } else { "#90a4ae" }
        $uname = if ($utilityName.ContainsKey($u)) { $utilityName[$u] } else { $u }
        Add-Line $sb ('<rect x="915" y="{0:F1}" width="13" height="13" fill="{1}" stroke="#374151" stroke-width="0.6"/>' -f ($y - 10.0), $color)
        $legendText = "{0}: {1}" -f $u, $uname
        Add-Line $sb ('<text x="936" y="{0:F1}" font-size="11.2" font-family="Arial, sans-serif" fill="#374151">{1}</text>' -f $y, (Escape-Xml $legendText))
        $row += 1
    }

    Add-Line $sb '<rect x="38" y="742" width="420" height="38" rx="7" fill="#f8fafc" stroke="#dbe3ea"/>'
    Add-Line $sb '<text x="50" y="764" font-size="11.5" font-family="Arial, sans-serif" fill="#4b5563">Edges are aggregated zone-pair corridors; width scales with total existing capacity.</text>'
    Add-Line $sb '</svg>'

    Write-TextFile -path $outPath -content $sb.ToString()
}

function Build-RtsZoneMapSvg([string]$rootDir, [string]$outPath) {
    $linePath = Join-Path $rootDir "ModelCases/RTS24_PCM_multizone4_congested_1month_case/Data_RTS24_PCM_full/linedata.csv"
    $zonePath = Join-Path $rootDir "ModelCases/RTS24_PCM_multizone4_congested_1month_case/Data_RTS24_PCM_full/zonedata.csv"
    $lines = Import-Csv $linePath
    $zones = Import-Csv $zonePath

    $edgeByPair = @{}
    foreach ($e in $lines) {
        $a = [string]$e.From_zone
        $b = [string]$e.To_zone
        if ($a -eq $b) { continue }
        if ($a -gt $b) { $tmp = $a; $a = $b; $b = $tmp }
        $k = "$a|$b"
        if (-not $edgeByPair.ContainsKey($k)) {
            $edgeByPair[$k] = [pscustomobject]@{
                A = $a
                B = $b
                Lines = 0
                CapMW = 0.0
            }
        }
        $edgeByPair[$k].Lines += 1
        $edgeByPair[$k].CapMW += [double]$e.'Capacity (MW)'
    }

    $pos = @{
        "Z1" = [pscustomobject]@{ X = 210.0; Y = 170.0 }
        "Z2" = [pscustomobject]@{ X = 650.0; Y = 170.0 }
        "Z3" = [pscustomobject]@{ X = 650.0; Y = 500.0 }
        "Z4" = [pscustomobject]@{ X = 210.0; Y = 500.0 }
    }
    $zoneColor = @{
        "Z1" = "#A5D6A7"
        "Z2" = "#90CAF9"
        "Z3" = "#FFE082"
        "Z4" = "#CE93D8"
    }

    $peakByZone = @{}
    foreach ($z in $zones) {
        $peakByZone[[string]$z.Zone_id] = [math]::Round([double]$z.'Demand (MW)', 1)
    }
    $edges = @($edgeByPair.Values)
    $maxCap = ($edges | Measure-Object -Property CapMW -Maximum).Maximum
    if (-not $maxCap) { $maxCap = 1.0 }

    $sb = New-Object System.Text.StringBuilder
    Add-Line $sb '<svg xmlns="http://www.w3.org/2000/svg" width="920" height="660" viewBox="0 0 920 660">'
    Add-Line $sb '<defs><linearGradient id="bg2" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#f7fbff"/><stop offset="100%" stop-color="#eef3f7"/></linearGradient></defs>'
    Add-Line $sb '<rect x="0" y="0" width="920" height="660" fill="url(#bg2)"/>'
    Add-Line $sb '<rect x="22" y="74" width="876" height="564" rx="12" fill="#ffffff" stroke="#d6dde5"/>'
    Add-Line $sb '<text x="28" y="38" font-size="26" font-family="Arial, sans-serif" fill="#1f2937">RTS24 PCM: Zone-Level Network</text>'
    Add-Line $sb '<text x="28" y="62" font-size="13" font-family="Arial, sans-serif" fill="#4b5563">Corridor labels show line count and total MW between zones.</text>'

    foreach ($e in $edges) {
        $a = $pos[$e.A]
        $b = $pos[$e.B]
        $w = 2.0 + 10.0 * ($e.CapMW / $maxCap)
        Add-Line $sb ('<line x1="{0:F1}" y1="{1:F1}" x2="{2:F1}" y2="{3:F1}" stroke="#64748b" stroke-width="{4:F2}" opacity="0.75"/>' -f $a.X, $a.Y, $b.X, $b.Y, $w)
    }

    foreach ($e in $edges) {
        $a = $pos[$e.A]
        $b = $pos[$e.B]
        $mx = ($a.X + $b.X) / 2.0
        $my = ($a.Y + $b.Y) / 2.0
        $word = if ($e.Lines -eq 1) { "line" } else { "lines" }
        $label = "{0} {1}, {2} MW" -f $e.Lines, $word, [math]::Round($e.CapMW, 0)
        Add-Line $sb ('<rect x="{0:F1}" y="{1:F1}" width="128" height="20" rx="4" fill="#ffffff" stroke="#d9e2ec"/>' -f ($mx - 64.0), ($my - 10.0))
        Add-Line $sb ('<text x="{0:F1}" y="{1:F1}" font-size="11" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" fill="#334155">{2}</text>' -f $mx, ($my + 0.2), (Escape-Xml $label))
    }

    foreach ($z in @("Z1", "Z2", "Z3", "Z4")) {
        $p = $pos[$z]
        $peak = if ($peakByZone.ContainsKey($z)) { $peakByZone[$z] } else { "n/a" }
        $col = $zoneColor[$z]
        Add-Line $sb ('<circle cx="{0:F1}" cy="{1:F1}" r="52" fill="{2}" stroke="#334155" stroke-width="1.4"/>' -f $p.X, $p.Y, $col)
        Add-Line $sb ('<text x="{0:F1}" y="{1:F1}" font-size="24" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" fill="#1f2937">{2}</text>' -f $p.X, ($p.Y - 8.0), (Escape-Xml $z))
        Add-Line $sb ('<text x="{0:F1}" y="{1:F1}" font-size="12" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" fill="#334155">Peak: {2} MW</text>' -f $p.X, ($p.Y + 18.0), (Escape-Xml ([string]$peak)))
    }

    Add-Line $sb '</svg>'

    Write-TextFile -path $outPath -content $sb.ToString()
}

function Build-RtsNodalMapSvg([string]$rootDir, [string]$outPath) {
    $busPath = Join-Path $rootDir "ModelCases/RTS24_PCM_multizone4_congested_1month_case/Data_RTS24_PCM_full/busdata.csv"
    $linePath = Join-Path $rootDir "ModelCases/RTS24_PCM_multizone4_congested_1month_case/Data_RTS24_PCM_full/linedata.csv"
    $genPath = Join-Path $rootDir "ModelCases/RTS24_PCM_multizone4_congested_1month_case/Data_RTS24_PCM_full/gendata.csv"
    $buses = Import-Csv $busPath
    $lines = Import-Csv $linePath
    $gens = if (Test-Path $genPath) { Import-Csv $genPath } else { @() }

    $zoneRects = @{
        "Z1" = [pscustomobject]@{X=70.0;  Y=130.0; W=400.0; H=300.0}
        "Z2" = [pscustomobject]@{X=620.0; Y=130.0; W=400.0; H=300.0}
        "Z3" = [pscustomobject]@{X=620.0; Y=500.0; W=400.0; H=300.0}
        "Z4" = [pscustomobject]@{X=70.0;  Y=500.0; W=400.0; H=300.0}
    }
    $zoneStroke = @{
        "Z1" = "#2f7d32"
        "Z2" = "#1565c0"
        "Z3" = "#e48f00"
        "Z4" = "#7e22ce"
    }
    $zoneFill = @{
        "Z1" = "#e9f7ee"
        "Z2" = "#eaf2ff"
        "Z3" = "#fff6dc"
        "Z4" = "#f5ecff"
    }
    $rowByZone = @{ "Z1" = 1; "Z2" = 1; "Z3" = 2; "Z4" = 2 }
    $colByZone = @{ "Z1" = 1; "Z4" = 1; "Z2" = 2; "Z3" = 2 }

    $busData = @{}
    $busByZone = @{}
    $zoneLoad = @{}
    foreach ($b in $buses) {
        $id = [int]$b.Bus_id
        $z = [string]$b.Zone_id
        $load = 0.0
        if ($b.PSObject.Properties.Name -contains "Demand (MW)" -and -not [string]::IsNullOrWhiteSpace([string]$b.'Demand (MW)')) {
            $load = [double]$b.'Demand (MW)'
        } elseif ($b.PSObject.Properties.Name -contains "Load_share" -and -not [string]::IsNullOrWhiteSpace([string]$b.Load_share)) {
            $load = [double]$b.Load_share
        }
        $busData[$id] = [pscustomobject]@{
            Id = $id
            Zone = $z
            LoadMW = $load
        }
        if (-not $busByZone.ContainsKey($z)) { $busByZone[$z] = @() }
        if (-not $zoneLoad.ContainsKey($z)) { $zoneLoad[$z] = 0.0 }
        $busByZone[$z] += $id
        $zoneLoad[$z] += $load
    }
    foreach ($z in @($busByZone.Keys)) {
        $busByZone[$z] = @($busByZone[$z] | Sort-Object)
    }

    # Place buses by zone with a one-line style substation layout.
    $zoneSlots = @{
        "Z1" = @(
            [pscustomobject]@{X=210.0; Y=200.0},
            [pscustomobject]@{X=335.0; Y=240.0},
            [pscustomobject]@{X=335.0; Y=360.0},
            [pscustomobject]@{X=210.0; Y=320.0},
            [pscustomobject]@{X=135.0; Y=320.0},
            [pscustomobject]@{X=135.0; Y=200.0}
        )
        "Z2" = @(
            [pscustomobject]@{X=765.0; Y=200.0},
            [pscustomobject]@{X=890.0; Y=240.0},
            [pscustomobject]@{X=890.0; Y=360.0},
            [pscustomobject]@{X=765.0; Y=320.0},
            [pscustomobject]@{X=690.0; Y=320.0},
            [pscustomobject]@{X=690.0; Y=200.0}
        )
        "Z3" = @(
            [pscustomobject]@{X=765.0; Y=570.0},
            [pscustomobject]@{X=890.0; Y=610.0},
            [pscustomobject]@{X=890.0; Y=730.0},
            [pscustomobject]@{X=765.0; Y=690.0},
            [pscustomobject]@{X=690.0; Y=690.0},
            [pscustomobject]@{X=690.0; Y=570.0}
        )
        "Z4" = @(
            [pscustomobject]@{X=210.0; Y=570.0},
            [pscustomobject]@{X=335.0; Y=610.0},
            [pscustomobject]@{X=335.0; Y=730.0},
            [pscustomobject]@{X=210.0; Y=690.0},
            [pscustomobject]@{X=135.0; Y=690.0},
            [pscustomobject]@{X=135.0; Y=570.0}
        )
    }

    $busPos = @{}
    foreach ($z in @("Z1", "Z2", "Z3", "Z4")) {
        if (-not $busByZone.ContainsKey($z)) { continue }
        $arr = $busByZone[$z]
        $slots = if ($zoneSlots.ContainsKey($z)) { $zoneSlots[$z] } else { @() }
        for ($i = 0; $i -lt $arr.Count; $i++) {
            if ($i -lt $slots.Count) {
                $busPos[$arr[$i]] = [pscustomobject]@{
                    X = $slots[$i].X
                    Y = $slots[$i].Y
                    Zone = $z
                }
            } else {
                # Fallback if a zone has more buses than layout slots.
                $x = 260.0 + 55.0 * ($i - $slots.Count)
                $y = 250.0 + 26.0 * ($i - $slots.Count)
                $busPos[$arr[$i]] = [pscustomobject]@{
                    X = $x
                    Y = $y
                    Zone = $z
                }
            }
        }
    }

    # Generator badges by bus/type for EE-style visual cues.
    $genByBus = @{}
    foreach ($g in $gens) {
        if (-not ($g.PSObject.Properties.Name -contains "Bus_id")) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$g.Bus_id)) { continue }
        $bid = [int]$g.Bus_id
        if (-not $genByBus.ContainsKey($bid)) {
            $genByBus[$bid] = [ordered]@{
                Thermal = 0
                PV = 0
                Wind = 0
                Hydro = 0
                Other = 0
                Total = 0
            }
        }
        $m = $genByBus[$bid]
        $m.Total += 1

        $typ = [string]$g.Type
        $isThermal = $false
        if ($g.PSObject.Properties.Name -contains "Flag_thermal") {
            try { $isThermal = ([int]$g.Flag_thermal -eq 1) } catch { $isThermal = $false }
        }

        if ($isThermal -or $typ -match "Coal|NGCC|Gas|Oil|Nuclear") {
            $m.Thermal += 1
        } elseif ($typ -match "Solar") {
            $m.PV += 1
        } elseif ($typ -match "Wind") {
            $m.Wind += 1
        } elseif ($typ -match "Hydro") {
            $m.Hydro += 1
        } else {
            $m.Other += 1
        }
    }

    # Build line list with explicit line IDs from linedata row order.
    $lineList = @()
    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        $e = $lines[$idx]
        $lineId = $idx + 1
        $fb = [int]$e.from_bus
        $tb = [int]$e.to_bus
        $cap = [double]$e.'Capacity (MW)'
        if (-not $busPos.ContainsKey($fb) -or -not $busPos.ContainsKey($tb)) { continue }
        $sameZone = $busPos[$fb].Zone -eq $busPos[$tb].Zone
        $a = [math]::Min($fb, $tb)
        $b = [math]::Max($fb, $tb)
        $pairKey = "$a|$b"
        $lineList += [pscustomobject]@{
            LineId = $lineId
            From = $fb
            To = $tb
            CapMW = $cap
            PairKey = $pairKey
            SameZone = $sameZone
        }
    }

    $pairCounts = @{}
    foreach ($l in $lineList) {
        if (-not $pairCounts.ContainsKey($l.PairKey)) { $pairCounts[$l.PairKey] = 0 }
        $pairCounts[$l.PairKey] += 1
    }
    $pairSeen = @{}
    foreach ($l in $lineList) {
        if (-not $pairSeen.ContainsKey($l.PairKey)) { $pairSeen[$l.PairKey] = 0 }
        $pairSeen[$l.PairKey] += 1
        $n = $pairCounts[$l.PairKey]
        $k = $pairSeen[$l.PairKey]
        # Symmetric offsets for parallel/duplicate lines.
        $l | Add-Member -NotePropertyName OffsetIndex -NotePropertyValue ($k - (($n + 1.0) / 2.0))
    }

    # Per-bus tap allocation so line endpoints do not stack at the same bar point.
    $busInc = @{}
    foreach ($e in $lineList) {
        if (-not $busInc.ContainsKey($e.From)) { $busInc[$e.From] = @() }
        if (-not $busInc.ContainsKey($e.To)) { $busInc[$e.To] = @() }
        $busInc[$e.From] += [pscustomobject]@{ LineId = [int]$e.LineId; End = "from"; Other = [int]$e.To }
        $busInc[$e.To] += [pscustomobject]@{ LineId = [int]$e.LineId; End = "to"; Other = [int]$e.From }
    }

    $tapXMap = @{}
    foreach ($bid in $busInc.Keys) {
        if (-not $busPos.ContainsKey([int]$bid)) { continue }
        $bx = [double]$busPos[[int]$bid].X
        $by = [double]$busPos[[int]$bid].Y
        $inc = @($busInc[$bid])
        $inc = @($inc | Sort-Object @{
            Expression = {
                $ob = $busPos[[int]$_.Other]
                [math]::Atan2(([double]$ob.Y - $by), ([double]$ob.X - $bx))
            }
        }, @{ Expression = { [int]$_.LineId } })

        $n = $inc.Count
        $slots = @()
        switch ($n) {
            0 { $slots = @() }
            1 { $slots = @(0.0) }
            2 { $slots = @(-6.0, 6.0) }
            3 { $slots = @(-7.0, 0.0, 7.0) }
            4 { $slots = @(-8.0, -3.0, 3.0, 8.0) }
            5 { $slots = @(-9.0, -5.0, 0.0, 5.0, 9.0) }
            6 { $slots = @(-9.0, -6.0, -2.0, 2.0, 6.0, 9.0) }
            7 { $slots = @(-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0) }
            default {
                for ($i = 0; $i -lt $n; $i++) {
                    if ($n -le 1) {
                        $slots += 0.0
                    } else {
                        $slots += (-9.0 + 18.0 * $i / ($n - 1))
                    }
                }
            }
        }

        for ($i = 0; $i -lt $inc.Count; $i++) {
            $ent = $inc[$i]
            $k = "{0}|{1}" -f ([int]$ent.LineId), $ent.End
            $tapXMap[$k] = ($bx + [double]$slots[$i])
        }
    }

    $maxCap = ($lineList | Measure-Object -Property CapMW -Maximum).Maximum
    if (-not $maxCap) { $maxCap = 1.0 }

    $sb = New-Object System.Text.StringBuilder
    Add-Line $sb '<svg xmlns="http://www.w3.org/2000/svg" width="1420" height="920" viewBox="0 0 1420 920">'
    Add-Line $sb '<defs><linearGradient id="bg3" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#f5f6f8"/><stop offset="100%" stop-color="#eceef2"/></linearGradient></defs>'
    Add-Line $sb '<rect x="0" y="0" width="1420" height="920" fill="url(#bg3)"/>'
    Add-Line $sb '<rect x="24" y="84" width="1040" height="804" rx="12" fill="#f3f4f6" stroke="#cfd4dc"/>'
    Add-Line $sb '<text x="28" y="42" font-size="40" font-family="Times New Roman, serif" fill="#111827">RTS24 PCM: 4-Zone, 24-Node Network</text>'
    Add-Line $sb '<text x="30" y="72" font-size="14" font-family="Arial, sans-serif" fill="#4b5563">Single-line schematic. Node labels are IDs, and line-number bubbles follow linedata row IDs.</text>'

    # Fixed one-line routes for clearer topology and fewer overlaps.
    $routeOverrides = @{
        1  = @([pscustomobject]@{X=210.0;Y=188.0}, [pscustomobject]@{X=335.0;Y=188.0}, [pscustomobject]@{X=335.0;Y=240.0})
        2  = @([pscustomobject]@{X=198.0;Y=200.0}, [pscustomobject]@{X=198.0;Y=360.0}, [pscustomobject]@{X=335.0;Y=360.0})
        3  = @([pscustomobject]@{X=185.0;Y=200.0}, [pscustomobject]@{X=185.0;Y=320.0}, [pscustomobject]@{X=135.0;Y=320.0})
        4  = @([pscustomobject]@{X=335.0;Y=252.0}, [pscustomobject]@{X=250.0;Y=252.0}, [pscustomobject]@{X=250.0;Y=320.0}, [pscustomobject]@{X=210.0;Y=320.0})
        5  = @([pscustomobject]@{X=335.0;Y=228.0}, [pscustomobject]@{X=250.0;Y=228.0}, [pscustomobject]@{X=250.0;Y=200.0}, [pscustomobject]@{X=135.0;Y=200.0})
        6  = @([pscustomobject]@{X=335.0;Y=348.0}, [pscustomobject]@{X=890.0;Y=348.0}, [pscustomobject]@{X=890.0;Y=360.0})
        7  = @([pscustomobject]@{X=315.0;Y=360.0}, [pscustomobject]@{X=315.0;Y=570.0}, [pscustomobject]@{X=135.0;Y=570.0})
        8  = @([pscustomobject]@{X=210.0;Y=336.0}, [pscustomobject]@{X=890.0;Y=336.0}, [pscustomobject]@{X=890.0;Y=360.0})
        9  = @([pscustomobject]@{X=135.0;Y=324.0}, [pscustomobject]@{X=765.0;Y=324.0}, [pscustomobject]@{X=765.0;Y=320.0})
        10 = @([pscustomobject]@{X=135.0;Y=300.0}, [pscustomobject]@{X=765.0;Y=300.0}, [pscustomobject]@{X=765.0;Y=320.0})
        11 = @([pscustomobject]@{X=765.0;Y=188.0}, [pscustomobject]@{X=890.0;Y=188.0}, [pscustomobject]@{X=890.0;Y=240.0})
        12 = @([pscustomobject]@{X=902.0;Y=240.0}, [pscustomobject]@{X=902.0;Y=360.0}, [pscustomobject]@{X=890.0;Y=360.0})
        13 = @([pscustomobject]@{X=890.0;Y=228.0}, [pscustomobject]@{X=825.0;Y=228.0}, [pscustomobject]@{X=825.0;Y=320.0}, [pscustomobject]@{X=765.0;Y=320.0})
        14 = @([pscustomobject]@{X=890.0;Y=372.0}, [pscustomobject]@{X=690.0;Y=372.0}, [pscustomobject]@{X=690.0;Y=320.0})
        15 = @([pscustomobject]@{X=890.0;Y=356.0}, [pscustomobject]@{X=740.0;Y=356.0}, [pscustomobject]@{X=740.0;Y=200.0}, [pscustomobject]@{X=690.0;Y=200.0})
        16 = @([pscustomobject]@{X=765.0;Y=308.0}, [pscustomobject]@{X=690.0;Y=308.0})
        17 = @([pscustomobject]@{X=765.0;Y=296.0}, [pscustomobject]@{X=725.0;Y=296.0}, [pscustomobject]@{X=725.0;Y=200.0}, [pscustomobject]@{X=690.0;Y=200.0})
        18 = @([pscustomobject]@{X=690.0;Y=370.0}, [pscustomobject]@{X=765.0;Y=370.0}, [pscustomobject]@{X=765.0;Y=570.0})
        19 = @([pscustomobject]@{X=690.0;Y=345.0}, [pscustomobject]@{X=890.0;Y=345.0}, [pscustomobject]@{X=890.0;Y=610.0})
        20 = @([pscustomobject]@{X=690.0;Y=222.0}, [pscustomobject]@{X=765.0;Y=222.0}, [pscustomobject]@{X=765.0;Y=570.0})
        21 = @([pscustomobject]@{X=560.0;Y=200.0}, [pscustomobject]@{X=560.0;Y=690.0}, [pscustomobject]@{X=135.0;Y=690.0})
        22 = @([pscustomobject]@{X=765.0;Y=560.0}, [pscustomobject]@{X=135.0;Y=560.0}, [pscustomobject]@{X=135.0;Y=690.0})
        23 = @([pscustomobject]@{X=890.0;Y=622.0}, [pscustomobject]@{X=820.0;Y=622.0}, [pscustomobject]@{X=820.0;Y=690.0}, [pscustomobject]@{X=765.0;Y=690.0})
        24 = @([pscustomobject]@{X=890.0;Y=718.0}, [pscustomobject]@{X=765.0;Y=718.0}, [pscustomobject]@{X=765.0;Y=690.0})
        25 = @([pscustomobject]@{X=890.0;Y=720.0}, [pscustomobject]@{X=335.0;Y=720.0}, [pscustomobject]@{X=335.0;Y=730.0})
        26 = @([pscustomobject]@{X=890.0;Y=708.0}, [pscustomobject]@{X=335.0;Y=708.0}, [pscustomobject]@{X=335.0;Y=730.0})
        27 = @([pscustomobject]@{X=890.0;Y=676.0}, [pscustomobject]@{X=135.0;Y=676.0}, [pscustomobject]@{X=135.0;Y=570.0})
        28 = @([pscustomobject]@{X=765.0;Y=702.0}, [pscustomobject]@{X=690.0;Y=702.0}, [pscustomobject]@{X=690.0;Y=690.0})
        29 = @([pscustomobject]@{X=765.0;Y=650.0}, [pscustomobject]@{X=210.0;Y=650.0}, [pscustomobject]@{X=210.0;Y=570.0})
        30 = @([pscustomobject]@{X=690.0;Y=678.0}, [pscustomobject]@{X=670.0;Y=678.0}, [pscustomobject]@{X=670.0;Y=570.0})
        31 = @([pscustomobject]@{X=690.0;Y=682.0}, [pscustomobject]@{X=210.0;Y=682.0}, [pscustomobject]@{X=210.0;Y=690.0})
        32 = @([pscustomobject]@{X=690.0;Y=582.0}, [pscustomobject]@{X=500.0;Y=582.0}, [pscustomobject]@{X=500.0;Y=730.0}, [pscustomobject]@{X=335.0;Y=730.0})
        33 = @([pscustomobject]@{X=690.0;Y=594.0}, [pscustomobject]@{X=520.0;Y=594.0}, [pscustomobject]@{X=520.0;Y=730.0}, [pscustomobject]@{X=335.0;Y=730.0})
        34 = @([pscustomobject]@{X=210.0;Y=598.0}, [pscustomobject]@{X=335.0;Y=598.0}, [pscustomobject]@{X=335.0;Y=610.0})
        35 = @([pscustomobject]@{X=210.0;Y=586.0}, [pscustomobject]@{X=335.0;Y=586.0}, [pscustomobject]@{X=335.0;Y=610.0})
        36 = @([pscustomobject]@{X=335.0;Y=622.0}, [pscustomobject]@{X=230.0;Y=622.0}, [pscustomobject]@{X=230.0;Y=690.0}, [pscustomobject]@{X=135.0;Y=690.0})
        37 = @([pscustomobject]@{X=335.0;Y=634.0}, [pscustomobject]@{X=250.0;Y=634.0}, [pscustomobject]@{X=250.0;Y=690.0}, [pscustomobject]@{X=135.0;Y=690.0})
        38 = @([pscustomobject]@{X=335.0;Y=718.0}, [pscustomobject]@{X=210.0;Y=718.0}, [pscustomobject]@{X=210.0;Y=690.0})
    }

    # Shaded zone areas.
    foreach ($z in @("Z1", "Z2", "Z3", "Z4")) {
        if (-not $zoneRects.ContainsKey($z)) { continue }
        $r = $zoneRects[$z]
        $f = $zoneFill[$z]
        $s = $zoneStroke[$z]
        Add-Line $sb ('<rect x="{0:F1}" y="{1:F1}" width="{2:F1}" height="{3:F1}" rx="18" fill="{4}" fill-opacity="0.55" stroke="{5}" stroke-width="1.6" stroke-dasharray="8 6"/>' -f $r.X, $r.Y, $r.W, $r.H, $f, $s)
        Add-Line $sb ('<text x="{0:F1}" y="{1:F1}" font-size="34" font-family="Times New Roman, serif" fill="{2}">{3}</text>' -f ($r.X + 14.0), ($r.Y + 34.0), $s, (Escape-Xml $z))
    }

    foreach ($e in $lineList) {
        if (-not $busPos.ContainsKey($e.From) -or -not $busPos.ContainsKey($e.To)) { continue }
        if (-not $busData.ContainsKey($e.From) -or -not $busData.ContainsKey($e.To)) { continue }

        $a = $busPos[$e.From]
        $b = $busPos[$e.To]
        $za = $busData[$e.From].Zone
        $zb = $busData[$e.To].Zone
        $off = [double]$e.OffsetIndex

        $x1 = [double]$a.X
        $y1 = [double]$a.Y
        $x2 = [double]$b.X
        $y2 = [double]$b.Y

        $tapFromKey = "{0}|from" -f ([int]$e.LineId)
        $tapToKey = "{0}|to" -f ([int]$e.LineId)
        $sx = if ($tapXMap.ContainsKey($tapFromKey)) { [double]$tapXMap[$tapFromKey] } else { $x1 }
        $tx = if ($tapXMap.ContainsKey($tapToKey)) { [double]$tapXMap[$tapToKey] } else { $x2 }

        $overridePts = @()
        if ($routeOverrides.ContainsKey([int]$e.LineId)) {
            foreach ($rp in $routeOverrides[[int]$e.LineId]) {
                $px = [double]$rp.X
                $py = [double]$rp.Y
                $isFromCenter = ([math]::Abs($px - $x1) -lt 0.6) -and ([math]::Abs($py - $y1) -lt 0.6)
                $isToCenter = ([math]::Abs($px - $x2) -lt 0.6) -and ([math]::Abs($py - $y2) -lt 0.6)
                if ($isFromCenter -or $isToCenter) { continue }
                $overridePts += [pscustomobject]@{ X = $px; Y = $py }
            }
        } elseif ($e.SameZone) {
            $xMid = (($sx + $tx) / 2.0) + 12.0 * $off
            $overridePts += [pscustomobject]@{ X = $xMid; Y = $y1 }
            $overridePts += [pscustomobject]@{ X = $xMid; Y = $y2 }
        } else {
            $laneX = 545.0 + 12.0 * $off
            $laneY = 468.0 + 12.0 * $off
            $overridePts += [pscustomobject]@{ X = $laneX; Y = $y1 }
            $overridePts += [pscustomobject]@{ X = $laneX; Y = $laneY }
            $overridePts += [pscustomobject]@{ X = $tx; Y = $laneY }
        }

        $defaultSignFrom = if (($za -eq "Z1") -or ($za -eq "Z2")) { 1.0 } else { -1.0 }
        $defaultSignTo = if (($zb -eq "Z1") -or ($zb -eq "Z2")) { 1.0 } else { -1.0 }
        $tFrom = if ($overridePts.Count -gt 0) { [double]$overridePts[0].Y } else { $y1 + 8.0 * $defaultSignFrom }
        $tTo = if ($overridePts.Count -gt 0) { [double]$overridePts[$overridePts.Count - 1].Y } else { $y2 + 8.0 * $defaultSignTo }
        $sgnFrom = [math]::Sign($tFrom - $y1)
        $sgnTo = [math]::Sign($tTo - $y2)
        if ($sgnFrom -eq 0) { $sgnFrom = $defaultSignFrom }
        if ($sgnTo -eq 0) { $sgnTo = $defaultSignTo }

        $leadFromY = $y1 + 8.0 * $sgnFrom
        $leadToY = $y2 + 8.0 * $sgnTo
        if (($overridePts.Count -gt 0) -and ([math]::Abs([double]$overridePts[0].Y - $y1) -lt 0.6)) { $leadFromY = $y1 }
        if (($overridePts.Count -gt 0) -and ([math]::Abs([double]$overridePts[$overridePts.Count - 1].Y - $y2) -lt 0.6)) { $leadToY = $y2 }

        $pts = @([pscustomobject]@{ X = $sx; Y = $y1 })
        $pts += [pscustomobject]@{ X = $sx; Y = $leadFromY }
        foreach ($rp in $overridePts) {
            $pts += [pscustomobject]@{ X = [double]$rp.X; Y = [double]$rp.Y }
        }
        $pts += [pscustomobject]@{ X = $tx; Y = $leadToY }
        $pts += [pscustomobject]@{ X = $tx; Y = $y2 }

        $ptsDedup = @()
        foreach ($p in $pts) {
            if ($ptsDedup.Count -eq 0) {
                $ptsDedup += $p
                continue
            }
            $q = $ptsDedup[$ptsDedup.Count - 1]
            if (([math]::Abs($p.X - $q.X) -gt 0.05) -or ([math]::Abs($p.Y - $q.Y) -gt 0.05)) {
                $ptsDedup += $p
            }
        }

        $ptString = ($ptsDedup | ForEach-Object { "{0:F1},{1:F1}" -f $_.X, $_.Y }) -join " "
        $w = 0.7 + 1.1 * ($e.CapMW / $maxCap)
        if (-not $e.SameZone) { $w += 0.12 }
        Add-Line $sb ('<polyline points="{0}" fill="none" stroke="#111827" stroke-width="{1:F2}" stroke-linecap="round" stroke-linejoin="round" opacity="0.92"/>' -f $ptString, $w)

        $lx = 0.0
        $ly = 0.0
        if ($ptsDedup.Count -ge 3) {
            $midSeg = [int][math]::Floor(($ptsDedup.Count - 1) / 2.0)
            if ($midSeg -lt 1) { $midSeg = 1 }
            $p1 = $ptsDedup[$midSeg - 1]
            $p2 = $ptsDedup[$midSeg]
            $lx = (($p1.X + $p2.X) / 2.0) + 5.0 + 2.0 * $off
            $ly = (($p1.Y + $p2.Y) / 2.0) - 8.0 - 2.0 * $off
        } else {
            $lx = (($x1 + $x2) / 2.0) + 4.0
            $ly = (($y1 + $y2) / 2.0) - 8.0
        }

        Add-Line $sb ('<circle cx="{0:F1}" cy="{1:F1}" r="8.2" fill="#ffffff" stroke="#94a3b8" stroke-width="1.1"/>' -f $lx, $ly)
        Add-Line $sb ('<text x="{0:F1}" y="{1:F1}" font-size="8.8" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" fill="#1f2937">{2}</text>' -f $lx, $ly, (Escape-Xml ([string]$e.LineId)))
    }

    foreach ($id in ($busPos.Keys | Sort-Object {[int]$_})) {
        if (-not $busData.ContainsKey([int]$id)) { continue }
        $b = $busPos[$id]
        $zone = $busData[[int]$id].Zone
        $loadMW = [double]$busData[[int]$id].LoadMW
        $x = [double]$b.X
        $y = [double]$b.Y

        $barHalf = 10.5
        Add-Line $sb ('<line x1="{0:F1}" y1="{1:F1}" x2="{2:F1}" y2="{1:F1}" stroke="#0f172a" stroke-width="4.2" stroke-linecap="round"/>' -f ($x - $barHalf), $y, ($x + $barHalf))
        Add-Line $sb ('<circle cx="{0:F1}" cy="{1:F1}" r="2.2" fill="#0f172a"/>' -f $x, $y)

        $labelAnchor = if ($zone -in @("Z2", "Z3")) { "end" } else { "start" }
        $labelX = if ($zone -in @("Z2", "Z3")) { $x - 17.0 } else { $x + 17.0 }
        Add-Line $sb ('<text x="{0:F1}" y="{1:F1}" font-size="15" text-anchor="{3}" font-family="Times New Roman, serif" fill="#111827">{2}</text>' -f $labelX, ($y - 5.0), (Escape-Xml ([string]$id)), $labelAnchor)
        if ($loadMW -gt 0.0) {
            # Put arrow at 1/3 of the bar length (not at center) to reduce overlaps.
            $arrowX = $x - ($barHalf / 3.0)
            Add-Line $sb ('<line x1="{0:F1}" y1="{1:F1}" x2="{0:F1}" y2="{2:F1}" stroke="#111827" stroke-width="1.2"/>' -f $arrowX, $y, ($y + 9.5))
            Add-Line $sb ('<polygon points="{0:F1},{1:F1} {2:F1},{1:F1} {3:F1},{4:F1}" fill="#111827"/>' -f ($arrowX - 2.7), ($y + 8.0), ($arrowX + 2.7), $arrowX, ($y + 12.2))
        }

        if ($genByBus.ContainsKey([int]$id)) {
            $g = $genByBus[[int]$id]
            $marks = @()
            if ($g.Thermal -gt 0) { $marks += [pscustomobject]@{Txt=("T{0}" -f $g.Thermal); C="#f97316"} }
            if ($g.PV -gt 0) { $marks += [pscustomobject]@{Txt=("PV{0}" -f $g.PV); C="#f59e0b"} }
            if ($g.Wind -gt 0) { $marks += [pscustomobject]@{Txt=("W{0}" -f $g.Wind); C="#0ea5e9"} }
            if ($g.Hydro -gt 0) { $marks += [pscustomobject]@{Txt=("H{0}" -f $g.Hydro); C="#0891b2"} }
            if ($g.Other -gt 0) { $marks += [pscustomobject]@{Txt=("G{0}" -f $g.Other); C="#64748b"} }

            if ($marks.Count -gt 0) {
                $x0 = $x - (22.0 * ($marks.Count - 1) / 2.0)
                for ($mi = 0; $mi -lt $marks.Count; $mi++) {
                    $mk = $marks[$mi]
                    $mx = $x0 + 22.0 * $mi
                    $my = $y - 36.0
                    Add-Line $sb ('<line x1="{0:F1}" y1="{1:F1}" x2="{0:F1}" y2="{2:F1}" stroke="{3}" stroke-width="1.1" opacity="0.95"/>' -f $mx, ($my + 10.4), ($y - 5.0), $mk.C)
                    Add-Line $sb ('<circle cx="{0:F1}" cy="{1:F1}" r="10.4" fill="#ffffff" stroke="{2}" stroke-width="2.3"/>' -f $mx, $my, $mk.C)
                    Add-Line $sb ('<text x="{0:F1}" y="{1:F1}" font-size="8.4" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" fill="#111827">{2}</text>' -f $mx, $my, (Escape-Xml $mk.Txt))
                }
            }
        }
    }

    Add-Line $sb '<rect x="1080" y="120" width="320" height="438" rx="10" fill="#ffffff" stroke="#cfd4dc"/>'
    Add-Line $sb '<text x="1100" y="152" font-size="30" font-family="Times New Roman, serif" fill="#111827">Legend</text>'
    Add-Line $sb '<line x1="1100" y1="178" x2="1180" y2="178" stroke="#111827" stroke-width="2.6"/><text x="1194" y="183" font-size="14" font-family="Arial, sans-serif" fill="#334155">Transmission line (all lines)</text>'
    Add-Line $sb '<circle cx="1112" cy="208" r="8.2" fill="#ffffff" stroke="#94a3b8" stroke-width="1.1"/><text x="1112" y="208" font-size="8.8" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" fill="#1f2937">12</text><text x="1130" y="213" font-size="14" font-family="Arial, sans-serif" fill="#334155">Line ID (linedata row)</text>'
    Add-Line $sb '<line x1="1100" y1="246" x2="1121" y2="246" stroke="#0f172a" stroke-width="4.2" stroke-linecap="round"/><text x="1175" y="251" font-size="14" font-family="Arial, sans-serif" fill="#334155">Node bar (bold)</text>'
    Add-Line $sb '<line x1="1107" y1="246" x2="1107" y2="255.5" stroke="#111827" stroke-width="1.2"/><polygon points="1104.3,254.0 1109.7,254.0 1107,258.2" fill="#111827"/><text x="1130" y="272" font-size="14" font-family="Arial, sans-serif" fill="#334155">Load arrow (if load &gt; 0)</text>'
    Add-Line $sb '<circle cx="1110" cy="316" r="10.4" fill="#ffffff" stroke="#f97316" stroke-width="2.3"/><text x="1110" y="316" font-size="8.4" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" fill="#111827">T1</text><text x="1130" y="321" font-size="14" font-family="Arial, sans-serif" fill="#334155">Thermal units at bus</text>'
    Add-Line $sb '<circle cx="1110" cy="346" r="10.4" fill="#ffffff" stroke="#f59e0b" stroke-width="2.3"/><text x="1110" y="346" font-size="8.4" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" fill="#111827">PV1</text><text x="1130" y="351" font-size="14" font-family="Arial, sans-serif" fill="#334155">Solar units at bus</text>'
    Add-Line $sb '<circle cx="1110" cy="376" r="10.4" fill="#ffffff" stroke="#0ea5e9" stroke-width="2.3"/><text x="1110" y="376" font-size="8.4" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" fill="#111827">W1</text><text x="1130" y="381" font-size="14" font-family="Arial, sans-serif" fill="#334155">Wind units at bus</text>'
    Add-Line $sb '<circle cx="1110" cy="406" r="10.4" fill="#ffffff" stroke="#0891b2" stroke-width="2.3"/><text x="1110" y="406" font-size="8.4" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" fill="#111827">H1</text><text x="1130" y="411" font-size="14" font-family="Arial, sans-serif" fill="#334155">Hydro units at bus</text>'
    Add-Line $sb '<text x="1100" y="448" font-size="13" font-family="Arial, sans-serif" fill="#475569">Colored dashed regions indicate the four zones.</text>'
    Add-Line $sb '<text x="1100" y="468" font-size="13" font-family="Arial, sans-serif" fill="#475569">Line widths scale by transmission capacity (MW).</text>'
    Add-Line $sb '<text x="1100" y="488" font-size="13" font-family="Arial, sans-serif" fill="#475569">Multiple parallel lines keep unique IDs (e.g., 25/26).</text>'
    Add-Line $sb '<text x="1100" y="518" font-size="13" font-family="Arial, sans-serif" fill="#64748b">Source: RTS24 PCM case busdata/linedata/gendata.</text>'

    Add-Line $sb '<text x="34" y="908" font-size="12.8" font-family="Arial, sans-serif" fill="#334155">Nodal note: this diagram uses orthogonal routing; topology and line IDs are data-driven from the case files.</text>'
    Add-Line $sb '</svg>'

    Write-TextFile -path $outPath -content $sb.ToString()
}

$out = Join-Path $RootDir $OutDir
Ensure-Dir $out

$pjmOut = Join-Path $out "modelcases_pjm_md100_zone_map.svg"
$rtsZoneOut = Join-Path $out "modelcases_rts24_multizone4_zone_map.svg"
$rtsNodalOut = Join-Path $out "modelcases_rts24_multizone4_nodal_map.svg"

Build-PjmZoneMapSvg -rootDir $RootDir -outPath $pjmOut
Build-RtsZoneMapSvg -rootDir $RootDir -outPath $rtsZoneOut
Build-RtsNodalMapSvg -rootDir $RootDir -outPath $rtsNodalOut

Write-Host "Wrote:"
Write-Host " - $pjmOut"
Write-Host " - $rtsZoneOut"
Write-Host " - $rtsNodalOut"
