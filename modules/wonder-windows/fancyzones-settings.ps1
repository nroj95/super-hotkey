#requires -Version 5.1
<#
.SYNOPSIS
    Reads or applies the narrowly scoped Win Key Overhaul / FancyZones setup.
.DESCRIPTION
    Internal helper invoked by fancyzones.ahk. Apply changes only the three
    navigation toggles and two zone-window shortcuts. An atomic replacement keeps
    an exact, timestamped backup. No layouts or unrelated settings are changed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Read', 'Apply')]
    [string] $Mode,

    [Parameter(Mandatory)]
    [string] $SettingsPath,

    [Parameter(Mandatory)]
    [string] $ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$temporaryPath = $null
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false

try {
    $originalText = [System.IO.File]::ReadAllText($SettingsPath)
    $settings = $originalText | ConvertFrom-Json
    $properties = $settings.properties
    $requiredNames = @(
        'fancyzones_overrideSnapHotkeys',
        'fancyzones_moveWindowsBasedOnPosition',
        'fancyzones_windowSwitching',
        'fancyzones_prevTab_hotkey',
        'fancyzones_nextTab_hotkey'
    )

    # Refuse unfamiliar or incomplete schemas instead of overwriting guessed data.
    foreach ($propertyName in $requiredNames) {
        if ($null -eq $properties.PSObject.Properties[$propertyName] -or
            $null -eq $properties.$propertyName.PSObject.Properties['value']) {
            throw "Unsupported FancyZones setting: $propertyName"
        }
    }
    foreach ($hotkeyName in @('fancyzones_prevTab_hotkey', 'fancyzones_nextTab_hotkey')) {
        foreach ($fieldName in @('win', 'ctrl', 'alt', 'shift', 'code')) {
            if ($null -eq $properties.$hotkeyName.value.PSObject.Properties[$fieldName]) {
                throw "Incomplete FancyZones shortcut: $hotkeyName.$fieldName"
            }
        }
    }

    # Presence alone is not enough: [bool] 'false' is true in PowerShell.
    # Reject unfamiliar value types rather than declaring that integration ready.
    foreach ($propertyName in $requiredNames[0..2]) {
        if ($properties.$propertyName.value -isnot [bool]) {
            throw "Unsupported FancyZones boolean: $propertyName"
        }
    }
    foreach ($hotkeyName in @('fancyzones_prevTab_hotkey', 'fancyzones_nextTab_hotkey')) {
        $hotkey = $properties.$hotkeyName.value
        foreach ($fieldName in @('win', 'ctrl', 'alt', 'shift')) {
            if ($hotkey.$fieldName -isnot [bool]) {
                throw "Unsupported FancyZones shortcut boolean: $hotkeyName.$fieldName"
            }
        }
        $code = $hotkey.code
        if (($code -isnot [int] -and $code -isnot [long]) -or $code -lt 0 -or $code -gt 255) {
            throw "Unsupported FancyZones virtual-key code: $hotkeyName.code"
        }
    }

    $backupPath = ''
    if ($Mode -eq 'Apply') {
        $properties.fancyzones_overrideSnapHotkeys.value = $true
        $properties.fancyzones_windowSwitching.value = $true

        $previous = $properties.fancyzones_prevTab_hotkey.value
        $next = $properties.fancyzones_nextTab_hotkey.value
        foreach ($hotkey in @($previous, $next)) {
            $hotkey.win = $false
            $hotkey.ctrl = $true
            $hotkey.alt = $true
            $hotkey.shift = $false
        }
        $previous.code = 33 # VK_PRIOR: Ctrl+Alt+PgUp
        $next.code = 34     # VK_NEXT: Ctrl+Alt+PgDn

        $updatedText = $settings | ConvertTo-Json -Depth 100
        $uniqueSuffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $backupPath = '{0}.win-key-overhaul-{1}-{2}.bak' -f (
            $SettingsPath, (Get-Date -Format 'yyyyMMdd-HHmmss'), $uniqueSuffix
        )
        $temporaryPath = "$SettingsPath.win-key-overhaul-$uniqueSuffix.tmp"
        [System.IO.File]::WriteAllText($temporaryPath, $updatedText, $utf8)

        # PowerToys may be writing its own settings. Do not knowingly replace a
        # newer version with the snapshot read above; leave it for a later retry.
        if ([System.IO.File]::ReadAllText($SettingsPath) -cne $originalText) {
            throw 'FancyZones settings changed during setup. Close PowerToys Settings and retry.'
        }
        [System.IO.File]::Replace($temporaryPath, $SettingsPath, $backupPath, $true)
        $temporaryPath = $null
    }

    $previous = $properties.fancyzones_prevTab_hotkey.value
    $next = $properties.fancyzones_nextTab_hotkey.value
    $fields = @(
        [int][bool] $properties.fancyzones_overrideSnapHotkeys.value,
        [int][bool] $properties.fancyzones_moveWindowsBasedOnPosition.value,
        [int][bool] $properties.fancyzones_windowSwitching.value,
        [int][bool] $previous.win, [int][bool] $previous.ctrl,
        [int][bool] $previous.alt, [int][bool] $previous.shift, [int] $previous.code,
        [int][bool] $next.win, [int][bool] $next.ctrl,
        [int][bool] $next.alt, [int][bool] $next.shift, [int] $next.code
    )
    [System.IO.File]::WriteAllText($ResultPath, (($fields -join ',') + "`n" + $backupPath), $utf8)
    exit 0
}
catch {
    [System.IO.File]::WriteAllText($ResultPath, ('ERROR: ' + $_.Exception.Message), $utf8)
    exit 1
}
finally {
    if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}
