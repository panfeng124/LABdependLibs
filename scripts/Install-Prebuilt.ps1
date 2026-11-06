#requires -Version 5.1
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Build.Common.ps1')
$root = Split-Path -Parent $PSScriptRoot
$sdk = Join-Path $root 'prebuilt/windows-x64'
$layout = [ordered]@{
    include = 'result/libHeaders'
    lib = 'result/libs/win_MSVC/lib'
    bin = 'result/libs/win_MSVC/bin'
    licenses = 'result/libs/win_MSVC/licenses'
}

# Release and Debug builds share these paths. Serialize their SDK updates.
$work = Assert-ChildPath (Join-Path $root '.build') $root
$null = New-Item -ItemType Directory -Force -Path $work
$lockPath = Assert-ChildPath (Join-Path $work 'install-prebuilt.lock') $work
$lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
$stage = Join-Path $work ('prebuilt-' + [Guid]::NewGuid().ToString('N'))
$changes = [Collections.Generic.List[object]]::new()
$published = 0
$recoverable = $true
try {
    $null = New-Item -ItemType Directory -Path $stage
    foreach ($group in $layout.Keys) {
        $source = Assert-ChildPath (Join-Path $sdk $group) $root
        $files = @(Get-ChildItem -LiteralPath $source -File -Recurse -Force)
        if (!$files.Count) { throw "Empty SDK directory: $source" }
        foreach ($file in $files) {
            $null = Assert-ChildPath $file.FullName $source
            $relative = $file.FullName.Substring($source.Length + 1)
            $target = Assert-ChildPath (Join-Path (Join-Path $root $layout[$group]) $relative) $root
            $exists = [IO.File]::Exists($target)
            if ($exists -and (Get-Sha256 $file.FullName) -eq (Get-Sha256 $target)) { continue }
            $temp = Join-Path $stage $changes.Count.ToString()
            [IO.File]::Copy($file.FullName, $temp)
            $changes.Add(@{ Temp=$temp; Target=$target; Exists=$exists; Backup="$temp.bak" })
        }
    }
    foreach ($change in $changes) {
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $change.Target))
        if ($change.Exists) { [IO.File]::Replace($change.Temp, $change.Target, $change.Backup) }
        else { [IO.File]::Move($change.Temp, $change.Target) }
        $published++
    }
    Write-Host "Installed Windows x64 prebuilt SDK in result ($published files updated)."
} catch {
    try {
        while ($published -gt 0) {
            $published--
            $change = $changes[$published]
            if ($change.Exists) { Copy-Item -LiteralPath $change.Backup -Destination $change.Target -Force }
            else { [IO.File]::Delete($change.Target) }
        }
    } catch {
        $recoverable = $false
        throw "SDK rollback failed. Recovery files: $stage. $_"
    }
    throw
} finally {
    $lock.Dispose()
    if ($recoverable) { Remove-ManagedDirectory $stage $work }
}
