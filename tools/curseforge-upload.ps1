# Upload dist\Questmates.zip to the Questmates CurseForge project.
#   powershell -ExecutionPolicy Bypass -File tools\curseforge-upload.ps1 -Notes "what changed"
# Needs, once:
#   - tools\curseforge.json  { "projectId": 123456 }        (not secret; written by -SetProject)
#   - the owner's CurseForge API token in the user environment variable CURSEFORGE_TOKEN
#     (set by the owner in their own terminal:  setx CURSEFORGE_TOKEN "<token>")
# The token is read from the registry, sent in a header file that is deleted right away, and never printed.
param([string]$Notes = '', [int]$SetProject = 0, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$cfgFile = Join-Path $PSScriptRoot 'curseforge.json'

if ($SetProject -gt 0) {
  (@{ projectId = $SetProject } | ConvertTo-Json) | Out-File -Encoding utf8 $cfgFile
  Write-Host "CurseForge project set to $SetProject"
  return
}
if (-not (Test-Path $cfgFile)) { Write-Host 'CurseForge: no project ID yet (tools\curseforge.json) - skipped.'; return }
$projectId = (Get-Content $cfgFile -Raw | ConvertFrom-Json).projectId
$token = [Environment]::GetEnvironmentVariable('CURSEFORGE_TOKEN', 'User')
if (-not $token) { $token = $env:CURSEFORGE_TOKEN }
if (-not $token) { Write-Host 'CurseForge: no CURSEFORGE_TOKEN set - skipped.'; return }

$api = 'https://wow.curseforge.com/api'
$headerFile = Join-Path $env:TEMP ('cf_' + [guid]::NewGuid().ToString('N') + '.txt')
try {
  [IO.File]::WriteAllText($headerFile, "X-Api-Token: $token")

  # WoW Forever's game version on CurseForge (the newest 1.60.x)
  $raw = curl.exe -s -H "@$headerFile" "$api/game/versions"
  if (-not $raw -or $raw -match '^\s*<') { throw 'CurseForge did not accept the token (game versions request failed).' }
  $versions = $raw | ConvertFrom-Json
  $forever = $versions | Where-Object { $_.name -match '^1\.60(\.|$)' } |
             Sort-Object { [version]($_.name + $(if ($_.name -match '^\d+\.\d+$') { '.0' } else { '' })) } -Descending
  if (-not $forever) { throw 'CurseForge has no WoW Forever (1.60.x) game version.' }
  $gv = $forever[0]
  Write-Host ("CurseForge: project $projectId, game version " + $gv.name + " (id " + $gv.id + ")")
  if ($CheckOnly) { Write-Host 'CurseForge: token and project look fine.'; return }

  $toc = Get-Content (Join-Path $repo 'Questmates\Questmates.toc') -Raw
  $ver = ([regex]::Match($toc, '## Version:\s*(\S+)')).Groups[1].Value
  $zip = Join-Path $repo 'dist\Questmates.zip'
  if (-not (Test-Path $zip)) { throw 'dist\Questmates.zip is missing - run tools\release.ps1 first.' }

  $meta = @{
    changelog     = $(if ($Notes) { $Notes } else { "Questmates $ver" })
    changelogType = 'markdown'
    displayName   = "Questmates $ver"
    gameVersions  = @([int]$gv.id)
    releaseType   = 'release'
  } | ConvertTo-Json -Compress
  $metaFile = Join-Path $env:TEMP ('cfmeta_' + [guid]::NewGuid().ToString('N') + '.json')
  [IO.File]::WriteAllText($metaFile, $meta, (New-Object Text.UTF8Encoding($false)))
  try {
    $res = curl.exe -s -H "@$headerFile" -F "metadata=<$metaFile;type=application/json" -F "file=@$zip" "$api/projects/$projectId/upload-file"
  } finally { Remove-Item $metaFile -Force -ErrorAction SilentlyContinue }
  if ($res -match '"id"\s*:\s*(\d+)') { Write-Host "CurseForge: uploaded Questmates $ver (file id $($Matches[1])) - it appears after CurseForge's review." }
  else { throw ('CurseForge upload failed: ' + ($res -replace [regex]::Escape($token), '***')) }
} finally {
  Remove-Item $headerFile -Force -ErrorAction SilentlyContinue
}
