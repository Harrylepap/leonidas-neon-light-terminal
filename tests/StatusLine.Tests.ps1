#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Runs the Claude Code status line the way Claude Code does: JSON on stdin, ANSI text on stdout.

BeforeAll {
    $script:Script = Join-Path (Split-Path -Parent $PSScriptRoot) 'claude-code\statusline.ps1'

    # ESC is rebuilt locally everywhere: no reliance on variables shared across Pester blocks
    function Get-Esc { [string][char]27 }

    function Invoke-StatusLine([string]$json) {
        $in = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($in, $json, (New-Object System.Text.UTF8Encoding($false)))
        $psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe', "-NoProfile -ExecutionPolicy Bypass -File `"$Script`""
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.UseShellExecute = $false
        $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $p = [Diagnostics.Process]::Start($psi)
        $bytes = [IO.File]::ReadAllBytes($in)
        $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        Remove-Item $in
        $out
    }

    function Remove-Ansi([string]$s) { $s -replace ((Get-Esc) + '\[[0-9;]*m'), '' }

    function Get-Truecolor([int]$r, [int]$g, [int]$b) { [regex]::Escape((Get-Esc) + "[38;2;$r;$g;${b}m") }
}

Describe 'statusline.ps1' {
    It 'prints two lines with model and context usage' {
        $out = Invoke-StatusLine '{"model":{"display_name":"Opus Test"},"context_window":{"used_percentage":42}}'
        $plain = Remove-Ansi $out
        ($plain -split "`n").Count | Should -Be 2
        $plain | Should -Match 'Opus Test'
        $plain | Should -Match 'ctx:42%'
    }

    It 'uses neon truecolor escapes instead of the 16 ANSI colors' {
        $out = Invoke-StatusLine '{"model":{"display_name":"Opus Test"}}'
        $out | Should -Match ((Get-Truecolor 255 46 136) + 'Opus Test')
    }

    It 'draws rate-limit gauges as a per-cell gradient' {
        $json = '{"model":{"display_name":"M"},"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":1999999999}}}'
        $out = Invoke-StatusLine $json
        (Remove-Ansi $out) | Should -Match 'session:█{10} 100%'
        # first cell lagoon, last cell golden yellow
        $out | Should -Match ((Get-Truecolor 43 217 232) + '█')
        $out | Should -Match ((Get-Truecolor 252 175 23) + '█')
    }

    It 'keeps accented session names intact (UTF-8 stdin)' {
        $out = Invoke-StatusLine '{"model":{"display_name":"M"},"session_name":"Thème déc. août"}'
        (Remove-Ansi $out) | Should -Match 'Thème déc\. août'
    }

    It 'survives invalid JSON' {
        { Invoke-StatusLine 'not json' } | Should -Not -Throw
        (Remove-Ansi (Invoke-StatusLine 'not json')) | Should -Match 'ctx:\?%'
    }
}
