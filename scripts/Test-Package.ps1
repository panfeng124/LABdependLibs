#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$InputDirectory, [string]$CMakePath)
. (Join-Path $PSScriptRoot 'Build.Common.ps1')
$root = Split-Path -Parent $PSScriptRoot
$inputRoot = (Resolve-Path -LiteralPath $InputDirectory).Path
$library = Get-ChildItem -LiteralPath $inputRoot -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'build-info.json') } | Select-Object -First 1
if (-not $library) { throw 'No built libraries in this package.' }
$info = Get-Content -LiteralPath (Join-Path $library.FullName 'build-info.json') -Raw | ConvertFrom-Json
$toolchain = Get-WindowsToolchain $info.toolchain.Year $CMakePath
$work = Join-Path $root ('.build/smoke-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$log = Join-Path $work 'smoke.log'
[IO.File]::WriteAllText($log, '')
Invoke-Logged $toolchain.CMake @('-S',(Join-Path $root 'tests/smoke'),'-B',$work,'-G',$toolchain.Generator,'-A','x64',"-DCMAKE_GENERATOR_INSTANCE=$($toolchain.Instance)",('-DLABDeps_DIR=' + $inputRoot.Replace('\','/'))) $log
Invoke-Logged $toolchain.CMake @('--build',$work,'--config',$info.configuration,'--parallel','4') $log
$ctest = Join-Path (Split-Path -Parent $toolchain.CMake) 'ctest.exe'
Invoke-Logged $ctest @('--test-dir',$work,'-C',$info.configuration,'--output-on-failure') $log
Get-Content -LiteralPath $log -Tail 8 | Write-Host
Write-Host "Consumer smoke test passed. Log: $log"
