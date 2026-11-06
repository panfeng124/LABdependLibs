#requires -Version 5.1
[CmdletBinding()]
param(
    [string[]]$Library = @('all'),
    [ValidateSet('Release','Debug')][string]$Configuration = 'Release',
    [ValidateSet('auto','2019','2022','2026')][string]$VisualStudioVersion = 'auto',
    [ValidateRange(1,128)][int]$Jobs = [Math]::Min(8, [Environment]::ProcessorCount),
    [string]$CMakePath,
    [switch]$List,
    [switch]$Plan,
    [switch]$IncludeLibffi,
    [switch]$Package
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts/Build.Common.ps1')
$root = $PSScriptRoot
$Library = @($Library | ForEach-Object { ($_ -split ',') | ForEach-Object { $_.Trim() } })
$manifest = Get-Content -LiteralPath (Join-Path $root 'dependencies.json') -Raw | ConvertFrom-Json
if ($List) {
    $manifest.libraries | Select-Object name,source,@{n='dependencies';e={$_.dependencies -join ', '}} | Format-Table -AutoSize
    $manifest.external | Format-Table name,reason -Wrap
    return
}
$buildPlan = @(Get-BuildPlan $manifest $Library)
foreach ($entry in $buildPlan) {
    $source = Assert-ChildPath (Join-Path $root $entry.source) $root
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Missing source: $source" }
}
if ($Plan) {
    Write-Host "Configuration: $Configuration; x64; shared libraries + MSVC DLL runtime (MD/MDd)"
    Write-Host ('Build order: ' + ($buildPlan.name -join ' -> '))
    Write-Host 'Copy prebuilt/windows-x64 to the LAB result paths before compiling. FFmpeg is supplied by this SDK.'
    if ($IncludeLibffi) { Write-Host 'Also build libffi with MSYS2 + MSVC.' }
    return
}
$toolchain = Get-WindowsToolchain $VisualStudioVersion $CMakePath
if ($IncludeLibffi) { & (Join-Path $root 'scripts/Build-Libffi.ps1') -Check }
& (Join-Path $root 'scripts/Install-Prebuilt.ps1')
$profile = "windows-x64-vs$($toolchain.Year)-md"
$workRoot = Assert-ChildPath (Join-Path $root ".build/$profile/$Configuration") $root
$outputRoot = Assert-ChildPath (Join-Path $root "result/$profile/$Configuration") $root
$null = New-Item -ItemType Directory -Force -Path $workRoot,$outputRoot
# One writer per profile/configuration, including packaging.
$lock = [IO.File]::Open((Join-Path $outputRoot '.build.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    Write-Host "Toolchain: $($toolchain.Generator) / $($toolchain.CMakeVersion)"
    Write-Host "Output: $outputRoot"
    $gitCommit = (& git -C $root rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $gitCommit = 'unknown' }
    foreach ($entry in $buildPlan) {
        Write-Host "[$($entry.name)] configure -> build -> install"
        $source = Join-Path $root $entry.source
        $work = Join-Path $workRoot $entry.name
        $buildDir = Join-Path $work 'build'
        $stage = Join-Path $work 'install'
        $null = New-Item -ItemType Directory -Force -Path $work
        Remove-ManagedDirectory $stage $workRoot
        $log = Join-Path $work 'build.log'
        [IO.File]::WriteAllText($log, '')
        if ($entry.PSObject.Properties.Name -contains 'stageDirectories') {
            # Only libhv's explicit build inputs are copied, never the baseLibs tree.
            $copy = Join-Path $work 'source'
            Remove-ManagedDirectory $copy $workRoot
            $null = New-Item -ItemType Directory -Path $copy
            Get-ChildItem -LiteralPath $source -File | Copy-Item -Destination $copy
            foreach ($directory in $entry.stageDirectories) {
                Copy-Item -LiteralPath (Join-Path $source $directory) -Destination $copy -Recurse
            }
            $source = $copy
        }
        $cmakeSource = $source
        $arguments = @('-S', $cmakeSource, '-B', $buildDir, '-G', $toolchain.Generator, '-A', 'x64',
            "-DCMAKE_GENERATOR_INSTANCE=$($toolchain.Instance)", "-DCMAKE_INSTALL_PREFIX=$stage",
            "-DCMAKE_BUILD_TYPE=$Configuration", '-DBUILD_SHARED_LIBS=ON', '-DBUILD_TESTING=OFF',
            '-DCMAKE_POLICY_VERSION_MINIMUM=3.5', '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW',
            '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>DLL',
            '-DCMAKE_C_FLAGS=/FS', '-DCMAKE_CXX_FLAGS=/FS',
            '-DCMAKE_INSTALL_LIBDIR=lib', '-DCMAKE_INSTALL_BINDIR=bin', '-DCMAKE_INSTALL_INCLUDEDIR=include',
            '-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF', '-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF')
        if ($entry.PSObject.Properties.Name -contains 'adapter') {
            $arguments[1] = Join-Path $root 'cmake/adapters'
            $arguments += ('-DLAB_SOURCE:PATH=' + $source.Replace('\','/')), "-DLAB_LIBRARY=$($entry.adapter)"
        }
        $prefixes = @($buildPlan | Where-Object { $_.name -ne $entry.name } | ForEach-Object { (Join-Path $outputRoot $_.name).Replace('\','/') })
        $arguments += '-DCMAKE_PREFIX_PATH=' + ($prefixes -join ';')
        foreach ($option in $entry.options.PSObject.Properties) {
            $value = [string]$option.Value
            foreach ($dependency in $buildPlan) {
                $value = $value.Replace("{$($dependency.name)}", (Join-Path $outputRoot $dependency.name).Replace('\','/'))
            }
            $arguments += "-D$($option.Name)=$value"
        }
        Invoke-Logged $toolchain.CMake $arguments $log
        Invoke-Logged $toolchain.CMake @('--build', $buildDir, '--config', $Configuration, '--parallel', "$Jobs") $log
        Invoke-Logged $toolchain.CMake @('--install', $buildDir, '--config', $Configuration) $log
        if ($entry.name -eq 'assimp') {
            # LAB historically consumes both generated headers; upstream installs
            # config.h but omits revision.h from its public header list.
            Copy-Item -LiteralPath (Join-Path $buildDir 'include/assimp/revision.h') -Destination (Join-Path $stage 'include/assimp/revision.h')
        }
        if (-not (Test-Path -LiteralPath (Join-Path $stage 'include'))) { throw "No installed headers for $($entry.name). See $log" }
        if ($entry.name -ne 'glm' -and -not (Test-Path -LiteralPath (Join-Path $stage 'lib'))) { throw "No installed libraries for $($entry.name). See $log" }
        foreach ($license in $entry.licenses) {
            $licenseSource = Join-Path (Join-Path $root $entry.source) $license
            if (-not (Test-Path -LiteralPath $licenseSource)) { throw "Missing license: $licenseSource" }
            $licenseDestination = Join-Path $stage "licenses/$($entry.name)/$license"
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $licenseDestination)
            Copy-Item -LiteralPath $licenseSource -Destination $licenseDestination
        }
        if ($entry.name -eq 'sqlite3') {
            $null = New-Item -ItemType Directory -Force -Path (Join-Path $stage 'licenses/sqlite3')
            Get-Content -LiteralPath (Join-Path $source 'sqlite3.c') -TotalCount 30 | Set-Content -LiteralPath (Join-Path $stage 'licenses/sqlite3/source-notice.txt')
        }
        Write-JsonFile ([ordered]@{schemaVersion=1; library=$entry.name; profile=$profile; configuration=$Configuration; architecture='x64'; runtime=$(if ($Configuration -eq 'Debug') {'MDd'} else {'MD'}); source=$entry.source; repositoryCommit=$gitCommit; sourceIdentity='working tree; local source changes are not hashed'; builtAtUtc=[DateTime]::UtcNow.ToString('o'); toolchain=$toolchain; dependencies=$entry.dependencies; options=$entry.options}) (Join-Path $stage 'build-info.json')
        Publish-Library $stage (Join-Path $outputRoot $entry.name) $root
        Write-Host "[$($entry.name)] OK"
    }
    Copy-Item -LiteralPath (Join-Path $root 'cmake/LABDepsConfig.cmake') -Destination $outputRoot -Force
} finally { $lock.Dispose() }
Write-Host "Build complete: $outputRoot"
if ($IncludeLibffi) { & (Join-Path $root 'scripts/Build-Libffi.ps1') -Configuration $Configuration -VisualStudioVersion $toolchain.Year -CMakePath $toolchain.CMake -Jobs $Jobs }
elseif ($Library -contains 'all') { Write-Warning 'libffi and FFmpeg are separate from this CMake batch. See README.md.' }
if ($Package) { & (Join-Path $root 'scripts/Package.ps1') -InputDirectory $outputRoot }
