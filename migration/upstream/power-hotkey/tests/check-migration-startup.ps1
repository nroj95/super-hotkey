#Requires -Version 7.0
# Run from the Power Hotkey tests directory. NEVER touches live user settings.
[CmdletBinding()]
param([string] $AutoHotkeyPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $AutoHotkeyPath) {
    $AutoHotkeyPath = @(
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}
if (-not $AutoHotkeyPath -or -not (Test-Path -LiteralPath $AutoHotkeyPath -PathType Leaf)) {
    throw 'AutoHotkey v2 executable was not found.'
}

$script = Join-Path $PSScriptRoot 'migration-startup-check.ahk'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    throw "Migration test script not found: $script"
}
$root = Join-Path $env:TEMP ('ph-migration-startup-' + [guid]::NewGuid().ToString('N'))
$report = Join-Path $root 'report.log'
New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null

try {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $AutoHotkeyPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('/ErrorStdOut=UTF-8')
    $startInfo.ArgumentList.Add($script)
    $startInfo.ArgumentList.Add($root)
    $startInfo.ArgumentList.Add($report)

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Could not launch isolated AutoHotkey test.' }
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw 'Synthetic migration timed out after 20 seconds.'
        }
        $stdout = $outTask.GetAwaiter().GetResult().Trim()
        $stderr = $errTask.GetAwaiter().GetResult().Trim()
        if ($stdout) { Write-Host $stdout }
        if ($stderr) { Write-Host $stderr }
        if (-not (Test-Path -LiteralPath $report)) {
            throw "No report produced; AutoHotkey exit code $($process.ExitCode)."
        }
        $result = [System.IO.File]::ReadAllText($report).Trim()
        Write-Host $result
        if ($process.ExitCode -ne 0 -or $stderr -or
            $result -notmatch '\APASS: Synthetic legacy configuration migrated' -or
            $result -notmatch 'Migration marker persisted and repeat installation did nothing\.$') {
            throw 'Synthetic migration did not pass all checks.'
        }
    }
    finally {
        $process.Dispose()
    }
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
    }
}
