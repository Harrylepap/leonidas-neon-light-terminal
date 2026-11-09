#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Runs install.ps1 against a throw-away home folder and a fake Windows Terminal settings.json.

BeforeAll {
    $script:Root      = Split-Path -Parent $PSScriptRoot
    $script:Installer = Join-Path $Root 'install.ps1'

    function New-Sandbox {
        $dir  = Join-Path ([IO.Path]::GetTempPath()) ('lnl-' + [guid]::NewGuid())
        $home_ = Join-Path $dir 'home'
        New-Item -ItemType Directory -Force (Join-Path $home_ '.claude') | Out-Null
        $wt = Join-Path $dir 'wt.json'
        @'
{
    "defaultProfile": "{00000000-0000-0000-0000-000000000001}",
    "actions": [],
    "keybindings": [ { "id": "Terminal.CopyToClipboard", "keys": "ctrl+c" } ],
    "profiles": { "defaults": { "font": { "face": "JetBrainsMono NFM" } }, "list": [ { "name": "Git Bash" } ] },
    "schemes": [ { "name": "Other" } ]
}
'@ | Set-Content -Path $wt -Encoding UTF8
        '{ "model": "opus", "enabledPlugins": { "foo": true } }' | Set-Content -Path (Join-Path $home_ '.claude\settings.json') -Encoding UTF8
        [pscustomobject]@{ Dir = $dir; Home = $home_; Wt = $wt }
    }

    function Invoke-Installer($sb, [hashtable]$extra = @{}) {
        & $Installer -TargetHome $sb.Home -WindowsTerminalSettings $sb.Wt @extra 6>$null | Out-Null
    }

    function Read-Json($path) { Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json }
}

Describe 'install.ps1' {
    BeforeEach { $script:sb = New-Sandbox }
    AfterEach  { Remove-Item $sb.Dir -Recurse -Force -ErrorAction SilentlyContinue }

    It 'adds the scheme and applies it to every profile' {
        Invoke-Installer $sb
        $wt = Read-Json $sb.Wt
        ($wt.schemes | Where-Object name -eq 'Leonidas - Neon Light') | Should -Not -BeNullOrEmpty
        ($wt.schemes | Where-Object name -eq 'Other') | Should -Not -BeNullOrEmpty
        $wt.profiles.defaults.colorScheme | Should -Be 'Leonidas - Neon Light'
        $wt.profiles.defaults.font.face | Should -Be 'JetBrainsMono NFM'
    }

    It 'installs the shader and binds Ctrl+Alt+G' {
        Invoke-Installer $sb
        $wt = Read-Json $sb.Wt
        $shader = $wt.profiles.defaults.'experimental.pixelShaderPath'
        $shader | Should -Exist
        ($wt.keybindings | Where-Object keys -eq 'ctrl+alt+g').id | Should -Be 'User.leonidasNeonShader'
        ($wt.actions | Where-Object id -eq 'User.leonidasNeonShader').command | Should -Be 'toggleShaderEffects'
    }

    It 'skips the shader with -NoShader' {
        Invoke-Installer $sb @{ NoShader = $true }
        $wt = Read-Json $sb.Wt
        $wt.profiles.defaults.PSObject.Properties['experimental.pixelShaderPath'] | Should -BeNullOrEmpty
        ($wt.keybindings | Where-Object keys -eq 'ctrl+alt+g') | Should -BeNullOrEmpty
    }

    It 'installs starship and sources the bash setup once' {
        Invoke-Installer $sb
        Join-Path $sb.Home '.config\starship.toml' | Should -Exist
        Join-Path $sb.Home '.config\starship\build-target.sh' | Should -Exist
        Join-Path $sb.Home '.config\leonidas-neon-light\leonidas-neon.bash' | Should -Exist
        (Select-String -Path (Join-Path $sb.Home '.bashrc') -Pattern 'leonidas-neon.bash' -SimpleMatch).Count | Should -Be 1
    }

    It 'sets the Claude Code status line and keeps existing settings' {
        Invoke-Installer $sb
        $claude = Read-Json (Join-Path $sb.Home '.claude\settings.json')
        $claude.statusLine.type | Should -Be 'command'
        $claude.statusLine.command | Should -Match 'leonidas-statusline\.ps1'
        $claude.model | Should -Be 'opus'
        $claude.enabledPlugins.foo | Should -BeTrue
        Join-Path $sb.Home '.claude\leonidas-statusline.ps1' | Should -Exist
    }

    It 'is idempotent: a second run adds no duplicates' {
        Invoke-Installer $sb
        Invoke-Installer $sb
        $wt = Read-Json $sb.Wt
        @($wt.schemes | Where-Object name -eq 'Leonidas - Neon Light').Count | Should -Be 1
        @($wt.keybindings | Where-Object id -eq 'User.leonidasNeonShader').Count | Should -Be 1
        @($wt.actions | Where-Object id -eq 'User.leonidasNeonShader').Count | Should -Be 1
        (Select-String -Path (Join-Path $sb.Home '.bashrc') -Pattern 'leonidas-neon.bash' -SimpleMatch).Count | Should -Be 1
    }

    It 'backs up every file it modifies' {
        Invoke-Installer $sb
        @(Get-ChildItem $sb.Dir -Filter 'wt.json.bak-*').Count | Should -Be 1
        @(Get-ChildItem (Join-Path $sb.Home '.claude') -Filter 'settings.json.bak-*').Count | Should -Be 1
    }

    It 'leaves skipped components untouched' {
        $before = Get-Content $sb.Wt -Raw
        Invoke-Installer $sb @{ SkipWindowsTerminal = $true; SkipStarship = $true; SkipClaudeCode = $true }
        Get-Content $sb.Wt -Raw | Should -Be $before
        Join-Path $sb.Home '.config\starship.toml' | Should -Not -Exist
    }
}
