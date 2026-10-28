Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-JsonFile($Value, [string]$Path) {
    $json = $Value | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}

function Assert-ChildPath([string]$Path, [string]$Parent) {
    $full = [IO.Path]::GetFullPath($Path)
    $boundary = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing operation outside ${Parent}: $full"
    }
    # Reject junctions/symlinks, including an ancestor such as result/.build.
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Managed paths cannot be junctions or symlinks: $cursor"
            }
        }
        $cursor = Split-Path -Parent $cursor
    }
    return $full
}

function Remove-ManagedDirectory([string]$Path, [string]$Parent) {
    $full = Assert-ChildPath $Path $Parent
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
}

function Invoke-Logged([string]$Executable, [string[]]$Arguments, [string]$Log) {
    Add-Content -LiteralPath $Log -Encoding utf8 -Value ("> $Executable " + ($Arguments -join ' '))
    # Native warnings written to stderr are log data; exit status decides success.
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Executable @Arguments 2>&1 | Out-File -LiteralPath $Log -Append -Encoding utf8
        $nativeExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($nativeExitCode -ne 0) {
        Get-Content -LiteralPath $Log -Tail 35 | Write-Host
        throw "Command failed (exit $nativeExitCode). Log: $Log"
    }
}

function Get-BuildPlan($Manifest, [string[]]$Names) {
    $entries = @{}
    foreach ($entry in $Manifest.libraries) {
        if ($entries.ContainsKey($entry.name)) { throw "Duplicate library: $($entry.name)" }
        $entries[$entry.name] = $entry
    }
    if ($Names -contains 'all') {
        if ($Names.Count -ne 1) { throw "Use all by itself, or list individual libraries." }
        $Names = @($Manifest.libraries.name)
    }
    $visiting = @{}
    $visited = @{}
    $ordered = [Collections.Generic.List[object]]::new()
    function Visit-Library([string]$Name) {
        if (-not $entries.ContainsKey($Name)) { throw "Unknown library '$Name'. Use -List." }
        if ($visited.ContainsKey($Name)) { return }
        if ($visiting.ContainsKey($Name)) { throw "Dependency cycle at '$Name'." }
        $visiting[$Name] = $true
        foreach ($dependency in $entries[$Name].dependencies) { Visit-Library $dependency }
        $visiting.Remove($Name)
        $visited[$Name] = $true
        $ordered.Add($entries[$Name])
    }
    foreach ($name in $Names) { Visit-Library $name }
    return $ordered.ToArray()
}

function Get-WindowsToolchain([string]$RequestedVersion, [string]$CMakePath) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Install Visual Studio C++ Build Tools and a Windows SDK.' }
    $instanceJson = & $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json
    if ($LASTEXITCODE -ne 0) { throw 'vswhere failed.' }
    # PS 5.1 does not enumerate ConvertFrom-Json arrays the same way as PS 7.
    $instances = ConvertFrom-Json -InputObject ($instanceJson -join "`n")
    $years = @{16='2019';17='2022';18='2026'}
    $instances = @($instances | Where-Object {
        $major = ([version]$_.installationVersion).Major
        $years.ContainsKey($major) -and ($RequestedVersion -eq 'auto' -or $years[$major] -eq $RequestedVersion)
    } | Sort-Object { [version]$_.installationVersion } -Descending)
    if ($instances.Count -eq 0) { throw "No supported Visual Studio C++ installation for '$RequestedVersion'." }
    if (-not $CMakePath) {
        $onPath = Get-Command cmake.exe -ErrorAction SilentlyContinue
        if ($onPath) { $CMakePath = $onPath.Source }
        else {
            foreach ($instance in $instances) {
                $candidate = Join-Path $instance.installationPath 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
                if (Test-Path -LiteralPath $candidate) { $CMakePath = $candidate; break }
            }
        }
    }
    if (-not $CMakePath -or -not (Test-Path -LiteralPath $CMakePath)) { throw 'CMake not found. Install CMake >= 3.22 or pass -CMakePath.' }
    $caps = & $CMakePath -E capabilities | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or [version]"$($caps.version.major).$($caps.version.minor)" -lt [version]'3.22') { throw 'CMake >= 3.22 is required.' }
    foreach ($instance in $instances) {
        $major = ([version]$instance.installationVersion).Major
        $generator = "Visual Studio $major $($years[$major])"
        if ($caps.generators.name -contains $generator) {
            return [pscustomobject]@{ CMake=$CMakePath; CMakeVersion=$caps.version.string; Generator=$generator; Year=$years[$major]; Instance=$instance.installationPath; Version=$instance.installationVersion }
        }
    }
    throw 'CMake does not support the installed Visual Studio generator. Update CMake or select another -VisualStudioVersion.'
}

function Publish-Library([string]$Stage, [string]$Destination, [string]$ManagedRoot) {
    $null = Assert-ChildPath $Stage $ManagedRoot
    $null = Assert-ChildPath $Destination $ManagedRoot
    $backup = "$Destination.previous"
    if (Test-Path -LiteralPath $backup) { throw "Backup already exists; inspect it before retrying: $backup" }
    $hadPrevious = Test-Path -LiteralPath $Destination
    if ($hadPrevious) { Move-Item -LiteralPath $Destination -Destination $backup }
    try { Move-Item -LiteralPath $Stage -Destination $Destination }
    catch {
        if ($hadPrevious) { Move-Item -LiteralPath $backup -Destination $Destination }
        throw
    }
    if ($hadPrevious) { Remove-ManagedDirectory $backup $ManagedRoot }
}
