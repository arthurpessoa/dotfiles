#Requires -Version 5.1

Write-Host "=== Installing CLI tools for Neovim ===" -ForegroundColor Cyan

$tools = @{
    "fd"  = "sharkdp.fd"
    "rg"  = "BurntSushi.ripgrep.MSVC"
    "fzf" = "junegunn.fzf"
    "ripgrep" = "BurntSushi.ripgrep.MSVC"
}


function Test-Command($cmd) {
    return $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}


function Install-With-Scoop($package) {

    if (Test-Command "scoop") {

        Write-Host "Installing $package with Scoop..." -ForegroundColor Yellow

        scoop install $package

        return $true
    }

    return $false
}


function Install-With-Winget($package) {

    if (Test-Command "winget") {

        Write-Host "Installing $package with Winget..." -ForegroundColor Yellow

        winget install `
            --id $package `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements

        return $true
    }

    return $false
}


foreach ($tool in $tools.Keys) {

    Write-Host ""
    Write-Host "Checking $tool..." -ForegroundColor Cyan


    if (Test-Command $tool) {

        Write-Host "$tool already installed" -ForegroundColor Green
        continue
    }


    $package = $tools[$tool]


    #
    # Try Scoop
    #
    if (Install-With-Scoop $tool) {
        continue
    }


    #
    # Try Winget
    #
    if (Install-With-Winget $package) {
        continue
    }


    Write-Host ""
    Write-Host "Could not install $tool" -ForegroundColor Red
    Write-Host "Install manually using Scoop or Winget"
}


Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host ""
Write-Host "Restart Neovim and run:"
Write-Host ":checkhealth"
