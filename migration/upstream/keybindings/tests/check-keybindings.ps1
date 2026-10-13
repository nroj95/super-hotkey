#Requires -Version 7.0
<#
.SYNOPSIS
    runs isolated helper, persistence and ownership tests for the shared keybindings library.
.DESCRIPTION
    has no dependency on the Caps + Pause service or its client adapter.
    helper checks use an isolated temporary directory, removed on completion.
    parser/helper success is not a guarantee of physical input or IPC reliability.
.PARAMETER AutoHotkeyPath
    optional full path to the AutoHotkey v2 interpreter executable.
#>
[CmdletBinding()]
param([string] $AutoHotkeyPath)

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
    throw 'AutoHotkey v2 was not found. specify -AutoHotkeyPath with the interpreter path.'
}

$scriptPaths = @(Join-Path $PSScriptRoot 'keybindings-check.ahk')
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
        # Drain both pipes concurrently; a parser warning must not deadlock validation.
        $standardOutputTask = $validationProcess.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $validationProcess.StandardError.ReadToEndAsync()
        if (-not $validationProcess.WaitForExit(20000)) {
            $validationProcess.Kill($true)
            $validationProcess.WaitForExit()
            throw "validation timed out for $scriptPath"
        }
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult().Trim()
        $standardError = $standardErrorTask.GetAwaiter().GetResult().Trim()
        if ($standardOutput) { Write-Host $standardOutput }
        if ($standardError) { Write-Host $standardError }
        # Exact single-line PASS is required; warnings must never be treated as success.
        if ($validationProcess.ExitCode -ne 0 -or $standardError -or
            $standardOutput -notmatch '\APASS: [^\r\n]+\z') {
            throw "validation failed for $scriptPath (exit $($validationProcess.ExitCode))"
        }
    }
    finally {
        $validationProcess.Dispose()
    }
}
Write-Host 'keybinding checks passed.'
