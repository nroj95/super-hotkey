#Requires -Version 7.0
<#
.SYNOPSIS
    Isolated live check: a pending edit cannot be redirected to a restarted Peer.
.DESCRIPTION
    Starts one Preview Peer and Host in a unique TEMP registry. Waits for the
    Host's hidden capture window before restarting only the Peer it launched.
    Requires one manual keyboard capture and one confirmation of the GUI result.
    Never stops existing Keybindings processes or touches their saved settings.
#>
[CmdletBinding()]
param([string] $AutoHotkeyPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$demo = Join-Path $PSScriptRoot 'unified-preview.ahk'
if (-not (Test-Path -LiteralPath $demo -PathType Leaf)) {
    throw 'Missing unified-preview.ahk next to this test.'
}
if (-not $AutoHotkeyPath) {
    $AutoHotkeyPath = @(
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $AutoHotkeyPath) {
    throw 'AutoHotkey v2 not found. Supply -AutoHotkeyPath.'
}

if (-not ('KeybindingsCaptureTestNative' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class KeybindingsCaptureTestNative {
    private delegate bool EnumerateWindow(IntPtr hwnd, IntPtr param);
    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumerateWindow callback, IntPtr param);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hwnd, StringBuilder title, int length);

    public static IntPtr FindCapture(uint expectedPid) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hwnd, unused) => {
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            if (pid != expectedPid) return true;
            var title = new StringBuilder(256);
            GetWindowText(hwnd, title, title.Capacity);
            if (!title.ToString().StartsWith("nroj.Keybindings.v1.Capture.", StringComparison.Ordinal))
                return true;
            found = hwnd;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    public static string WindowTitles(uint expectedPid) {
        var titles = new StringBuilder();
        EnumWindows((hwnd, unused) => {
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            if (pid != expectedPid) return true;
            var title = new StringBuilder(256);
            GetWindowText(hwnd, title, title.Capacity);
            if (titles.Length != 0) titles.Append(" | ");
            titles.Append(title.Length != 0 ? title.ToString() : "[untitled]");
            return true;
        }, IntPtr.Zero);
        return titles.ToString();
    }
}
"@
}

function Get-BindingLine([string] $manifest) {
    $inBindings = $false
    $bindingLines = @(
        foreach ($line in [System.IO.File]::ReadAllLines($manifest)) {
            if ($line -match '^\[([^\]]+)\]$') {
                $inBindings = ($Matches[1] -eq 'bindings')
                continue
            }
            if ($inBindings -and $line.StartsWith('preview.one=')) {
                $line
            }
        }
    )
    if ($bindingLines.Count -ne 1) {
        throw "Expected exactly one preview.one entry in the bindings section of $manifest."
    }
    return $bindingLines[0]
}

$root = Join-Path $env:TEMP ('nroj-keybindings-restart-' + [guid]::NewGuid().ToString('N'))
$startedProcesses = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$peerProcess = $null
$hostProcess = $null
try {
    Write-Host "Using isolated registry: $root"
    $peerProcess = Start-Process -FilePath $AutoHotkeyPath -ArgumentList @(
        "`"$demo`"", 'peer', "`"$root`""
    ) -PassThru
    $startedProcesses.Add($peerProcess)
    Start-Sleep -Milliseconds 700
    $peerProcess.Refresh()
    if ($peerProcess.HasExited) {
        throw 'Preview Peer exited during startup.'
    }
    $manifest = Join-Path $root 'unified-preview-peer.ini'
    if (-not (Test-Path -LiteralPath $manifest)) {
        throw 'Preview Peer failed to publish its test configuration.'
    }
    $originalLine = Get-BindingLine $manifest
    if ($originalLine -ne "preview.one=1`t`t") {
        throw 'The isolated Peer did not start with an unassigned shortcut.'
    }

    $hostProcess = Start-Process -FilePath $AutoHotkeyPath -ArgumentList @(
        "`"$demo`"", 'host', "`"$root`""
    ) -PassThru
    $startedProcesses.Add($hostProcess)
    Start-Sleep -Milliseconds 600
    $hostProcess.Refresh()
    if ($hostProcess.HasExited) {
        throw 'Preview Host exited during startup.'
    }

    # Look for the actual hidden capture window in this specific Host process.
    # This avoids both a fragile reimplementation of the registry hash and
    # accidentally accepting a recorder belonging to another Preview Host.
    Write-Host "Use the window titled 'Preview Host [Restart Test]' (PID $($hostProcess.Id))."

    Write-Host ''
    Write-Host 'In Preview Host, click the primary shortcut button under Preview Peer.'
    Write-Host 'Do not press the new shortcut yet. The Peer will restart automatically.'
    Write-Host 'Waiting up to 60 seconds for the recording window...'
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    while ([KeybindingsCaptureTestNative]::FindCapture([uint32]$hostProcess.Id) -eq [IntPtr]::Zero) {
        $hostProcess.Refresh()
        if ($hostProcess.HasExited) { throw 'Preview Host exited before recording.' }
        if ($deadline.Elapsed.TotalSeconds -gt 60) {
            $windowTitles = [KeybindingsCaptureTestNative]::WindowTitles([uint32]$hostProcess.Id)
            throw "Timed out waiting for capture. Host PID $($hostProcess.Id) windows: $windowTitles. Make sure you clicked '+ add' under Preview Peer in Preview Host [Restart Test]."
        }
        Start-Sleep -Milliseconds 150
    }

    Start-Sleep -Milliseconds 650
    if ([KeybindingsCaptureTestNative]::FindCapture([uint32]$hostProcess.Id) -eq [IntPtr]::Zero) {
        throw 'Recording ended before the restart; try again.'
    }
    $peerProcess.Refresh()
    if ($peerProcess.HasExited) {
        throw 'Isolated Preview Peer already exited before restart.'
    }
    $peerProcess.Kill()
    if (-not $peerProcess.WaitForExit(5000)) {
        throw 'Could not stop the isolated Preview Peer.'
    }
    Start-Sleep -Milliseconds 300
    $newPeerProcess = Start-Process -FilePath $AutoHotkeyPath -ArgumentList @(
        "`"$demo`"", 'peer', "`"$root`""
    ) -PassThru
    $startedProcesses.Add($newPeerProcess)
    Start-Sleep -Milliseconds 650
    $newPeerProcess.Refresh()
    if ($newPeerProcess.HasExited) {
        throw 'The restarted Preview Peer exited unexpectedly.'
    }
    Write-Host 'Peer restarted. Finish the pending shortcut with Ctrl + Alt + F10.'
    try { [Console]::Beep(850, 230) } catch { }

    $deadline.Restart()
    while ([KeybindingsCaptureTestNative]::FindCapture([uint32]$hostProcess.Id) -ne [IntPtr]::Zero) {
        if ($deadline.Elapsed.TotalSeconds -gt 45) {
            throw 'Recording did not finish. Release all modifiers and try again.'
        }
        Start-Sleep -Milliseconds 150
    }
    if ((Get-BindingLine $manifest) -ne $originalLine) {
        throw 'FAIL: Restarted Peer shortcut was unexpectedly modified.'
    }
    Write-Host 'PASS: The restarted Peer retained its original unassigned shortcut.'
    $answer = Read-Host 'Did Preview Host report that the remote edit failed (rather than saving it)? [y/N]'
    if ($answer.Trim().ToLowerInvariant() -ne 'y') {
        throw 'GUI rejection was not confirmed; restart test is inconclusive.'
    }
    Write-Host 'PASS: Restarted-owner edit was rejected by the GUI and did not change saved settings.'
}
finally {
    foreach ($process in $startedProcesses) {
        try {
            $process.Refresh()
            if (-not $process.HasExited) {
                $process.Kill()
                $null = $process.WaitForExit(5000)
            }
        }
        catch { }
        finally { $process.Dispose() }
    }
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
