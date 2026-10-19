#requires -Version 5.1
# Read-only compatibility check for Windows Terminal shortcuts used by Super Hotkey.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TerminalVersion,
    [Parameter(Mandatory)] [string] $SettingsPath,
    [Parameter(Mandatory)] [string] $ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false

# Resolve only definitions equivalent to Terminal's built-in macro actions.
# Unknown arguments are not assumed harmless: their effects may differ.
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

try {
    # Defaults verified from Terminal's v1.22, v1.23 and v1.24 defaults.json.
    $knownVersion = $TerminalVersion -match '^1\.(22|23|24)\.'
    $defaults = @{'ctrl+shift+c' = ''; 'ctrl+shift+a' = ''; 'ctrl+shift+k' = ''}
    if ($knownVersion) {
        $defaults['ctrl+shift+c'] = 'Terminal.CopyToClipboard'
        $defaults['ctrl+shift+a'] = 'Terminal.SelectAll'
    }
    if ($TerminalVersion -match '^1\.24\.') {
        $defaults['ctrl+shift+k'] = 'Terminal.ClearBuffer'
    }
    $overrides = @{}
    $customActions = @{}
    $requiredIds = @('Terminal.ClearBuffer', 'Terminal.CopyToClipboard', 'Terminal.SelectAll')

    if (Test-Path -LiteralPath $SettingsPath) {
        $source = [System.IO.File]::ReadAllText($SettingsPath)
        # Terminal settings use JSON with comments and trailing commas.
        # Preserve quoted strings so URLs and literal comment markers survive.
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
        if ($settings -isnot [pscustomobject]) {
            throw 'Terminal settings root must be a JSON object.'
        }
        if ($null -ne $settings.PSObject.Properties['import'] -and
            @($settings.import | Where-Object { $null -ne $_ }).Count) {
            throw 'Imported Terminal configuration is not supported.'
        }
        # Build the action-ID map before evaluating keybindings; the arrays may
        # appear in any order, and UI-generated action IDs are not fixed names.
        if ($null -ne $settings.PSObject.Properties['actions']) {
            foreach ($entry in @($settings.actions)) {
                if ($null -eq $entry -or $entry -isnot [pscustomobject]) { continue }
                if ($null -eq $entry.PSObject.Properties['id'] -or
                    $null -eq $entry.PSObject.Properties['command']) { continue }
                $id = [string] $entry.id
                if ($requiredIds -ccontains $id) {
                    throw "Action $id has a custom definition."
                }
                if ($customActions.ContainsKey($id)) {
                    throw "Duplicate Terminal action definition: $id."
                }
                $customActions[$id] = Resolve-EquivalentAction $entry.command
            }
        }
        $entries = @()
        foreach ($name in @('actions', 'keybindings')) {
            if ($null -ne $settings.PSObject.Properties[$name]) {
                $entries += @($settings.$name)
            }
        }
        foreach ($entry in $entries) {
            if ($null -eq $entry) { continue }
            $id = if ($null -ne $entry.PSObject.Properties['id']) { [string] $entry.id } else { '' }
            # Inline commands are not safely resolved by their ID alone.
            if (($requiredIds -ccontains $id) -and $null -ne $entry.PSObject.Properties['command']) {
                throw "Action $id has a custom definition."
            }
            if ($null -eq $entry.PSObject.Properties['keys']) { continue }
            $keys = @($entry.keys)
            if ($keys.Count -ne 1 -or $keys[0] -isnot [string]) {
                throw 'Unsupported Terminal keybinding format.'
            }
            $parts = ([string] $keys[0]).ToLowerInvariant().Replace(' ', '').Split('+')
            $key = if ($parts.Count -eq 3 -and $parts -contains 'ctrl' -and $parts -contains 'shift') {
                @('a', 'c', 'k') | Where-Object { $parts -contains $_ } | ForEach-Object { "ctrl+shift+$_" }
            } else { '' }
            if (-not $key) {
                if ($parts -contains 'ctrl' -and $parts -contains 'shift' -and
                    ([string] $keys[0]) -match '(?i)(vk\(|sc\()') {
                    throw 'Virtual-key/scancode Terminal shortcuts require manual verification.'
                }
                continue
            }
            if ($null -ne $entry.PSObject.Properties['command']) {
                # Legacy inline commands or explicit unbinding are ambiguous here.
                $id = ''
            }
            elseif ($customActions.ContainsKey($id)) {
                $id = $customActions[$id]
            }
            if ($overrides.ContainsKey($key) -and $overrides[$key] -cne $id) {
                throw "Conflicting Terminal definitions for $key."
            }
            $overrides[$key] = $id
        }
    }

    foreach ($key in @($defaults.Keys)) {
        if ($overrides.ContainsKey($key)) { $defaults[$key] = $overrides[$key] }
    }
    $result = @('OK',
        ('CLEAR=' + [int]($defaults['ctrl+shift+k'] -ceq 'Terminal.ClearBuffer')),
        ('COPY=' + [int]($defaults['ctrl+shift+c'] -ceq 'Terminal.CopyToClipboard')),
        ('SELECT=' + [int]($defaults['ctrl+shift+a'] -ceq 'Terminal.SelectAll')))
    [System.IO.File]::WriteAllText($ResultPath, ($result -join "`n"), $utf8)
    exit 0
}
catch {
    [System.IO.File]::WriteAllText($ResultPath, ('ERROR: ' + $_.Exception.Message), $utf8)
    exit 1
}
