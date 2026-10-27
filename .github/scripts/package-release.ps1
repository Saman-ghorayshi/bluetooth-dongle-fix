<#
.SYNOPSIS
Packages a BTFix release: zip, SHA256SUMS.txt and the per-file hash manifest.
.DESCRIPTION
Run from a checkout of the tag to release (CI sets the working directory to
the repo root):

    powershell -File .github\scripts\package-release.ps1 -Tag v1.2.0

Produces, next to the repo root:
  - BTFix-<Tag>.zip      the runnable payload, including file-hashes.json
  - SHA256SUMS.txt       "SHA256  filename" lines for the artifacts
  - file-hashes.json     SHA256 per code file; the manifest the installer
                         verifies against and the suite checks before every
                         elevated run (also placed inside the zip)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^v[0-9]')]
    [string]$Tag
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Push-Location $repo
try {
    $zipName = "BTFix-$Tag.zip"

    # Per-file integrity manifest. The key list must stay in sync with
    # $script:BTFixIntegrityFiles in src\BTFix.psm1.
    $codeFiles = @(
        'BTFix.ps1', 'BTFix-GUI.ps1',
        'src\BTFix.psm1', 'src\BTFix.psd1', 'src\Chipsets.psm1', 'src\Findings.psm1',
        'src\Health.psm1', 'src\ProblemCodes.psm1', 'src\Superiority.psm1'
    )
    $hashes = [ordered]@{}
    foreach ($rel in $codeFiles) {
        $hashes[$rel] = (Get-FileHash -LiteralPath (Join-Path $repo $rel) -Algorithm SHA256).Hash
    }
    $manifestPath = Join-Path $repo 'file-hashes.json'
    $hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $manifestPath -Encoding utf8

    $payload = @(
        'BTFix.ps1', 'BTFix-GUI.ps1', 'BTFix-GUI.bat', 'BTFix.bat', 'Run-Fix-As-Admin.bat',
        'install.ps1', 'src', 'file-hashes.json', 'README.md', 'CHANGELOG.md', 'LICENSE'
    )
    if (Test-Path -LiteralPath $zipName) { Remove-Item -LiteralPath $zipName -Force }
    Compress-Archive -Path $payload -DestinationPath $zipName

    $lines = @()
    foreach ($artifact in @($zipName, 'file-hashes.json')) {
        $h = (Get-FileHash -LiteralPath (Join-Path $repo $artifact) -Algorithm SHA256).Hash
        $lines += ("{0}  {1}" -f $h, $artifact)
    }
    Set-Content -LiteralPath (Join-Path $repo 'SHA256SUMS.txt') -Value $lines -Encoding ascii

    Write-Host "Packaged $zipName"
    Write-Host "Wrote SHA256SUMS.txt and file-hashes.json"
} finally {
    Pop-Location
}
