# pack_hf_spaces.ps1
#
# Packs the HOPE PCM and GTEP dashboards into ready-to-push Hugging Face Space
# directories under tools/hope_dashboard/deploy/hf-pcm-v8/ and hf-gtep/.
#
# Prerequisites:
#   pip install huggingface_hub          (for huggingface-cli login)
#   git lfs install                      (for large file support)
#
# Usage:
#   cd <repo_root>
#   .\tools\hope_dashboard\deploy\pack_hf_spaces.ps1
#
# After running this script:
#   1. Create two HF Spaces (Docker SDK) at https://huggingface.co/new-space
#        - hope-pcm-dashboard
#        - hope-gtep-dashboard
#      under the HOPE-Model-Project organization (or your personal account).
#   2. Clone each Space repo locally (git clone https://huggingface.co/spaces/...)
#   3. Copy the contents of hf-pcm-v8/ and hf-gtep/ into the cloned repos.
#   4. git lfs track "ModelCases/**/*.csv"
#   5. git add . && git commit -m "Initial deployment" && git push
#
# ─────────────────────────────────────────────────────────────────────────────

param(
    [string]$PcmOutName = "hf-pcm-v8",
    [string]$GtepOutName = "hf-gtep"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$DashDir     = Split-Path -Parent $ScriptDir          # tools/hope_dashboard
$RepoRoot    = Split-Path -Parent (Split-Path -Parent $DashDir)  # repo root
$ModelCases  = Join-Path $RepoRoot "ModelCases"
$OutPCM      = Join-Path $ScriptDir $PcmOutName
$OutGTEP     = Join-Path $ScriptDir $GtepOutName

function Copy-DirectoryContents {
    param(
        [string]$Source,
        [string]$Destination
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
}

# ── PCM Space ─────────────────────────────────────────────────────────────────
Write-Host "`n==> Packing PCM Space → $OutPCM" -ForegroundColor Cyan
if (Test-Path $OutPCM) { Remove-Item $OutPCM -Recurse -Force }
New-Item -ItemType Directory -Path $OutPCM | Out-Null

# Deployment config
Copy-Item (Join-Path $ScriptDir "pcm\Dockerfile") $OutPCM
Copy-Item (Join-Path $ScriptDir "pcm\README.md")  $OutPCM

# Dashboard source
Copy-Item (Join-Path $DashDir "app.py")          $OutPCM
Copy-Item (Join-Path $DashDir "data_loader.py")  $OutPCM
Copy-Item (Join-Path $DashDir "requirements.txt") $OutPCM
Copy-DirectoryContents (Join-Path $DashDir "assets") (Join-Path $OutPCM "assets")
Copy-DirectoryContents (Join-Path $DashDir "data") (Join-Path $OutPCM "data")

# Bundled PCM cases: finalized Germany 2-day nodal seasonal v8 pack plus
# the existing ISONE and RTS24 dashboard demos.
# Copy only dashboard-ready outputs, settings, and compact data folders to keep the HF repo small.
$PcmCases = @(
    @{
        Name = "GERMANY_PCM_nodal_jan15_2day_resource_cost_case_v8"
        Items = @("output", "Settings", "Data_GERMANY_PCM_nodal_jan15_2day_resource_cost_case_v8")
    },
    @{
        Name = "GERMANY_PCM_nodal_apr15_2day_resource_cost_case_v8"
        Items = @("output", "Settings", "Data_GERMANY_PCM_nodal_apr15_2day_resource_cost_case_v8")
    },
    @{
        Name = "GERMANY_PCM_nodal_jul15_2day_resource_cost_case_v8"
        Items = @("output", "Settings", "Data_GERMANY_PCM_nodal_jul15_2day_resource_cost_case_v8")
    },
    @{
        Name = "GERMANY_PCM_nodal_oct15_2day_resource_cost_case_v8"
        Items = @("output", "Settings", "Data_GERMANY_PCM_nodal_oct15_2day_resource_cost_case_v8")
    },
    @{
        Name = "ISONE_PCM_250bus_case"
        Items = @("output_nocarbon_check", "dashboard_output.txt", "Settings", "Data_ISONE_PCM_250bus")
    },
    @{
        Name = "RTS24_PCM_multizone4_congested_1month_case"
        Items = @("output", "Settings", "Data_RTS24_PCM_full")
    }
)
foreach ($caseSpec in $PcmCases) {
    $caseName = $caseSpec.Name
    $PcmCase = Join-Path $ModelCases $caseName
    $PcmCaseDst = Join-Path $OutPCM "ModelCases\$caseName"
    Write-Host "  Copying PCM case: $caseName ..."
    New-Item -ItemType Directory -Path $PcmCaseDst | Out-Null
    foreach ($sub in $caseSpec.Items) {
        $src = Join-Path $PcmCase $sub
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $PcmCaseDst $sub) -Recurse
        }
    }
}

$pcmSize = (Get-ChildItem $OutPCM -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
Write-Host "  PCM Space packed: $([math]::Round($pcmSize,1)) MB total" -ForegroundColor Green

# ── GTEP Space ────────────────────────────────────────────────────────────────
Write-Host "`n==> Packing GTEP Space → $OutGTEP" -ForegroundColor Cyan
if (Test-Path $OutGTEP) { Remove-Item $OutGTEP -Recurse -Force }
New-Item -ItemType Directory -Path $OutGTEP | Out-Null

# Deployment config
Copy-Item (Join-Path $ScriptDir "gtep\Dockerfile") $OutGTEP
Copy-Item (Join-Path $ScriptDir "gtep\README.md")  $OutGTEP

# Dashboard source
Copy-Item (Join-Path $DashDir "gtep_app.py")      $OutGTEP
Copy-Item (Join-Path $DashDir "requirements.txt") $OutGTEP
Copy-DirectoryContents (Join-Path $DashDir "assets") (Join-Path $OutGTEP "assets")
Copy-DirectoryContents (Join-Path $DashDir "data") (Join-Path $OutGTEP "data")

# Bundled sample cases for GTEP: PJM MD100 (4.7 MB) + USA 64-zone (11 MB) + MD clean fallback (0.1 MB)
foreach ($caseName in @("PJM_MD100_GTEP_case", "USA_64zone_GTEP_case", "MD_GTEP_clean_case")) {
    $src = Join-Path $ModelCases $caseName
    $dst = Join-Path $OutGTEP "ModelCases\$caseName"
    Write-Host "  Copying GTEP case: $caseName ..."
    New-Item -ItemType Directory -Path $dst | Out-Null
    foreach ($sub in @("output", "Settings")) {
        $subsrc = Join-Path $src $sub
        if (Test-Path $subsrc) {
            Copy-Item $subsrc (Join-Path $dst $sub) -Recurse
        }
    }
}

$gtepSize = (Get-ChildItem $OutGTEP -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
Write-Host "  GTEP Space packed: $([math]::Round($gtepSize,1)) MB total" -ForegroundColor Green

# ── Next steps ────────────────────────────────────────────────────────────────
Write-Host @"

==> Done!

Next steps to publish to Hugging Face:

  1. Go to https://huggingface.co/new-space
     Create two Docker Spaces under HOPE-Model-Project:
       • hope-pcm-dashboard
       • hope-gtep-dashboard

  2. Clone both Space repos:
       git clone https://huggingface.co/spaces/HOPE-Model-Project/hope-pcm-dashboard
       git clone https://huggingface.co/spaces/HOPE-Model-Project/hope-gtep-dashboard

  3. Copy packed files into each clone:
       Copy-Item "$OutPCM\*"  hope-pcm-dashboard\  -Recurse -Force
       Copy-Item "$OutGTEP\*" hope-gtep-dashboard\ -Recurse -Force

  4. Track large files with Git LFS or Git Xet (run inside each clone):
       git lfs install
       git lfs track "ModelCases/**/*.csv"
       git add .gitattributes

  5. Commit and push:
       git add .
       git commit -m "Deploy HOPE dashboard"
       git push

  Spaces will be available at:
    https://huggingface.co/spaces/HOPE-Model-Project/hope-pcm-dashboard
    https://huggingface.co/spaces/HOPE-Model-Project/hope-gtep-dashboard

"@ -ForegroundColor Yellow
