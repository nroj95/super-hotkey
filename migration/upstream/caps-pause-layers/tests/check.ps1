#Requires -Version 7.0
<#
.SYNOPSIS
    checks that the preview scripts load and their pure helper assertions pass.
.DESCRIPTION
    runs each script with its own --check switch. neither script installs hooks,
    opens its interface, or connects to the layer service in this mode.
    this is not a substitute for the physical keyboard tests in the README.
.PARAMETER AutoHotkeyPath
    optional full path to an AutoHotkey v2 interpreter executable.
#>
[CmdletBinding()]
param(
    [string] $AutoHotkeyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $AutoHotkeyPath) {
    $interpreterCommand = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue
    $interpreterCandidates = @(
        if ($interpreterCommand) { $interpreterCommand.Source }
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe"
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey32.exe"
    )
    $AutoHotkeyPath = $interpreterCandidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -First 1
}

if (-not $AutoHotkeyPath -or -not (Test-Path -LiteralPath $AutoHotkeyPath -PathType Leaf)) {
    throw 'AutoHotkey v2 was not found. supply -AutoHotkeyPath with the interpreter path.'
}

$packageDirectory = Split-Path -Parent $PSScriptRoot
$scriptPaths = @(
    (Join-Path $packageDirectory 'caps-pause-layers.ahk')
    (Join-Path $PSScriptRoot 'layer-test-client.ahk')
)

foreach ($scriptPath in $scriptPaths) {
    $processSettings = [System.Diagnostics.ProcessStartInfo]::new()
    $processSettings.FileName = $AutoHotkeyPath
    $processSettings.UseShellExecute = $false
    $processSettings.CreateNoWindow = $true
    $processSettings.RedirectStandardOutput = $true
    $processSettings.RedirectStandardError = $true
    $processSettings.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $processSettings.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $processSettings.ArgumentList.Add('/ErrorStdOut=UTF-8')
    $processSettings.ArgumentList.Add($scriptPath)
    $processSettings.ArgumentList.Add('--check')

    $validationProcess = [System.Diagnostics.Process]::new()
    $validationProcess.StartInfo = $processSettings
    try {
        if (-not $validationProcess.Start()) {
            throw "could not start the interpreter for $scriptPath"
        }
        # Read both streams concurrently so neither pipe can deadlock the child.
        $standardOutputTask = $validationProcess.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $validationProcess.StandardError.ReadToEndAsync()
        if (-not $validationProcess.WaitForExit(10000)) {
            $validationProcess.Kill($true)
            $validationProcess.WaitForExit()
            throw "validation timed out for $scriptPath"
        }
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult()
        $standardError = $standardErrorTask.GetAwaiter().GetResult()
        if ($standardOutput) { Write-Host $standardOutput.TrimEnd() }
        if ($standardError) { Write-Host $standardError.TrimEnd() }
        if ($validationProcess.ExitCode -ne 0 -or $standardOutput -notmatch '^PASS:') {
            throw "validation failed for $scriptPath (exit $($validationProcess.ExitCode))"
        }
    }
    finally {
        $validationProcess.Dispose()
    }
}

Write-Host 'load/helper checks passed. continue with the manual keyboard and IPC checks.'
