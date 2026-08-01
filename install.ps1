# Clones this repository and links the WezTerm and Neovim configs into place.
#
# Run it directly, or through the one-liner in the README, which pipes the file
# straight into Invoke-Expression before the repository exists on disk. That is
# why there is no param block and no #Requires here: both are legal only in a
# script that is being run as a file, and piped text is not one.
#
# Set DOTFILES_DRY_RUN=1 to see what it would do without doing it.
#
# It links configuration only. Installing WezTerm, Neovim and the rest is a
# separate installer, still to be built.

$ErrorActionPreference = 'Stop'
$DryRun = $env:DOTFILES_DRY_RUN -eq '1'

$RepoUrl  = 'https://github.com/arthurpessoa/dotfiles'
$RepoRoot = Join-Path $HOME '.dotfiles'

function Write-Step { param([string] $Message) Write-Host $Message }

# Junctions, not symlinks: they need neither administrator rights nor Developer
# Mode, and they work for directories, which is all this links.
function New-ConfigLink {
    param(
        [Parameter(Mandatory)] [string] $Target,
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Stamp,
        [switch] $DryRun
    )

    $existing = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue

    if ($existing -and $existing.LinkType -in 'Junction', 'SymbolicLink') {
        $points = @($existing.Target)[0]
        if ($points -and (Resolve-Path -LiteralPath $points).Path -eq (Resolve-Path -LiteralPath $Source).Path) {
            return @{ Action = 'already-linked'; Backup = $null }
        }
    }

    $backup = $null
    if ($existing) {
        # Never delete a config that is already there. Rename it and say where
        # it went, so a mistake is always recoverable.
        $backup = "$Target.bak-$Stamp"
        if (-not $DryRun) { Move-Item -LiteralPath $Target -Destination $backup }
    }

    $parent = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $parent)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    }

    if (-not $DryRun) {
        New-Item -ItemType Junction -Path $Target -Target $Source | Out-Null
    }

    return @{ Action = if ($backup) { 'backed-up-and-linked' } else { 'linked' }; Backup = $backup }
}

function Get-LinkTargets {
    param([Parameter(Mandatory)] [string] $Root)
    return @(
        @{ Target = Join-Path $HOME '.config/wezterm'; Source = Join-Path $Root 'wezterm' }
        @{ Target = Join-Path $env:LOCALAPPDATA 'nvim'; Source = Join-Path $Root 'nvim' }
    )
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is required and was not found on PATH'
}

if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git')) {
    Write-Step "updating $RepoRoot"
    if (-not $DryRun) { git -C $RepoRoot pull --ff-only }
} else {
    Write-Step "cloning $RepoUrl into $RepoRoot"
    if (-not $DryRun) { git clone $RepoUrl $RepoRoot }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

foreach ($pair in Get-LinkTargets $RepoRoot) {
    $result = New-ConfigLink $pair.Target $pair.Source $stamp -DryRun:$DryRun
    Write-Step ('{0,-42} {1}' -f $pair.Target, $result.Action)
    if ($result.Backup) { Write-Step "  previous config kept at $($result.Backup)" }
}

Write-Step ''
Write-Step 'configs linked. WezTerm and Neovim themselves are not installed by this script.'
Write-Step 'requirements: WezTerm nightly, Neovim 0.10+, JetBrainsMono Nerd Font.'
