#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Archive,
    [Parameter(Mandatory=$true)][string]$Destination,
    [string]$ExpectedSha256
)
. (Join-Path $PSScriptRoot 'Build.Common.ps1')
$archivePath = (Resolve-Path -LiteralPath $Archive).Path
$destinationPath = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $destinationPath) { throw "Destination must be new: $destinationPath" }
$parent = Split-Path -Parent $destinationPath
$null = Assert-ChildPath $destinationPath $parent
if (-not $ExpectedSha256) {
    if (-not (Test-Path -LiteralPath "$archivePath.sha256")) { throw 'Supply -ExpectedSha256 or copy the .zip.sha256 file alongside the archive.' }
    $ExpectedSha256 = ((Get-Content -LiteralPath "$archivePath.sha256" -Raw).Trim() -split '\s+')[0]
}
if ($ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid SHA256 value.' }
if ((Get-Sha256 $archivePath) -ne $ExpectedSha256) { throw 'Archive SHA256 mismatch.' }
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $entryNames = @{}
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName -match '[:\\]' -or [IO.Path]::IsPathRooted($entry.FullName)) { throw "Unsafe archive path: $($entry.FullName)" }
        $target = Assert-ChildPath (Join-Path $destinationPath $entry.FullName) $destinationPath
        if ($entryNames.ContainsKey($target)) { throw "Duplicate archive path: $($entry.FullName)" }
        $entryNames[$target] = $true
    }
} finally { $zip.Dispose() }
try {
    [IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $destinationPath)
    $manifest = Get-Content -LiteralPath (Join-Path $destinationPath 'package-manifest.json') -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1) { throw 'Unsupported package manifest.' }
    $expectedPaths = @{}
    foreach ($record in $manifest.files) {
        $path = Assert-ChildPath (Join-Path $destinationPath $record.path) $destinationPath
        if ($expectedPaths.ContainsKey($path)) { throw "Duplicate manifest entry: $($record.path)" }
        $expectedPaths[$path] = $true
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $($record.path)" }
        if ((Get-Item -LiteralPath $path).Length -ne $record.bytes -or (Get-Sha256 $path) -ne $record.sha256) {
            throw "File integrity check failed: $($record.path)"
        }
    }
    $actual = @(Get-ChildItem -LiteralPath $destinationPath -Recurse -File | Where-Object { $_.FullName -ne (Join-Path $destinationPath 'package-manifest.json') })
    if ($actual.Count -ne $expectedPaths.Count) { throw 'Archive contains unlisted files.' }
    Write-Host "Verified $($actual.Count) files. Installed at: $destinationPath"
    Write-Host $manifest.note
} catch {
    Remove-ManagedDirectory $destinationPath $parent
    throw
}
