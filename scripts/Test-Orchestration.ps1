#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Build.Common.ps1')
$root = Split-Path -Parent $PSScriptRoot
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert $failed $Message
}
$manifest = Get-Content -LiteralPath (Join-Path $root 'dependencies.json') -Raw | ConvertFrom-Json
$plan = @(Get-BuildPlan $manifest @('harfbuzz','assimp'))
Assert (($plan.name -join ',') -eq 'zlib,libpng,brotli,freetype,harfbuzz,assimp') 'Wrong dependency order or duplicate dependency.'
Assert-Throws { Get-BuildPlan $manifest @('typo') } 'Unknown dependency must fail.'
$cyclic = '{"libraries":[{"name":"a","dependencies":["b"]},{"name":"b","dependencies":["a"]}]}' | ConvertFrom-Json
Assert-Throws { Get-BuildPlan $cyclic @('a') } 'Cycle must fail.'
Assert-Throws { Assert-ChildPath (Join-Path $root '../outside') $root } 'Parent traversal must fail.'
Assert-Throws { Assert-ChildPath $root $root } 'Managed root must not be deletable.'
Assert-Throws { Assert-ChildPath ($root + '-other/file') $root } 'Sibling prefix must not pass containment.'
$workspace = Join-Path $root ('.build/orchestration-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $workspace
try {
    $old = Join-Path $workspace 'library'
    $new = Join-Path $workspace 'staging'
    $null = New-Item -ItemType Directory -Path $old,$new
    Set-Content -LiteralPath (Join-Path $old 'stale.txt') -Value 'old'
    Set-Content -LiteralPath (Join-Path $new 'current.txt') -Value 'new'
    Publish-Library $new $old $workspace
    Assert (Test-Path -LiteralPath (Join-Path $old 'current.txt')) 'Publish failed.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $old 'stale.txt'))) 'Publish kept stale files.'
    Assert-Throws { Publish-Library (Join-Path $workspace 'missing') $old $workspace } 'Missing stage must fail.'
    Assert (Test-Path -LiteralPath (Join-Path $old 'current.txt')) 'Failed publish did not restore previous output.'
    # The importer must reject a corrupt download before creating a destination.
    $fakeArchive = Join-Path $workspace 'corrupt.zip'
    Set-Content -LiteralPath $fakeArchive -Value 'not a zip'
    $rejected = Join-Path $workspace 'rejected'
    Assert-Throws { & (Join-Path $PSScriptRoot 'Import-Package.ps1') -Archive $fakeArchive -Destination $rejected -ExpectedSha256 ('0' * 64) } 'Corrupt archive must fail.'
    Assert (-not (Test-Path -LiteralPath $rejected)) 'Hash failure created a destination.'
    # Even an archive with a matching outer checksum cannot escape its destination.
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $unsafeArchive = Join-Path $workspace 'unsafe.zip'
    $archive = [IO.Compression.ZipFile]::Open($unsafeArchive, [IO.Compression.ZipArchiveMode]::Create)
    try { $null = $archive.CreateEntry('../escaped.txt') } finally { $archive.Dispose() }
    Assert-Throws { & (Join-Path $PSScriptRoot 'Import-Package.ps1') -Archive $unsafeArchive -Destination $rejected -ExpectedSha256 (Get-Sha256 $unsafeArchive) } 'Zip path traversal must fail.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $workspace 'escaped.txt'))) 'Zip escaped its destination.'
} finally { Remove-ManagedDirectory $workspace (Join-Path $root '.build') }
Write-Host 'Orchestration checks passed.'
