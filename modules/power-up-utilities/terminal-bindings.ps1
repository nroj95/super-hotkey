#requires -Version 5.1
# Read-only Windows Terminal keybinding resolver for Super Hotkey. Defaults come
# from the running release's defaults.json, so Terminal updates need no table.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $DefaultsPath,
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

# Terminal accepts comments and trailing commas, without altering quoted strings.
function Read-TerminalJson([string] $path) {
    $source = [System.IO.File]::ReadAllText($path)
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
    if ($settings -isnot [pscustomobject]) { throw "$path must be a JSON object." }
    return $settings
}

function Get-Entries($settings, [string] $name) {
    if ($null -eq $settings.PSObject.Properties[$name]) { return @() }
    return @($settings.$name | Where-Object { $null -ne $_ })
}

try {
    $tracked = @('Terminal.ClearBuffer', 'Terminal.CopyToClipboard', 'Terminal.SelectAll')
    $known = @{}    # action ID -> the tracked action it is equivalent to, or '<other>'
    $bindings = @{} # shortcut -> action; '' is an explicitly unbound shortcut

    # The running release's defaults. Their definitions are verified like custom
    # actions; shortcuts that the macros could never send are irrelevant here.
    $defaults = Read-TerminalJson $DefaultsPath
    foreach ($entry in Get-Entries $defaults 'actions') {
        if ($entry -isnot [pscustomobject] -or $null -eq $entry.PSObject.Properties['id'] -or
            $null -eq $entry.PSObject.Properties['command']) { continue }
        $resolved = Resolve-EquivalentAction $entry.command
        $known[[string] $entry.id] = if ($resolved) { $resolved } else { '<other>' }
    }
    foreach ($name in @('actions', 'keybindings')) {
        foreach ($entry in Get-Entries $defaults $name) {
            if ($entry -isnot [pscustomobject] -or $null -eq $entry.PSObject.Properties['keys']) { continue }
            $id = if ($null -ne $entry.PSObject.Properties['id']) { [string] $entry.id } else { '' }
            if ($null -ne $entry.PSObject.Properties['command']) {
                $id = Resolve-EquivalentAction $entry.command
                if (!$id) { $id = '<other>' }
            }
            elseif ($id -ne '') {
                $id = if ($known.ContainsKey($id)) { $known[$id] } else { '<other>' }
            }
            foreach ($rawKey in @($entry.keys)) {
                $key = Normalize-Shortcut ([string] $rawKey)
                if ($key) { $bindings[$key] = $id }
            }
        }
    }
    # settings.json starts with this binding from Terminal's userDefaults.json.
    $bindings['ctrl+c'] = 'Terminal.CopyToClipboard'

    $userBindings = @{}
    $userOrder = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath $SettingsPath) {
        $settings = Read-TerminalJson $SettingsPath
        if (@(Get-Entries $settings 'import').Count) {
            throw 'Imported Terminal configuration is not supported.'
        }
        $customIds = @{}
        foreach ($entry in Get-Entries $settings 'actions') {
            if ($entry -isnot [pscustomobject]) { throw 'Malformed Terminal action.' }
            if ($null -eq $entry.PSObject.Properties['id'] -or
                $null -eq $entry.PSObject.Properties['command']) { continue }
            $id = [string] $entry.id
            if ($tracked -ccontains $id) { throw "Built-in action $id was redefined." }
            if ($customIds.ContainsKey($id)) { throw "Duplicate action ID: $id." }
            $customIds[$id] = $true
            $resolved = Resolve-EquivalentAction $entry.command
            $known[$id] = if ($resolved) { $resolved } else { '<other>' }
        }
        # The later layer wins only for identical definitions; conflicting ones
        # are rejected instead of guessing Terminal's precedence.
        foreach ($name in @('actions', 'keybindings')) {
            foreach ($entry in Get-Entries $settings $name) {
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
                    if ($tracked -ccontains $id) { throw "Built-in action $id was redefined." }
                    $id = Resolve-EquivalentAction $entry.command
                    if (!$id) { $id = '<other>' }
                }
                elseif ($id -ne '') {
                    # Unknown actions shadow defaults, but aren't safe Ctrl+C/Enter.
                    $id = if ($known.ContainsKey($id)) { $known[$id] } else { '<other>' }
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
