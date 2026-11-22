if ($env.KWICK_ENV? | is-empty) and ("/usr/lib/kwick/shell-env" | path exists) {
    let kv = (^/usr/lib/kwick/shell-env | lines | each {|l| $l | split row -n 2 "=" } | where {|p| ($p | length) == 2 })
    load-env ($kv | where {|p| $p.0 != "PATH" and $p.0 != "Path" } | reduce -f {} {|p, acc| $acc | upsert $p.0 $p.1 })
    let p = ($kv | where {|p| $p.0 == "PATH" })
    if ($p | is-not-empty) { $env.PATH = ($p.0.1 | split row ":") }
}

$env.config.show_banner = false

def kwick-git-branch [] {
    mut d = $env.PWD
    loop {
        let h = ($d | path join ".git" "HEAD")
        if ($h | path exists) and (($h | path type) == "file") {
            let s = (open --raw $h | str trim)
            if ($s | str starts-with "ref: refs/heads/") {
                return ($s | str replace "ref: refs/heads/" "")
            }
            return ($s | str substring 0..6)
        }
        if $d == "/" or $d == "" { return null }
        $d = ($d | path dirname)
    }
}

def kwick-dir [] {
    if $env.PWD == $env.HOME { "~" } else if $env.PWD == "/" { "/" } else { $env.PWD | path basename }
}

def kwick-read [f: string] {
    if ($f | path exists) { open --raw $f | lines | first | default "" | str trim } else { "" }
}

let kwick_cfg = ($env.XDG_CONFIG_HOME? | default ($env.HOME | path join ".config") | path join "kwick")
mut kwick_style = ($env.KWICK_PROMPT? | default "")
if $kwick_style == "" { $kwick_style = (kwick-read ($kwick_cfg | path join "prompt")) }
if $kwick_style == "" { $kwick_style = (kwick-read "/etc/kwick/prompt") }
if not ($kwick_style in ["kwick" "minimal" "powerline" "starship"]) { $kwick_style = "kwick" }
if $kwick_style == "starship" and (which starship | is-empty) { $kwick_style = "kwick" }
let kwick_layout = (kwick-read ($kwick_cfg | path join "layout"))
$env.KWICK_PS_HI = (match $kwick_layout { "windows" => "32", "linux" => "69", _ => "33" })
$env.KWICK_PS_UTF = ((($env.TERM? | default "") not-in ["linux" "dumb" ""]) and ((($env.LC_ALL? | default "") + ($env.LC_CTYPE? | default "") + ($env.LANG? | default "")) =~ '(?i)utf-?8'))
$env.KWICK_PROMPT_STYLE = $kwick_style
$env.KWICK_USERHOST = $"($env.USER? | default (^id -un | str trim))@(open --raw /proc/sys/kernel/hostname | str trim)"

alias ll = ls -la
alias la = ls -a

$env.PROMPT_COMMAND_RIGHT = ""
$env.PROMPT_INDICATOR_VI_INSERT = ""
$env.PROMPT_INDICATOR_VI_NORMAL = ""
$env.PROMPT_MULTILINE_INDICATOR = "::: "

match $kwick_style {
    "starship" => {
        if ($env.STARSHIP_CONFIG? | is-empty) and not ($env.XDG_CONFIG_HOME? | default ($env.HOME | path join ".config") | path join "starship.toml" | path exists) {
            $env.STARSHIP_CONFIG = "/usr/share/kwick/shell/starship.toml"
        }
        $env.STARSHIP_SHELL = "nu"
        $env.PROMPT_INDICATOR = ""
        $env.PROMPT_COMMAND = {|| ^starship prompt $"--cmd-duration=($env.CMD_DURATION_MS)" $"--status=($env.LAST_EXIT_CODE)" $"--terminal-width=((term size).columns)" }
    }
    "minimal" => {
        $env.PROMPT_COMMAND = {|| $"\e[1;38;5;($env.KWICK_PS_HI)m(kwick-dir)\e[0m" }
        $env.PROMPT_INDICATOR = {||
            let c = (if $env.LAST_EXIT_CODE == 0 { $"38;5;($env.KWICK_PS_HI)" } else { "31" })
            let a = (if $env.KWICK_PS_UTF { "\u{276f}" } else { ">" })
            $" \e[($c)m($a)\e[0m "
        }
    }
    "powerline" => {
        $env.PROMPT_INDICATOR = ""
        $env.PROMPT_COMMAND = {||
            let hi = $env.KWICK_PS_HI
            let sep = (if $env.KWICK_PS_UTF { "\u{e0b0}" } else { "" })
            let br = (if $env.KWICK_PS_UTF { "\u{e0a0} " } else { "git:" })
            let bgu = (if (is-admin) { "41" } else { "48;5;238" })
            let fgsep = (if (is-admin) { "31" } else { "38;5;238" })
            let head = $"\e[($bgu);38;5;252m ($env.KWICK_USERHOST) \e[0;($fgsep);48;5;($hi)m($sep)\e[1;97;48;5;($hi)m (kwick-dir) "
            let b = (kwick-git-branch)
            let end = (if $env.LAST_EXIT_CODE == 0 { "" } else { "31" })
            if ($b | is-empty) {
                let e = (if $end == "" { $"38;5;($hi)" } else { $end })
                $"($head)\e[0;($e)m($sep)\e[0m "
            } else {
                let e = (if $end == "" { "38;5;236" } else { $end })
                $"($head)\e[0;38;5;($hi);48;5;236m($sep)\e[0;38;5;250;48;5;236m ($br)($b) \e[0;($e)m($sep)\e[0m "
            }
        }
    }
    _ => {
        $env.PROMPT_INDICATOR = {||
            let ch = (if (is-admin) { "#" } else { "$" })
            if $env.LAST_EXIT_CODE == 0 { $"\e[0m ($ch) " } else { $" \e[31m($ch)\e[0m " }
        }
        $env.PROMPT_COMMAND = {||
            let who = (if (is-admin) { "31" } else { "38;5;245" })
            $"\e[($who)m($env.KWICK_USERHOST)\e[0m \e[1;38;5;($env.KWICK_PS_HI)m(kwick-dir)\e[0m"
        }
    }
}
