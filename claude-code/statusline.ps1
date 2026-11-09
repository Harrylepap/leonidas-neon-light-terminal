param()

# ── ENCODAGE UTF-8 SANS BOM — doit être la toute première instruction ─────────
# New-Object UTF8Encoding($false) = UTF-8 sans BOM, garantit que les blocs █
# passent correctement même dans PowerShell 5.1 capturé par Claude Code.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
$OutputEncoding               = New-Object System.Text.UTF8Encoding($false)
# Le JSON envoyé par Claude Code sur stdin est en UTF-8 (nom de session accentué)

$Esc = [char]27

# Read JSON from stdin (Claude Code statusLine API)
# Lecture du flux brut en UTF-8 : indépendant de la console (absente en CI) et de son encodage
$stdinReader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), (New-Object System.Text.UTF8Encoding($false)))
$jsonRaw = $stdinReader.ReadToEnd()
$json = $null
try { $json = $jsonRaw | ConvertFrom-Json } catch {}

# ── helpers ───────────────────────────────────────────────────────────────────
# Palette Leonidas - Neon Light : codes ANSI 16 couleurs -> truecolor néon
$NEON = @{ "31"="38;2;255;61;110"; "32"="38;2;46;230;166"; "33"="38;2;255;122;47"; "35"="38;2;255;46;136"; "36"="38;2;43;217;232"; "37"="38;2;255;244;250"; "90"="38;2;122;90;150"; "91"="38;2;255;61;110"; "93"="38;2;255;211;110"; "94"="38;2;142;63;214"; "95"="38;2;255;92;240"; "96"="38;2;125;243;255" }
function AnsiColor($code, $text) { if ($NEON.ContainsKey($code)) { $code = $NEON[$code] }; "${Esc}[${code}m${text}${Esc}[0m" }
function Dim($text)   { AnsiColor "90" $text }
function Bold($text)  { "${Esc}[1m${text}${Esc}[0m" }
function Sep()        { Dim " | " }

# ── Fuseau Europe/Paris (ID Windows) ──────────────────────────────────────────
$TZ_PARIS = $null
try { $TZ_PARIS = [TimeZoneInfo]::FindSystemTimeZoneById("Romance Standard Time") } catch {}

# Convertit un Unix epoch en DateTimeOffset Paris
function EpochToParisDTO($epochSeconds) {
    $utc = [DateTimeOffset]::FromUnixTimeSeconds([long]$epochSeconds)
    if ($TZ_PARIS) {
        $local = [TimeZoneInfo]::ConvertTime($utc, $TZ_PARIS)
        return $local
    }
    return $utc
}

# Formate le timestamp de reset au format 24h :
#   - si dans < 24h  → "15:59"
#   - si dans >= 24h → "Jun 16 02:00"
function FormatResetLabel($epochSeconds) {
    try {
        $dto = EpochToParisDTO $epochSeconds
        $now = if ($TZ_PARIS) { [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $TZ_PARIS) } `
               else           { [DateTimeOffset]::UtcNow }
        $diff = $dto - $now
        if ($diff.TotalSeconds -le 0) { return "maintenant" }

        # Format 24h : "HH:mm"
        $h   = $dto.DateTime.Hour
        $min = $dto.DateTime.Minute
        $timeStr = $h.ToString("D2") + ":" + $min.ToString("D2")

        if ($diff.TotalHours -lt 24) {
            return $timeStr
        } else {
            # Format date : "16 juin 02:00" (mois français abrégés, codés en dur)
            $months = @("janv.","févr.","mars","avr.","mai","juin","juil.","août","sept.","oct.","nov.","déc.")
            $mon = $months[$dto.DateTime.Month - 1]
            $day = $dto.DateTime.Day
            return "${day} ${mon} ${timeStr}"
        }
    } catch { return "?" }
}

# ── Couleur progressive selon le pourcentage (barres session/week) ───────────
# Retourne un code ANSI de couleur : vert → jaune → orange → rouge → rouge vif
function PctColor($pct) {
    if     ($pct -gt 95) { return "91" }   # rouge vif
    elseif ($pct -gt 85) { return "31" }   # rouge
    elseif ($pct -gt 70) { return "93" }   # orange/jaune vif
    elseif ($pct -gt 50) { return "33" }   # jaune
    else                  { return "32" }   # vert
}

# ── Couleur dédiée à la barre ctx (contexte) ─────────────────────────────────
# Palette bleu/cyan en état normal, alerte magenta/rouge quand > 85 % rempli.
# Visuellement distinct du dégradé vert→rouge des barres de consommation.
function CtxColor($pct) {
    if     ($pct -gt 95) { return "91" }   # rouge vif   — contexte quasi plein
    elseif ($pct -gt 85) { return "95" }   # magenta vif — signal d'alerte
    elseif ($pct -gt 60) { return "94" }   # bleu vif    — contexte chargé
    else                  { return "36" }   # cyan        — état normal
}

# ── Barre de progression inline (blocs █/░) ───────────────────────────────────
# Produit "████░░░░░░ 40% → 15:59"
# $pct        : entier 0-100
# $width      : nombre total de cellules de la barre rempli+vide (défaut 10)
# $color      : code ANSI couleur (ex. "32" pour vert)
# $resetLabel : chaîne optionnelle affichée après le % (ex. "→ 15:59")
function InlineBar($pct, $width, $color, $resetLabel = "") {
    $filled = [math]::Round([double]$pct / 100.0 * $width)
    if ($filled -lt 0)      { $filled = 0 }
    if ($filled -gt $width) { $filled = $width }
    $empty = $width - $filled

    $block   = [char]0x2588   # █
    $light   = [char]0x2591   # ░
    $filledStr = $block.ToString() * $filled
    $emptyStr  = $light.ToString() * $empty

    # Dégradé néon cellule par cellule : lagon → violet → rose → orange → jaune doré
    $stops = @(@(43,217,232), @(142,63,214), @(255,46,136), @(255,122,47), @(252,175,23))
    $bar = ""
    $lastRgb = $stops[0]
    for ($i = 0; $i -lt $filled; $i++) {
        $t   = if ($width -gt 1) { $i / ($width - 1) } else { 0 }
        $seg = [math]::Min([math]::Floor($t * ($stops.Count - 1)), $stops.Count - 2)
        $f   = $t * ($stops.Count - 1) - $seg
        $a = $stops[$seg]; $b = $stops[$seg + 1]
        $rgb = @(0..2 | ForEach-Object { [int]($a[$_] + ($b[$_] - $a[$_]) * $f) })
        $lastRgb = $rgb
        $bar += "${Esc}[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m" + $block
    }
    $bar += "${Esc}[38;2;58;31;92m" + $emptyStr + "${Esc}[0m"
    $pctStr = "${Esc}[1;38;2;$($lastRgb[0]);$($lastRgb[1]);$($lastRgb[2])m$pct%${Esc}[0m"
    $arrow    = [char]0x2192   # →
    $resetStr = if ($resetLabel) { " " + (AnsiColor "90" "$arrow") + " " + (AnsiColor "37" $resetLabel) } else { "" }
    return $bar + " " + $pctStr + $resetStr
}

# ── LINE 1: user@host  cwd  (branche git) ─────────────────────────────────────
$user  = $env:USERNAME.ToLower()
$host_ = if ($env:COMPUTERNAME) { $env:COMPUTERNAME.ToLower() -replace '\..*','' } else { "localhost" }
$userHost = AnsiColor "32" "${user}@${host_}"

$cwd = ""
if ($json -and $json.cwd)              { $cwd = $json.cwd }
elseif ($env:STATUSLINE_CWD)           { $cwd = $env:STATUSLINE_CWD }
else                                   { $cwd = (Get-Location).Path }

$homePath = $env:USERPROFILE
if ($homePath -and $cwd.StartsWith($homePath)) {
    $cwd = "~" + $cwd.Substring($homePath.Length).Replace("\", "/")
} else {
    $cwd = $cwd.Replace("\", "/")
}
$cwdStr = AnsiColor "33" $cwd

$gitPart = ""
try {
    $gitDir = if ($json -and $json.workspace -and $json.workspace.current_dir) {
        $json.workspace.current_dir
    } else { $null }

    $branchArgs = @("rev-parse", "--abbrev-ref", "HEAD")
    $branch = if ($gitDir) { & git -C $gitDir @branchArgs 2>$null } else { & git @branchArgs 2>$null }

    if ($branch) {
        $branch    = $branch.Trim()
        $porcelain = if ($gitDir) { & git -C $gitDir status --porcelain 2>$null } else { & git status --porcelain 2>$null }
        $dirty     = if ($porcelain) { " *" } else { "" }
        $ahead     = if ($gitDir) { (& git -C $gitDir rev-list --count "@{u}..HEAD" 2>$null) } else { (& git rev-list --count "@{u}..HEAD" 2>$null) }
        $behind    = if ($gitDir) { (& git -C $gitDir rev-list --count "HEAD..@{u}" 2>$null) } else { (& git rev-list --count "HEAD..@{u}" 2>$null) }
        $ahead     = if ($ahead)  { $ahead.Trim()  } else { "0" }
        $behind    = if ($behind) { $behind.Trim() } else { "0" }
        $sync = ""
        if ($ahead  -ne "0") { $sync += " ^$ahead"  }
        if ($behind -ne "0") { $sync += " v$behind" }
        $gitPart = "  " + (AnsiColor "36" "(${branch}${dirty}${sync})")
    }
} catch {}

$line1 = "${userHost}  ${cwdStr}${gitPart}"

# ── LINE 2: modèle + contexte + (optionnel) session + java/mvn ────────────────

$model = ""
if ($json -and $json.model -and $json.model.display_name) { $model = $json.model.display_name }
if (-not $model -and $json -and $json.model -and $json.model.id) { $model = $json.model.id }
if (-not $model) { $model = $env:CLAUDE_MODEL }
if (-not $model) { $model = "claude" }
$modelStr = AnsiColor "35" $model

# Contexte — libellé + % coloré uniquement (sans barre de blocs)
$ctxStr = (Dim "ctx:") + (AnsiColor "90" "?%")
if ($json -and $json.context_window) {
    $usedPct = $json.context_window.used_percentage
    if ($null -ne $usedPct) {
        $pct   = [math]::Round($usedPct)
        $color = CtxColor $pct
        $ctxStr = (Dim "ctx:") + (AnsiColor $color "$pct%")
    }
}

$accountStr = ""
try {
    $authOutput = (& claude auth status 2>&1) -join "`n"
    $emailMatch = [regex]::Match($authOutput, '[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}')
    if ($emailMatch.Success) {
        $accountStr = AnsiColor "96" $emailMatch.Value
    }
} catch {}

$sessionStr = ""
if ($json -and $json.session_name) {
    $sessionStr = AnsiColor "37" $json.session_name
}

$javaStr = ""
$projectDir = ""
if ($json -and $json.workspace -and $json.workspace.project_dir) { $projectDir = $json.workspace.project_dir }
elseif ($json -and $json.cwd) { $projectDir = $json.cwd }
if ($projectDir -and (Test-Path (Join-Path $projectDir "pom.xml"))) {
    $javaVersion = ""
    try {
        $jv = (& java -version 2>&1) | Select-String 'version "([^"]+)"'
        if ($jv) { $javaVersion = $jv.Matches[0].Groups[1].Value -replace '^1\.', '' }
    } catch {}
    $mvnVersion = ""
    try {
        $mv = (& mvn -version 2>&1) | Select-String 'Apache Maven ([\d.]+)'
        if ($mv) { $mvnVersion = $mv.Matches[0].Groups[1].Value }
    } catch {}
    $jVal = if ($javaVersion) { $javaVersion } else { "?" }
    $mVal = if ($mvnVersion)  { $mvnVersion  } else { "?" }
    $javaStr = (Dim "java:") + (AnsiColor "33" $jVal) + (Sep) + (Dim "mvn:") + (AnsiColor "33" $mVal)
}

# ── Segments session/week — inline sur la ligne 2 ────────────────────────────
# N'est rendu que si $json.rate_limits.<champ> existe (absent avant 1ère réponse API).
$BAR_INLINE = 10   # largeur de la barre inline (cellules)

$sessionRateStr = ""
$weekRateStr    = ""

if ($json -and $json.rate_limits) {
    $rl = $json.rate_limits

    # ── Fenêtre 5h — "session:" ───────────────────────────────────────────────
    if ($rl.five_hour -and $null -ne $rl.five_hour.used_percentage) {
        $pct5   = [math]::Round($rl.five_hour.used_percentage)
        $color5 = PctColor $pct5
        $reset5 = if ($rl.five_hour.resets_at) { FormatResetLabel $rl.five_hour.resets_at } else { "" }
        $sessionRateStr = (Dim "session:") + (InlineBar $pct5 $BAR_INLINE $color5 $reset5)
    }

    # ── Fenêtre 7d — "week:" avec barre de blocs + % + → + reset ────────────
    if ($rl.seven_day -and $null -ne $rl.seven_day.used_percentage) {
        $pct7   = [math]::Round($rl.seven_day.used_percentage)
        $color7 = PctColor $pct7
        $reset7 = if ($rl.seven_day.resets_at) { FormatResetLabel $rl.seven_day.resets_at } else { "" }
        $weekRateStr = (Dim "week:") + (InlineBar $pct7 $BAR_INLINE $color7 $reset7)
    }
}

# ── Assemblage ligne 2 : model | ctx | session | week | account | session-name? | java/mvn? ──
$seg2 = @($modelStr, $ctxStr)
if ($sessionRateStr) { $seg2 += $sessionRateStr }
if ($weekRateStr)    { $seg2 += $weekRateStr }
if ($accountStr)     { $seg2 += $accountStr }
if ($sessionStr)     { $seg2 += $sessionStr }
if ($javaStr)        { $seg2 += $javaStr }
$line2 = $seg2 -join (Sep)

# ── Assemblage final ──────────────────────────────────────────────────────────
$allLines = @($line1, $line2)
$output = $allLines -join "`n"

# Écriture via [Console]::Out pour respecter l'encodage UTF-8 défini plus haut
[Console]::Out.Write($output)
