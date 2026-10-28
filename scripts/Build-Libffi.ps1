#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Release','Debug')][string]$Configuration = 'Release',
    [ValidateSet('auto','2019','2022','2026')][string]$VisualStudioVersion = 'auto',
    [string]$MsysRoot = 'C:\msys64',
    [string]$CMakePath,
    [ValidateRange(1,128)][int]$Jobs = 4,
    [switch]$Check
)
. (Join-Path $PSScriptRoot 'Build.Common.ps1')
$root = Split-Path -Parent $PSScriptRoot
$bash = Join-Path $MsysRoot 'usr/bin/bash.exe'
if (-not (Test-Path -LiteralPath $bash)) { throw "MSYS2 not found at $MsysRoot. Pass -MsysRoot." }
$shellScript = Join-Path $PSScriptRoot 'build-libffi.sh'
& $bash --noprofile --norc $shellScript --check
if ($LASTEXITCODE -ne 0) { throw 'MSYS2 build prerequisites missing. In MSYS2 run: pacman -S --needed autoconf-wrapper automake-wrapper libtool make tar' }
if ($Check) { return }
$toolchain = Get-WindowsToolchain $VisualStudioVersion $CMakePath
$profile = "windows-x64-vs$($toolchain.Year)-md"
$outputRoot = Assert-ChildPath (Join-Path $root "result/$profile/$Configuration") $root
$work = Assert-ChildPath (Join-Path $root ".build/$profile/$Configuration/libffi") $root
$null = New-Item -ItemType Directory -Force -Path $work,$outputRoot
$lock = [IO.File]::Open((Join-Path $outputRoot '.build.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
$savedEnvironment = @{}
try {
    $source = Join-Path $root 'baseLibs/libffi-master'
    $copy = Join-Path $work 'source'
    $build = Join-Path $work 'build'
    $stage = Join-Path $work 'install'
    foreach ($directory in @($copy,$build,$stage)) { Remove-ManagedDirectory $directory $work }
    $null = New-Item -ItemType Directory -Path $copy,$build
    Get-ChildItem -LiteralPath $source -File | Copy-Item -Destination $copy
    # Autoreconf uses these specific trees; do not copy old builds or the entire vendor root.
    foreach ($directory in @('src','include','m4','doc','man','testsuite')) {
        Copy-Item -LiteralPath (Join-Path $source $directory) -Destination $copy -Recurse
    }
    $vcvars = Join-Path $toolchain.Instance 'VC/Auxiliary/Build/vcvars64.bat'
    $environmentScript = Join-Path $work 'msvc-environment.cmd'
    [IO.File]::WriteAllText($environmentScript, "@echo off`r`ncall `"%LAB_VCVARS_PATH%`" >nul`r`nif errorlevel 1 exit /b 1`r`nset`r`n", [Text.Encoding]::ASCII)
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/d /s /c ""' + $environmentScript + '""'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.EnvironmentVariables['LAB_VCVARS_PATH'] = $vcvars
    $process = [Diagnostics.Process]::Start($startInfo)
    $environmentLines = $process.StandardOutput.ReadToEnd() -split "`r?`n"
    $process.WaitForExit()
    $environmentExitCode = $process.ExitCode
    $process.Dispose()
    if ($environmentExitCode -ne 0) { throw 'vcvars64.bat failed.' }
    foreach ($line in $environmentLines) {
        if ($line -match '^([^=]+)=(.*)$') {
            $name = $Matches[1]
            $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            [Environment]::SetEnvironmentVariable($name, $Matches[2], 'Process')
        }
    }
    $log = Join-Path $work 'build.log'
    [IO.File]::WriteAllText($log, '')
    # Bash reads scripts incrementally. Run a snapshot so editing the recipe in
    # another editor cannot change a build already in progress.
    $runScript = Join-Path $work 'run-build-libffi.sh'
    Copy-Item -LiteralPath $shellScript -Destination $runScript -Force
    Invoke-Logged $bash @('--noprofile','--norc',$runScript,$copy,$build,$stage,$Configuration,"$Jobs") $log
    foreach ($relative in @('include/ffi.h','include/ffitarget.h','lib/ffi.lib')) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage $relative))) { throw "Missing libffi output: $relative. See $log" }
    }
    if (-not ((Test-Path -LiteralPath (Join-Path $stage 'bin/ffi-8.dll')) -or (Test-Path -LiteralPath (Join-Path $stage 'bin/libffi-8.dll')))) { throw "Missing libffi DLL. See $log" }
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $stage 'licenses/libffi')
    Copy-Item -LiteralPath (Join-Path $source 'LICENSE') -Destination (Join-Path $stage 'licenses/libffi/LICENSE')
    Write-JsonFile ([ordered]@{schemaVersion=1; library='libffi'; profile=$profile; configuration=$Configuration; architecture='x64'; runtime=$(if ($Configuration -eq 'Debug') {'MDd'} else {'MD'}); source='baseLibs/libffi-master'; repositoryCommit=(& git -C $root rev-parse HEAD); sourceIdentity='working tree; local source changes are not hashed'; builtAtUtc=[DateTime]::UtcNow.ToString('o'); toolchain=$toolchain; dependencies=@(); options=@{adapter='MSYS2 autotools + MSVC msvcc.sh'}}) (Join-Path $stage 'build-info.json')
    Publish-Library $stage (Join-Path $outputRoot 'libffi') $root
    Copy-Item -LiteralPath (Join-Path $root 'cmake/LABDepsConfig.cmake') -Destination $outputRoot -Force
    Write-Host "libffi built: $outputRoot/libffi"
} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    $lock.Dispose()
}
