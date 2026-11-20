# Publish a Questmates release.
#   1. bump "## Version:" in Questmates\Questmates.toc and QM.VERSION in Questmates\Core.lua (same number)
#   2. run:  powershell -ExecutionPolicy Bypass -File tools\release.ps1 -Notes "what changed"
# Builds dist\Questmates.zip and dist\Install Questmates.bat (also copied to the Desktop), commits, tags vX.Y.Z,
# pushes, and creates the GitHub release. Everyone with the installer's auto-updater gets it within ~3 hours
# (or at their next Windows sign-in).
param([string]$Notes = '', [switch]$NoPublish)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo

$toc = Get-Content "$repo\Questmates\Questmates.toc" -Raw
$ver = ([regex]::Match($toc, '## Version:\s*(\S+)')).Groups[1].Value
$core = Get-Content "$repo\Questmates\Core.lua" -Raw
$coreVer = ([regex]::Match($core, 'QM\.VERSION = "([^"]+)"')).Groups[1].Value
if ($ver -ne $coreVer) { throw "Version mismatch: toc $ver, Core.lua $coreVer" }
if (git tag --list "v$ver") { throw "v$ver is already released - bump the version first" }

# build
$dist = "$repo\dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = "$dist\Questmates.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$repo\Questmates" -DestinationPath $zip
$head = (Get-Content "$repo\tools\installer\installer_head.txt" -Raw) -replace "`r?`n", "`r`n"
$upd = (Get-Content "$repo\tools\installer\update.ps1" -Raw) -replace "`r?`n", "`r`n"
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($zip))
$bat = "$dist\Install Questmates.bat"
[IO.File]::WriteAllText($bat, $head + "#UPD_START#`r`n" + $upd + "`r`n#UPD_END#`r`n#QMDATA#`r`n" + $b64 + "`r`n", (New-Object Text.ASCIIEncoding))
Copy-Item $bat ([Environment]::GetFolderPath('Desktop')) -Force
Copy-Item $zip ([Environment]::GetFolderPath('Desktop')) -Force
Write-Host "built $ver"
if ($NoPublish) { return }

# publish
git add -A
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  $msg = "Questmates $ver" + $(if ($Notes) { "`n`n$Notes" } else { '' }) + "`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  git commit -q -m $msg
}
git tag "v$ver"
git push -q origin HEAD --tags
$relNotes = $(if ($Notes) { $Notes } else { "Questmates $ver" }) + "`n`nNew players: download **Install Questmates.bat** below and double-click it - it installs Questmates and keeps it up to date automatically."
gh release create "v$ver" $zip $bat --title "Questmates $ver" --notes $relNotes
Write-Host "released v$ver"
