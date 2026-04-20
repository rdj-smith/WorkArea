# ===== S3 -> OneDrive (GWAC + eGOS ID -> numeric folder) =====

# ---- SET THESE 3 ----
$Bucket   = "nextgen-prod2-data"
$InFile   = "C:\Temp\26Q2AWARDS.txt"   # tab-delimited file with headers: eGOS ID, GWAC
$DestRoot = "C:\Users\smithr6\OneDrive - National Institutes of Health\ShareDir\26Q2Awards"
# ---------------------

# --- Checks ---
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { throw "AWS CLI not found in PATH." }
if (!(Test-Path -LiteralPath $InFile)) { throw "Input file not found: $InFile" }
if (!(Test-Path -LiteralPath $DestRoot)) { New-Item -Path $DestRoot -ItemType Directory -Force | Out-Null }
$BaseDest = (Resolve-Path -LiteralPath $DestRoot).Path

# --- Import: try TAB first, then CSV ---
try {
  $rows = Import-Csv -LiteralPath $InFile -Delimiter "`t"
  if (-not ($rows[0].PSObject.Properties.Name -contains "GWAC")) { throw "Not tab format / headers not found" }
} catch {
  $rows = Import-Csv -LiteralPath $InFile
}

# --- Build map: GWAC + eGOS ID ---
$map = @()
foreach ($r in $rows) {
  $gwac = ("$($r.GWAC)").Trim()
  $egos = ("$($r.'eGOS ID')").Trim()

  if (-not $gwac -or -not $egos) { continue }

  # Accept plain numeric IDs (e.g. 121782) OR extract digits from formatted strings (e.g. CS-120460-SB)
  $m = [regex]::Match($egos, '^\d+$')
  if ($m.Success) {
    $id = $egos
  } else {
    $m = [regex]::Match($egos, '\d{6}')
    if (-not $m.Success) { continue }
    $id = $m.Value
  }

  $map += [PSCustomObject]@{ GWAC = $gwac; FolderID = $id }
}

# Deduplicate and validate
$map = $map | Sort-Object GWAC, FolderID -Unique
if (-not $map -or $map.Count -eq 0) { throw "No valid rows parsed. Check that headers include 'GWAC' and 'eGOS ID'." }

Write-Host "Will sync $($map.Count) folders into:" -ForegroundColor Cyan
Write-Host "  $BaseDest\<GWAC>\<FolderID>" -ForegroundColor Cyan

$flags   = @("--exact-timestamps","--only-show-errors","--no-progress")
$errors  = 0
$skipped = 0
$synced  = 0

foreach ($row in $map) {
  $gwac = $row.GWAC
  $id   = $row.FolderID

  $s3Prefix = "$gwac/$id/"
  $src      = "s3://$Bucket/$s3Prefix"

  $destGwac = Join-Path -Path $BaseDest -ChildPath $gwac
  $dest     = Join-Path -Path $destGwac -ChildPath $id

  if (!(Test-Path -LiteralPath $destGwac)) { New-Item -Path $destGwac -ItemType Directory -Force | Out-Null }
  if (!(Test-Path -LiteralPath $dest))     { New-Item -Path $dest     -ItemType Directory -Force | Out-Null }

  # --- Reliable non-empty check ---
  $countText = & aws s3api list-objects-v2 `
    --bucket $Bucket `
    --prefix $s3Prefix `
    --max-keys 1 `
    --query "KeyCount" `
    --output text 2>$null

  $count = 0
  if ($countText -match '^\d+$') { $count = [int]$countText }

  if ($count -eq 0) {
    Write-Host "Skipping empty: $src" -ForegroundColor Yellow
    $skipped++
    continue
  }

  # --- Sync ---
  Write-Host "Syncing: $src -> $dest" -ForegroundColor Gray
  & aws s3 sync $src $dest @flags
  if ($LASTEXITCODE -ne 0) {
    $errors++
    Write-Warning "Error syncing $gwac/$id (exit $LASTEXITCODE)"
  } else {
    $synced++
  }
}

Write-Host "Done. Synced: $synced  Skipped: $skipped  Errors: $errors" -ForegroundColor Green
Write-Host "Note: If you hit path-length errors, shorten DestRoot or enable LongPathsEnabled in Windows." -ForegroundColor DarkGray
