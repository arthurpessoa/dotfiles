# Clones this repository and links the WezTerm and Neovim configs into place.
#
# Run it directly, or through the one-liner in the README, which pipes the file
# straight into Invoke-Expression before the repository exists on disk. That is
# why there is no param block and no #Requires here: both are legal only in a
# script that is being run as a file, and piped text is not one.
#
# Set DOTFILES_DRY_RUN=1 to see what it would do without doing it, and
# DOTFILES_SKIP_TOOLS=1 to link the configs without installing anything.
#
# It links the configs and installs the command-line tools Neovim reaches for.
# WezTerm, Neovim and the Nerd Font are not installed here; that is a larger
# installer, still to be built.

$ErrorActionPreference = 'Stop'
$DryRun = $env:DOTFILES_DRY_RUN -eq '1'
$SkipTools = $env:DOTFILES_SKIP_TOOLS -eq '1'

# The tools LazyVim's pickers and grep depend on. Scoop first: it installs into
# the user profile and needs no elevation. The scoop name is the package, which
# is not always the command -- `rg` comes out of `ripgrep`.
$Tools = @(
    @{ Command = 'fd';  Scoop = 'main/fd';      Winget = 'sharkdp.fd' }
    @{ Command = 'rg';  Scoop = 'main/ripgrep'; Winget = 'BurntSushi.ripgrep.MSVC' }
    @{ Command = 'fzf'; Scoop = 'main/fzf';     Winget = 'junegunn.fzf' }
    @{ Command = 'gh';  Scoop = 'main/gh';      Winget = 'GitHub.cli' }
)

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

function Test-Command {
    param([Parameter(Mandatory)] [string] $Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# A tool counts as installed when its command answers afterwards, not when the
# package manager exits zero: scoop refuses to reinstall and exits non-zero on
# a run that was perfectly fine, and a manager can succeed while putting the
# binary somewhere off PATH.
function Install-Tool {
    param(
        [Parameter(Mandatory)] $Tool,
        [switch] $DryRun
    )

    if (Test-Command $Tool.Command) { return 'already installed' }

    $attempts = @()
    if (Test-Command 'scoop')  { $attempts += @{ Manager = 'scoop';  Run = { scoop install $Tool.Scoop } } }
    if (Test-Command 'winget') {
        $attempts += @{ Manager = 'winget'; Run = {
            winget install --id $Tool.Winget --silent --accept-package-agreements --accept-source-agreements
        } }
    }

    if ($attempts.Count -eq 0) { return 'no scoop or winget on this machine' }

    if ($DryRun) { return "would install with $($attempts[0].Manager)" }

    foreach ($attempt in $attempts) {
        try { & $attempt.Run | Out-Null } catch { }
        if (Test-Command $Tool.Command) { return "installed with $($attempt.Manager)" }
    }

    return 'failed'
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
    # A pull can fail for reasons that have nothing to do with linking: local
    # commits, a renamed upstream branch, no network. None of those are a
    # reason to leave the configs unlinked, so the failure is reported and the
    # run continues with whatever is already checked out.
    if (-not $DryRun) {
        git -C $RepoRoot pull --ff-only *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Step '  could not pull; continuing with the checkout that is already there'
        }
    }
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

if (-not $SkipTools) {
    Write-Step ''
    foreach ($tool in $Tools) {
        $outcome = Install-Tool $tool -DryRun:$DryRun
        Write-Step ('{0,-42} {1}' -f $tool.Command, $outcome)
    }
}

Write-Step ''
Write-Step 'WezTerm and Neovim themselves are not installed by this script.'
Write-Step 'requirements: WezTerm nightly, Neovim 0.10+, JetBrainsMono Nerd Font.'
Write-Step 'in Neovim, :checkhealth reports anything still missing.'
