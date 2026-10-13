#Requires -Version 7.0
<#
.SYNOPSIS
    verifies or updates Power Hotkey's pinned AutoHotkey libraries.
.DESCRIPTION
    reads immutable GitHub commit snapshots; does not change the source repos.
    default is offline verification. -Update downloads and replaces only mismatches.
#>
[CmdletBinding()]
param([switch] $Update)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$dependencies = @(
    @{
        Name = 'Keybindings'
        Repository = 'nroj95/keybindings'
        Commit = '42261fa924c74ccd0c5887ff3408c03cbcc6c0d0'
        Source = 'lib/keybindings.ahk'
        Target = 'lib/keybindings.ahk'
        Sha256 = 'FF7C4C5AB6C3A3355CBFBCA14FF043D492AFE01F35ABF81E636C8018E5875CB2'
    }
    @{
        Name = 'Keybindings icon'
        Repository = 'nroj95/keybindings'
        Commit = '42261fa924c74ccd0c5887ff3408c03cbcc6c0d0'
        Source = 'icons/keybindings.ico'
        Target = 'icons/keybindings.ico'
        Sha256 = 'B7AAB409F49DA17E2189EAA3E9F115AFE0A96DB197D383406E948477BFD0128F'
    }
    @{
        Name = 'Keybindings attribution'
        Repository = 'nroj95/keybindings'
        Commit = '42261fa924c74ccd0c5887ff3408c03cbcc6c0d0'
        Source = 'icons/ATTRIBUTION.md'
        Target = 'icons/keybindings-ATTRIBUTION.md'
        Sha256 = '9D3CA0A4A7AAD2977B9DB85CF582D2E439211185C6F89D07C0586EFB8146486E'
    }
    @{
        Name = 'Caps + Pause client'
        Repository = 'nroj95/caps-pause-layers'
        Commit = 'f674ff57543b8ddbadac49b43d7248c89581c003'
        Source = 'lib/caps-pause-client.ahk'
        Target = 'lib/caps-pause-client.ahk'
        Sha256 = '80b8114c656e89ac07df84c0e0f4bb874b6d83ed0d0d89b58ea6ccd5d53f350c'
    }
)

$pending = @()
$outdated = @()

try {
    foreach ($dependency in $dependencies) {
        $destination = Join-Path $repositoryRoot $dependency.Target
        $currentHash = if (Test-Path -LiteralPath $destination -PathType Leaf) {
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        } else {
            ''
        }

        if ($currentHash -eq $dependency.Sha256) {
            Write-Host "OK: $($dependency.Name) matches $($dependency.Commit.Substring(0, 7))"
            continue
        }

        if (-not $Update) {
            $outdated += $dependency.Name
            Write-Warning "$($dependency.Name) is missing or differs from the pinned revision."
            continue
        }

        $targetDirectory = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        $temporary = Join-Path $targetDirectory ('.' + [IO.Path]::GetFileName($destination) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
        $pending += [pscustomobject]@{ Temporary = $temporary; Destination = $destination; Name = $dependency.Name }

        $url = "https://raw.githubusercontent.com/$($dependency.Repository)/$($dependency.Commit)/$($dependency.Source)"
        Invoke-WebRequest -Uri $url -OutFile $temporary -ErrorAction Stop
        $downloadHash = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
        if ($downloadHash -ne $dependency.Sha256) {
            throw "Downloaded $($dependency.Name) failed SHA256 verification; no dependencies were replaced."
        }
    }

    if (-not $Update) {
        if ($outdated.Count) {
            throw 'Dependency check failed. Review local changes, then run with -Update to restore pinned copies.'
        }
        Write-Host 'All pinned dependencies match.'
        return
    }

    # Verify all downloaded files before replacing any existing copy.
    foreach ($item in $pending) {
        [IO.File]::Move($item.Temporary, $item.Destination, $true)
        Write-Host "Updated: $($item.Name)"
    }
    Write-Host 'Dependency synchronization complete.'
}
finally {
    foreach ($item in $pending) {
        if (Test-Path -LiteralPath $item.Temporary) {
            Remove-Item -LiteralPath $item.Temporary -Force
        }
    }
}
