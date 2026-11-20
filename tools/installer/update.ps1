# Questmates updater.
# Checks the latest Questmates release on GitHub and, if it is newer than the installed one, replaces the
# Questmates addon folder with it. Runs hidden at Windows sign-in and every few hours (set up by the installer).
# It only downloads Questmates.zip from https://github.com/Bjornaman2/questmates/releases and only writes to the
# AddOns\Questmates folder. Log: %LOCALAPPDATA%\Questmates\update.log
#   -Uninstall   remove the automatic updates (the addon itself stays)
param([switch]$Uninstall, [string]$AddOns)

$ErrorActionPreference = 'Stop'
$Repo = 'Bjornaman2/questmates'
$Home_ = Join-Path $env:LOCALAPPDATA 'Questmates'
$LogFile = Join-Path $Home_ 'update.log'
$StartupFile = Join-Path ([Environment]::GetFolderPath('Startup')) 'Questmates Updater.vbs'

function Write-Log($msg) {
  try {
    if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 200KB) { Remove-Item $LogFile -Force }
    Add-Content -Path $LogFile -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $msg)
  } catch {}
}

if ($Uninstall) {
  schtasks.exe /Delete /F /TN 'Questmates Updater' 2>$null | Out-Null
  if (Test-Path $StartupFile) { Remove-Item $StartupFile -Force }
  Write-Log 'automatic updates removed'
  Write-Host 'Questmates will no longer update automatically. (The addon itself is still installed.)'
  return
}

try {
  if (-not $AddOns) {
    $cfg = Get-Content (Join-Path $Home_ 'config.json') -Raw | ConvertFrom-Json
    $AddOns = $cfg.addons
  }
  $target = Join-Path $AddOns 'Questmates'
  if ((Test-Path $target) -and (Get-Item $target).LinkType) { Write-Log 'developer copy (linked folder) - left alone'; return }

  $installed = '0.0.0'
  $toc = Join-Path $target 'Questmates.toc'
  if (Test-Path $toc) {
    $m = Select-String -Path $toc -Pattern '^## Version:\s*(\S+)'
    if ($m) { $installed = $m.Matches[0].Groups[1].Value }
  }

  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'Questmates-Updater' } -TimeoutSec 30
  $latest = ($rel.tag_name -replace '^v', '')
  if ([version]$latest -le [version]$installed) { Write-Log "up to date ($installed)"; return }

  $asset = $rel.assets | Where-Object { $_.name -eq 'Questmates.zip' } | Select-Object -First 1
  if (-not $asset) { Write-Log "release $latest has no Questmates.zip"; return }

  $stage = Join-Path $Home_ 'staging'
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  New-Item -ItemType Directory -Force $stage | Out-Null
  $zip = Join-Path $stage 'Questmates.zip'
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'Questmates-Updater' } -TimeoutSec 120
  Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $stage 'x') -Force
  $new = Join-Path $stage 'x\Questmates'
  $newToc = Join-Path $new 'Questmates.toc'
  if (-not (Test-Path $newToc)) { Write-Log 'download did not contain Questmates\Questmates.toc - skipped'; return }

  # swap: copy the new version next to the old one, then replace
  $incoming = Join-Path $AddOns 'Questmates.incoming'
  if (Test-Path $incoming) { Remove-Item $incoming -Recurse -Force }
  Copy-Item $new $incoming -Recurse -Force
  if (Test-Path $target) { Remove-Item $target -Recurse -Force }
  Rename-Item $incoming 'Questmates'
  Remove-Item $stage -Recurse -Force
  Write-Log "updated $installed -> $latest"
} catch {
  Write-Log ('error: ' + $_.Exception.Message)
}
