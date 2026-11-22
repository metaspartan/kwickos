if (-not $env:KWICK_ENV -and (Test-Path -PathType Leaf /usr/lib/kwick/shell-env)) {
    foreach ($l in (& /usr/lib/kwick/shell-env)) {
        $i = $l.IndexOf('=')
        if ($i -gt 0) { [Environment]::SetEnvironmentVariable($l.Substring(0, $i), $l.Substring($i + 1)) }
    }
}

function Get-KwickFirst([string]$Path) {
    if (Test-Path -PathType Leaf $Path) { $f = Get-Content -TotalCount 1 $Path; if ($f) { return $f.Trim() } }
    return ''
}

$KwickCfg = if ($env:XDG_CONFIG_HOME) { "$env:XDG_CONFIG_HOME/kwick" } else { "$HOME/.config/kwick" }
$KwickStyle = $env:KWICK_PROMPT
if (-not $KwickStyle) { $KwickStyle = Get-KwickFirst "$KwickCfg/prompt" }
if (-not $KwickStyle) { $KwickStyle = Get-KwickFirst /etc/kwick/prompt }
if ($KwickStyle -notin 'kwick', 'minimal', 'powerline', 'starship') { $KwickStyle = 'kwick' }
if ($KwickStyle -eq 'starship' -and -not (Get-Command starship -CommandType Application -ErrorAction SilentlyContinue)) { $KwickStyle = 'kwick' }
$KwickHi = switch (Get-KwickFirst "$KwickCfg/layout") { 'windows' { 32 } 'linux' { 69 } default { 33 } }
$KwickUtf = ($env:TERM -notin 'linux', 'dumb', '') -and ("$env:LC_ALL$env:LC_CTYPE$env:LANG" -match '(?i)utf-?8')
$KwickRoot = ([Environment]::UserName -eq 'root')
$KwickUserHost = "$([Environment]::UserName)@$([Environment]::MachineName)"
$E = [char]27

function Get-KwickDir {
    $p = (Get-Location).ProviderPath
    if ($p -eq $HOME) { return '~' }
    if ($p -eq '/') { return '/' }
    return Split-Path -Leaf $p
}

function Get-KwickGitBranch {
    $d = (Get-Location).ProviderPath
    while ($true) {
        $h = Join-Path $d '.git/HEAD'
        if (Test-Path -PathType Leaf $h) {
            $s = (Get-Content -TotalCount 1 $h).Trim()
            if ($s.StartsWith('ref: refs/heads/')) { return $s.Substring(16) }
            return $s.Substring(0, [Math]::Min(7, $s.Length))
        }
        if ($d -eq '/' -or -not $d) { return '' }
        $d = Split-Path -Parent $d
    }
}

function ll { & ls -alF --color=auto @args }
function la { & ls -A --color=auto @args }
function l { & ls -CF --color=auto @args }
if (Test-Path Alias:ls) { Remove-Item Alias:ls -Force }
function ls { & /usr/bin/ls --color=auto @args }

switch ($KwickStyle) {
    'starship' {
        if (-not $env:STARSHIP_CONFIG -and -not (Test-Path "$HOME/.config/starship.toml")) { $env:STARSHIP_CONFIG = '/usr/share/kwick/shell/starship.toml' }
        Invoke-Expression (& starship init powershell | Out-String)
    }
    'minimal' {
        function global:prompt {
            $ok = $?
            $a = if ($KwickUtf) { [string][char]0x276F } else { '>' }
            $c = if ($ok) { "38;5;$KwickHi" } else { '31' }
            "$E[1;38;5;${KwickHi}m$(Get-KwickDir)$E[0m $E[${c}m$a$E[0m "
        }
    }
    'powerline' {
        function global:prompt {
            $ok = $?
            $sep = if ($KwickUtf) { [string][char]0xE0B0 } else { '' }
            $br = if ($KwickUtf) { [string][char]0xE0A0 + ' ' } else { 'git:' }
            $bgu = if ($KwickRoot) { '41' } else { '48;5;238' }
            $fgs = if ($KwickRoot) { '31' } else { '38;5;238' }
            $s = "$E[${bgu};38;5;252m $KwickUserHost $E[0;${fgs};48;5;${KwickHi}m$sep$E[1;97;48;5;${KwickHi}m $(Get-KwickDir) "
            $b = Get-KwickGitBranch
            if ($b) {
                $end = if ($ok) { '38;5;236' } else { '31' }
                $s += "$E[0;38;5;${KwickHi};48;5;236m$sep$E[0;38;5;250;48;5;236m $br$b $E[0;${end}m$sep$E[0m "
            } else {
                $end = if ($ok) { "38;5;$KwickHi" } else { '31' }
                $s += "$E[0;${end}m$sep$E[0m "
            }
            $s
        }
    }
    default {
        function global:prompt {
            $ok = $?
            $ch = if ($KwickRoot) { '#' } else { '$' }
            $who = if ($KwickRoot) { '31' } else { '38;5;245' }
            $c = if ($ok) { $ch } else { "$E[31m$ch$E[0m" }
            "$E[${who}m$KwickUserHost$E[0m $E[1;38;5;${KwickHi}m$(Get-KwickDir)$E[0m $c "
        }
    }
}
