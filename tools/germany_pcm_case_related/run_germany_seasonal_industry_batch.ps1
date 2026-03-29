param(
  [string[]]$Cases = @(
    'ModelCases/GERMANY_PCM_nodal_jan_week3_baseline_case',
    'ModelCases/GERMANY_PCM_nodal_apr_week3_baseline_case',
    'ModelCases/GERMANY_PCM_nodal_jul_week3_baseline_case',
    'ModelCases/GERMANY_PCM_nodal_oct_week3_baseline_case'
  ),
  [switch]$SkipPackBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repoRoot

$julia = 'C:\Users\wangs\.julia\juliaup\julia-1.12.4+0.x64.w64.mingw32\bin\julia.exe'
$runner = 'tools/germany_pcm_case_related/run_hope_case.jl'
$logDir = 'tools/germany_pcm_case_related/outputs/seasonal_industry_batch_logs'

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Rotate-CaseOutput {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CasePath,
    [Parameter(Mandatory = $true)]
    [string]$BatchLog
  )

  $caseRoot = Join-Path $repoRoot $CasePath
  $outputPath = Join-Path $caseRoot 'output'
  if (-not (Test-Path $outputPath)) {
    return
  }

  $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $archivePath = Join-Path $caseRoot ("output_prebatch_{0}" -f $timestamp)
  Move-Item -Path $outputPath -Destination $archivePath -Force
  "[$(Get-Date -Format s)] Archived existing output for $(Split-Path $CasePath -Leaf) to $(Split-Path $archivePath -Leaf)" | Tee-Object -FilePath $BatchLog -Append
}

$batchLog = Join-Path $logDir 'batch_status.log'
"[$(Get-Date -Format s)] Starting seasonal industry batch" | Set-Content -Path $batchLog

foreach ($case in $Cases) {
  $caseName = Split-Path $case -Leaf
  $caseLog = Join-Path $logDir "$caseName.log"
  "[$(Get-Date -Format s)] Starting $caseName" | Tee-Object -FilePath $batchLog -Append
  Rotate-CaseOutput -CasePath $case -BatchLog $batchLog
  & $julia --project=. $runner $case *>&1 | Tee-Object -FilePath $caseLog
  if ($LASTEXITCODE -ne 0) {
    "[$(Get-Date -Format s)] FAILED $caseName with exit code $LASTEXITCODE" | Tee-Object -FilePath $batchLog -Append
    exit $LASTEXITCODE
  }
  "[$(Get-Date -Format s)] Finished $caseName" | Tee-Object -FilePath $batchLog -Append
}

if (-not $SkipPackBuild) {
  "[$(Get-Date -Format s)] Building seasonal validation pack" | Tee-Object -FilePath $batchLog -Append
  python 'tools/germany_pcm_case_related/build_germany_seasonal_validation_pack.py' *>&1 | Tee-Object -FilePath (Join-Path $logDir 'build_germany_seasonal_validation_pack.log')
  if ($LASTEXITCODE -ne 0) {
    "[$(Get-Date -Format s)] FAILED seasonal validation pack build with exit code $LASTEXITCODE" | Tee-Object -FilePath $batchLog -Append
    exit $LASTEXITCODE
  }
}

"[$(Get-Date -Format s)] Seasonal industry batch completed" | Tee-Object -FilePath $batchLog -Append
