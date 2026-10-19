#requires -Version 5.1
# Read-only Windows Terminal keybinding resolver for Super Hotkey.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TerminalVersion,
    [Parameter(Mandatory)] [string] $SettingsPath,
    [Parameter(Mandatory)] [string] $ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false

# Only native-equivalent commands may be used by the macros.
function Resolve-EquivalentAction($command) {
    if ($command -is [string]) {
        switch -CaseSensitive ($command) {
            'copy' { return 'Terminal.CopyToClipboard' }
            'selectAll' { return 'Terminal.SelectAll' }
        }
        return ''
    }
    if ($command -isnot [pscustomobject]) { return '' }
    $fields = @($command.PSObject.Properties.Name)
    if ($fields -cnotcontains 'action') { return '' }
    switch -CaseSensitive ([string]$command.action) {
        'clearBuffer' {
            if ($fields.Count -eq 2 -and $fields -ccontains 'clear' -and $command.clear -ceq 'all') {
                return 'Terminal.ClearBuffer'
            }
        }
        'copy' {
            if ($fields.Count -eq 2 -and $fields -ccontains 'singleLine' -and
                $command.singleLine -is [bool] -and -not $command.singleLine) {
                return 'Terminal.CopyToClipboard'
            }
        }
        'selectAll' {
            if ($fields.Count -eq 1) { return 'Terminal.SelectAll' }
        }
    }
    return ''
}

function Normalize-Shortcut([string] $shortcut) {
    $parts = @($shortcut.ToLowerInvariant().Replace(' ', '').Split('+'))
    if ($parts.Count -lt 1 -or $parts.Count -gt 4 -or $parts -contains '') { return '' }
    $key = $parts[-1]
    if ($key -notmatch '^(?:[a-z0-9]|f(?:[1-9]|1[0-9]|2[0-4])|enter)$') { return '' }
    $modifiers = @()
    if ($parts.Count -gt 1) { $modifiers = @($parts[0..($parts.Count - 2)]) }
    if (@($modifiers | Where-Object { $_ -cnotin @('ctrl', 'alt', 'shift') }).Count -gt 0) {
        return ''
    }
    if (@($modifiers | Select-Object -Unique).Count -ne $modifiers.Count) { return '' }
    $canonical = @('ctrl', 'alt', 'shift') | Where-Object { $modifiers -contains $_ }
    return (@($canonical) + @($key)) -join '+'
}

function Convert-ToSend([string] $shortcut) {
    $parts = $shortcut.Split('+')
    $key = $parts[-1]
    if ($key -eq 'enter') { return '' } # Never dispatch Enter as an action shortcut.
    $modifiers = @()
    if ($parts.Count -gt 1) { $modifiers = @($parts[0..($parts.Count - 2)]) }
    if ($modifiers.Count -eq 0) { return '' } # No unmodified text keys.
    $prefix = ''
    if ($modifiers -contains 'ctrl') { $prefix += '^' }
    if ($modifiers -contains 'alt') { $prefix += '!' }
    if ($modifiers -contains 'shift') { $prefix += '+' }
    if ($key -match '^f\d+$') { return $prefix + '{' + $key.ToUpperInvariant() + '}' }
    return $prefix + $key
}

try {
    # Defaults established from Terminal v1.22-1.24. Unknown releases fail closed.
    if ($TerminalVersion -notmatch '^1\.(22|23|24)\.\d+\.\d+$') {
        throw "Unsupported Windows Terminal version: $TerminalVersion."
    }
    $bindings = @{
        'ctrl+shift+c' = 'Terminal.CopyToClipboard'
        'ctrl+shift+a' = 'Terminal.SelectAll'
        'ctrl+c' = 'Terminal.CopyToClipboard' # userDefaults.json in these releases
        'enter' = 'Terminal.CopyToClipboard'
    }
    if ($TerminalVersion -match '^1\.24\.') {
        $bindings['ctrl+shift+k'] = 'Terminal.ClearBuffer'
    }
    $builtinIds = @('Terminal.ClearBuffer', 'Terminal.CopyToClipboard', 'Terminal.SelectAll')
    $customActions = @{}
    $userBindings = @{}
    $userOrder = New-Object 'System.Collections.Generic.List[string]'

    if (Test-Path -LiteralPath $SettingsPath) {
        $source = [System.IO.File]::ReadAllText($SettingsPath)
        # Terminal accepts comments and trailing commas, without altering quoted strings.
        $source = [regex]::Replace($source, '(?s)"(?:\\.|[^"\\])*"|//[^\r\n]*|/\*.*?\*/',
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($match)
                if ($match.Value.StartsWith('"')) { return $match.Value }
                return ''
            })
        $source = [regex]::Replace($source, '"(?:\\.|[^"\\])*"|,\s*(?=[}\]])',
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($match)
                if ($match.Value.StartsWith('"')) { return $match.Value }
                return $match.Value.Substring(1)
            })
        $settings = $source | ConvertFrom-Json
        if ($settings -isnot [pscustomobject]) { throw 'Terminal settings must be a JSON object.' }
        if ($null -ne $settings.PSObject.Properties['import'] -and
            @($settings.import | Where-Object { $null -ne $_ }).Count) {
            throw 'Imported Terminal configuration is not supported.'
        }

        if ($null -ne $settings.PSObject.Properties['actions']) {
            foreach ($entry in @($settings.actions)) {
                if ($null -eq $entry) { continue }
                if ($entry -isnot [pscustomobject]) { throw 'Malformed Terminal action.' }
                if ($null -eq $entry.PSObject.Properties['id'] -or
                    $null -eq $entry.PSObject.Properties['command']) { continue }
                $id = [string] $entry.id
                if ($builtinIds -ccontains $id) { throw "Built-in action $id was redefined." }
                if ($customActions.ContainsKey($id)) { throw "Duplicate action ID: $id." }
                $resolved = Resolve-EquivalentAction $entry.command
                $customActions[$id] = $resolved
                if (!$resolved) { $customActions[$id] = '<other>' }
            }
        }
        # The later layer wins only for identical definitions; conflicting ones
        # are rejected instead of guessing Terminal's precedence.
        foreach ($name in @('actions', 'keybindings')) {
            if ($null -eq $settings.PSObject.Properties[$name]) { continue }
            foreach ($entry in @($settings.$name)) {
                if ($null -eq $entry) { continue }
                if ($entry -isnot [pscustomobject]) { throw 'Malformed Terminal keybinding.' }
                if ($null -eq $entry.PSObject.Properties['keys']) { continue }
                $keys = @($entry.keys)
                if ($keys.Count -ne 1 -or $keys[0] -isnot [string]) {
                    throw 'Unsupported Terminal keybinding format.'
                }
                $rawKey = [string] $keys[0]
                if ($rawKey -match '(?i)(vk\(|sc\()') {
                    throw 'Terminal scan-code and virtual-key bindings cannot be verified.'
                }
                $key = Normalize-Shortcut $rawKey
                if (!$key) { continue }
                $id = if ($null -ne $entry.PSObject.Properties['id']) { [string]$entry.id } else { '' }
                if ($null -ne $entry.PSObject.Properties['command']) {
                    if ($builtinIds -ccontains $id) { throw "Built-in action $id was redefined." }
                    $id = Resolve-EquivalentAction $entry.command
                    if (!$id) { $id = '<other>' }
                }
                elseif ($customActions.ContainsKey($id)) {
                    $id = $customActions[$id]
                }
                elseif ($id -ne '' -and $builtinIds -cnotcontains $id) {
                    $id = '<other>' # Unknown actions shadow defaults, but aren't safe Ctrl+C/Enter.
                }
                if ($userBindings.ContainsKey($key) -and $userBindings[$key] -cne $id) {
                    throw "Conflicting Terminal definitions for $key."
                }
                if (!$userBindings.ContainsKey($key)) { $userOrder.Add($key) }
                $userBindings[$key] = $id
            }
        }
    }
    foreach ($key in $userOrder) { $bindings[$key] = $userBindings[$key] }

    # Prefer familiar defaults, then explicit custom chords in user order.
    $preferred = @{
        CLEAR  = @('ctrl+shift+k')
        COPY   = @('ctrl+shift+c')
        SELECT = @('ctrl+shift+a')
    }
    $actions = @{
        CLEAR  = 'Terminal.ClearBuffer'
        COPY   = 'Terminal.CopyToClipboard'
        SELECT = 'Terminal.SelectAll'
    }
    $result = New-Object 'System.Collections.Generic.List[string]'
    $result.Add('OK')
    foreach ($name in @('CLEAR', 'COPY', 'SELECT')) {
        # Ctrl+C is a fallback, not a reason to ignore customized copy keys.
        $candidates = @($preferred[$name]) + @($userOrder | Where-Object { $_ -ne 'ctrl+c' })
        if ($name -eq 'COPY') { $candidates += 'ctrl+c' }
        $chosen = ''
        foreach ($key in $candidates) {
            if ($bindings.ContainsKey($key) -and $bindings[$key] -ceq $actions[$name]) {
                $send = Convert-ToSend $key
                if ($send) { $chosen = $send; break }
            }
        }
        $result.Add("$name=$chosen")
    }
    # Clear also sends Ctrl+C and Enter. Block the macro if either has been
    # remapped to an unrelated Terminal action, which could trigger side effects.
    $ctrlC = if ($bindings.ContainsKey('ctrl+c')) { $bindings['ctrl+c'] } else { '' }
    $enter = if ($bindings.ContainsKey('enter')) { $bindings['enter'] } else { '' }
    $safeSteps = ($ctrlC -ceq '' -or $ctrlC -ceq 'Terminal.CopyToClipboard') -and
        ($enter -ceq '' -or $enter -ceq 'Terminal.CopyToClipboard')
    $result.Add('SAFE_CLEAR_STEPS=' + [int] $safeSteps)
    [System.IO.File]::WriteAllText($ResultPath, ($result -join "`n"), $utf8)
    exit 0
}
catch {
    [System.IO.File]::WriteAllText($ResultPath, ('ERROR: ' + $_.Exception.Message), $utf8)
    exit 1
}
