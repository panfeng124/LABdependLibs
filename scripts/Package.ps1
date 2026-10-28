#requires -Version 5.1
[CmdletBinding()]
param([string]$InputDirectory, [switch]$Legacy)
. (Join-Path $PSScriptRoot 'Build.Common.ps1')
$root = Split-Path -Parent $PSScriptRoot
if ($Legacy -and $InputDirectory) { throw 'Choose -Legacy or -InputDirectory, not both.' }
if (-not $Legacy -and -not $InputDirectory) { throw 'Pass the result profile/configuration directory as -InputDirectory, or use -Legacy.' }
$lock = $null
$zip = $null
$archivePath = $null
try {
    $sources = @()
    if ($Legacy) {
        $inputRoot = Join-Path $root 'result'
        foreach ($relative in @('libHeaders','libs/win_MSVC')) {
            $path = Assert-ChildPath (Join-Path $inputRoot $relative) $inputRoot
            if (-not (Test-Path -LiteralPath $path)) { throw "Missing legacy outputs: $path" }
            $sources += Get-Item -LiteralPath $path
        }
        $label = 'legacy-windows-unverified'
    } else {
        $inputRoot = Assert-ChildPath $InputDirectory (Join-Path $root 'result')
        if (-not (Test-Path -LiteralPath $inputRoot)) { throw "Missing output: $inputRoot" }
        $lock = [IO.File]::Open((Join-Path $inputRoot '.build.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
        $sources = @(Get-ChildItem -LiteralPath $inputRoot -Directory)
        if (-not $sources.Count) { throw 'No built libraries to package.' }
        foreach ($source in $sources) {
            if (-not (Test-Path -LiteralPath (Join-Path $source.FullName 'build-info.json'))) { throw "Not a completed library: $($source.FullName)" }
        }
        $label = (Split-Path -Leaf (Split-Path -Parent $inputRoot)) + '-' + (Split-Path -Leaf $inputRoot)
    }
    $files = [Collections.Generic.List[object]]::new()
    foreach ($source in $sources) {
        # This recursion is limited to selected output trees, never vendored sources.
        $null = Assert-ChildPath $source.FullName $inputRoot
        foreach ($item in Get-ChildItem -LiteralPath $source.FullName -Recurse -Force) {
            $null = Assert-ChildPath $item.FullName $inputRoot
            if (-not $item.PSIsContainer) { $files.Add($item) }
        }
    }
    if (-not $Legacy) {
        $configPath = Join-Path $inputRoot 'LABDepsConfig.cmake'
        if (-not (Test-Path -LiteralPath $configPath)) { throw 'Missing LABDepsConfig.cmake. Run build.ps1 again to refresh the package entrypoint.' }
        $files.Add((Get-Item -LiteralPath $configPath))
    }
    if (-not $files.Count) { throw 'The selected outputs are empty.' }
    $packageRoot = Assert-ChildPath (Join-Path $root 'packages') $root
    $null = New-Item -ItemType Directory -Force -Path $packageRoot
    $archivePath = Join-Path $packageRoot ("LABdeps-$label-" + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.zip')
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
    $records = @()
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($inputRoot.TrimEnd('\','/').Length + 1).Replace('\','/')
        $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relative, [IO.Compression.CompressionLevel]::Optimal)
        $records += [ordered]@{path=$relative; bytes=$file.Length; sha256=(Get-Sha256 $file.FullName)}
    }
    $metadata = [ordered]@{schemaVersion=1; kind=$(if ($Legacy) {'legacy-snapshot'} else {'built-libraries'}); label=$label; createdAtUtc=[DateTime]::UtcNow.ToString('o'); libraries=@($sources.Name); note=$(if ($Legacy) {'Original hand-built outputs. Compiler, architecture, runtime and completeness are not verified.'} else {'Contains the listed completed libraries, including libffi only if it was built separately. Does not pull in FFmpeg or headers from the legacy output tree. Use LABDepsConfig.cmake for relocatable LAB:: targets; upstream CMake/pkg-config files may contain producer paths.'}); files=$records}
    $manifestEntry = $zip.CreateEntry('package-manifest.json')
    $writer = [IO.StreamWriter]::new($manifestEntry.Open(), [Text.UTF8Encoding]::new($false))
    try { $writer.Write(($metadata | ConvertTo-Json -Depth 12)) } finally { $writer.Dispose() }
    $zip.Dispose(); $zip = $null
    $hash = Get-Sha256 $archivePath
    [IO.File]::WriteAllText("$archivePath.sha256", "$hash  $([IO.Path]::GetFileName($archivePath))`n")
    Write-Host "Package: $archivePath"
    Write-Host "SHA256:  $hash"
    return $archivePath
} catch {
    if ($zip) { $zip.Dispose(); $zip = $null }
    if ($archivePath -and (Test-Path -LiteralPath $archivePath)) { Remove-Item -LiteralPath $archivePath -Force }
    throw
} finally {
    if ($zip) { $zip.Dispose() }
    if ($lock) { $lock.Dispose() }
}
