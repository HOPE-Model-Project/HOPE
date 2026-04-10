# pack_hf_spaces.ps1
#
# Packs the HOPE PCM and GTEP dashboards into ready-to-push Hugging Face Space
# directories under tools/hope_dashboard/deploy/hf-pcm/ and hf-gtep/.
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
#   3. Copy the contents of hf-pcm/ and hf-gtep/ into the cloned repos.
#   4. git lfs track "ModelCases/**/*.csv"
#   5. git add . && git commit -m "Initial deployment" && git push
#
# ─────────────────────────────────────────────────────────────────────────────

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$DashDir     = Split-Path -Parent $ScriptDir          # tools/hope_dashboard
$RepoRoot    = Split-Path -Parent (Split-Path -Parent $DashDir)  # repo root
$ModelCases  = Join-Path $RepoRoot "ModelCases"
$OutPCM      = Join-Path $ScriptDir "hf-pcm"
$OutGTEP     = Join-Path $ScriptDir "hf-gtep"

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
Copy-Item (Join-Path $DashDir "assets")  (Join-Path $OutPCM "assets")  -Recurse
Copy-Item (Join-Path $DashDir "data")    (Join-Path $OutPCM "data")    -Recurse

# Bundled sample case: Germany 2-day nodal PCM
$PcmCase    = Join-Path $ModelCases "GERMANY_PCM_nodal_jan_2day_rescaled_case"
$PcmCaseDst = Join-Path $OutPCM "ModelCases\GERMANY_PCM_nodal_jan_2day_rescaled_case"
Write-Host "  Copying PCM case output (~20 MB) ..."
New-Item -ItemType Directory -Path $PcmCaseDst | Out-Null
# Copy only the output and settings (not raw data inputs — keeps HF repo small)
foreach ($sub in @("output", "output_holistic", "Settings")) {
    $src = Join-Path $PcmCase $sub
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $PcmCaseDst $sub) -Recurse
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
Copy-Item (Join-Path $DashDir "assets")  (Join-Path $OutGTEP "assets")  -Recurse
Copy-Item (Join-Path $DashDir "data")    (Join-Path $OutGTEP "data")    -Recurse

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

  4. Track large files with Git LFS (run inside each clone):
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
