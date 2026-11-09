<#
.SYNOPSIS
    Installs the Leonidas - Neon Light terminal style (Windows Terminal, Starship, Claude Code status line).

.DESCRIPTION
    Every file that gets modified is backed up first as <file>.bak-<timestamp>.
    Works with Windows PowerShell 5.1 and PowerShell 7+.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -NoShader -SkipClaudeCode
#>
[CmdletBinding()]
param(
    [switch]$SkipWindowsTerminal,
    [switch]$SkipStarship,
    [switch]$SkipClaudeCode,
    # Keep the color scheme but do not enable the neon glow / sparkles shader
    [switch]$NoShader,
    # Install starship, eza and JetBrainsMono Nerd Font with winget first
    [switch]$InstallTools,
    # Testing overrides
    [string]$TargetHome = $env:USERPROFILE,
    [string]$WindowsTerminalSettings
)

$ErrorActionPreference = 'Stop'
$Here   = $PSScriptRoot
$Stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$Utf8   = New-Object System.Text.UTF8Encoding($false)
$Scheme = 'Leonidas - Neon Light'

function Write-Step($text) { Write-Host "==> $text" -ForegroundColor Magenta }
function Write-Ok($text)   { Write-Host "    $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "    $text" -ForegroundColor Yellow }

function Backup-File($path) {
    if (Test-Path $path) {
        $bak = "$path.bak-$Stamp"
        Copy-Item $path $bak
        Write-Ok "backup: $bak"
    }
}

function Save-Json($object, $path) {
    $json = $object | ConvertTo-Json -Depth 32
    [IO.File]::WriteAllText($path, $json, $Utf8)
}

function Set-Prop($object, $name, $value) {
    if ($object.PSObject.Properties[$name]) { $object.$name = $value }
    else { $object | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

# ─── Windows Terminal ────────────────────────────────────────────────────────
function Install-WindowsTerminal {
    Write-Step 'Windows Terminal'
    $candidates = @(
        $WindowsTerminalSettings,
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    ) | Where-Object { $_ -and (Test-Path $_) }

    if (-not $candidates) { Write-Warn 'settings.json not found: is Windows Terminal installed? Skipped.'; return }
    $settingsPath = @($candidates)[0]

    try { $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch {
        Write-Warn "Could not parse $settingsPath (comments in the file?)."
        Write-Warn 'Add windows-terminal\leonidas-neon-light.scheme.json to "schemes" manually (see README).'
        return
    }
    Backup-File $settingsPath

    # 1. Color scheme
    $newScheme = Get-Content (Join-Path $Here 'windows-terminal\leonidas-neon-light.scheme.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $schemes = @()
    if ($settings.PSObject.Properties['schemes']) { $schemes = @($settings.schemes | Where-Object { $_.name -ne $Scheme }) }
    Set-Prop $settings 'schemes' (@($schemes) + $newScheme)

    # 2. Defaults applied to every profile
    if (-not $settings.PSObject.Properties['profiles']) { Set-Prop $settings 'profiles' ([pscustomobject]@{}) }
    if ($settings.profiles -is [array]) {
        Write-Warn 'Legacy "profiles" array format: set "colorScheme" manually on each profile.'
    } else {
        if (-not $settings.profiles.PSObject.Properties['defaults']) { Set-Prop $settings.profiles 'defaults' ([pscustomobject]@{}) }
        $d = $settings.profiles.defaults
        Set-Prop $d 'colorScheme' $Scheme
        Set-Prop $d 'cursorShape' 'bar'
        Set-Prop $d 'opacity' 92
        Set-Prop $d 'useAcrylic' $true
        Set-Prop $d 'tabColor' '#FF4FA3'

        if (-not $NoShader) {
            $shaderDir = Join-Path $TargetHome '.config\leonidas-neon-light'
            New-Item -ItemType Directory -Force $shaderDir | Out-Null
            $shader = Join-Path $shaderDir 'leonidas-neon.hlsl'
            Copy-Item (Join-Path $Here 'windows-terminal\leonidas-neon.hlsl') $shader -Force
            Set-Prop $d 'experimental.pixelShaderPath' $shader
            Write-Ok "shader: $shader"
        }
    }

    # 3. Ctrl+Alt+G toggles the shader
    if (-not $NoShader) {
        $actionId = 'User.leonidasNeonShader'
        $actions = @()
        if ($settings.PSObject.Properties['actions']) { $actions = @($settings.actions | Where-Object { $_.id -ne $actionId }) }
        if ($settings.PSObject.Properties['keybindings']) {
            Set-Prop $settings 'actions' (@($actions) + [pscustomobject]@{ command = 'toggleShaderEffects'; id = $actionId })
            $keys = @($settings.keybindings | Where-Object { $_.id -ne $actionId })
            Set-Prop $settings 'keybindings' (@($keys) + [pscustomobject]@{ id = $actionId; keys = 'ctrl+alt+g' })
        } else {
            Set-Prop $settings 'actions' (@($actions) + [pscustomobject]@{ command = 'toggleShaderEffects'; id = $actionId; keys = 'ctrl+alt+g' })
        }
    }

    Save-Json $settings $settingsPath
    Write-Ok "updated: $settingsPath"
}

# ─── Starship ────────────────────────────────────────────────────────────────
function Install-Starship {
    Write-Step 'Starship prompt'
    $configDir = Join-Path $TargetHome '.config'
    New-Item -ItemType Directory -Force (Join-Path $configDir 'starship') | Out-Null

    $toml = Join-Path $configDir 'starship.toml'
    Backup-File $toml
    Copy-Item (Join-Path $Here 'starship\starship.toml') $toml -Force
    Copy-Item (Join-Path $Here 'starship\build-target.sh') (Join-Path $configDir 'starship\build-target.sh') -Force
    Write-Ok "config: $toml"

    # Git Bash: eza aliases + starship init, sourced from ~/.bashrc
    $snippetDir = Join-Path $configDir 'leonidas-neon-light'
    New-Item -ItemType Directory -Force $snippetDir | Out-Null
    Copy-Item (Join-Path $Here 'bash\leonidas-neon.bash') (Join-Path $snippetDir 'leonidas-neon.bash') -Force

    $bashrc = Join-Path $TargetHome '.bashrc'
    $hasSource = (Test-Path $bashrc) -and (Select-String -Path $bashrc -Pattern 'leonidas-neon.bash' -SimpleMatch -Quiet)
    if (-not $hasSource) {
        Backup-File $bashrc
        $line = '[ -f ~/.config/leonidas-neon-light/leonidas-neon.bash ] && . ~/.config/leonidas-neon-light/leonidas-neon.bash'
        [IO.File]::AppendAllText($bashrc, "`n# --- Leonidas - Neon Light: eza + starship ---`n$line`n", $Utf8)
        Write-Ok "Git Bash setup sourced from $bashrc"
    }

    foreach ($tool in 'starship', 'eza') {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Write-Warn "$tool not found on PATH: run install.ps1 -InstallTools, or winget install it."
        }
    }
    Write-Warn 'The prompt and eza icons need a Nerd Font in the terminal (e.g. JetBrainsMono Nerd Font).'
}

# ─── Tools (winget) ──────────────────────────────────────────────────────────
function Install-Tools {
    Write-Step 'Tools (winget)'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Warn 'winget not available. Skipped.'; return }
    foreach ($id in 'Starship.Starship', 'eza-community.eza', 'DEVCOM.JetBrainsMonoNerdFont') {
        Write-Ok "winget install $id"
        winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements | Out-Null
    }
    Write-Warn 'Set "JetBrainsMono Nerd Font" as the font in Windows Terminal (Settings > Defaults > Appearance).'
}

# ─── Claude Code status line ─────────────────────────────────────────────────
function Install-ClaudeCode {
    Write-Step 'Claude Code status line'
    $claudeDir = Join-Path $TargetHome '.claude'
    New-Item -ItemType Directory -Force $claudeDir | Out-Null

    $script = Join-Path $claudeDir 'leonidas-statusline.ps1'
    Copy-Item (Join-Path $Here 'claude-code\statusline.ps1') $script -Force
    Write-Ok "script: $script"

    $settingsPath = Join-Path $claudeDir 'settings.json'
    $settings = [pscustomobject]@{}
    if (Test-Path $settingsPath) {
        Backup-File $settingsPath
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File ' + ($script -replace '\\', '/')
    Set-Prop $settings 'statusLine' ([pscustomobject]@{ type = 'command'; command = $command })
    Save-Json $settings $settingsPath
    Write-Ok "statusLine set in $settingsPath"
}

if ($InstallTools)              { Install-Tools }
if (-not $SkipWindowsTerminal) { Install-WindowsTerminal }
if (-not $SkipStarship)        { Install-Starship }
if (-not $SkipClaudeCode)      { Install-ClaudeCode }

Write-Host ''
Write-Host 'Done. Open a new terminal tab to see Leonidas - Neon Light.' -ForegroundColor Cyan
