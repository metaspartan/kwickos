use str
use path

if (and (not (has-env KWICK_ENV)) (path:is-regular /usr/lib/kwick/shell-env)) {
  for l [(/usr/lib/kwick/shell-env)] {
    var kv = [(str:split &max=2 = $l)]
    if (== (count $kv) 2) { set-env $kv[0] $kv[1] }
  }
}

fn -first {|f|
  if (path:is-regular $f) {
    var lines = [(str:split "\n" (slurp < $f))]
    if (> (count $lines) 0) { put (str:trim-space $lines[0]) } else { put '' }
  } else {
    put ''
  }
}

var cfg = $E:HOME/.config/kwick
if (has-env XDG_CONFIG_HOME) { set cfg = $E:XDG_CONFIG_HOME/kwick }
var style = ''
if (has-env KWICK_PROMPT) { set style = $E:KWICK_PROMPT }
if (eq $style '') { set style = (-first $cfg/prompt) }
if (eq $style '') { set style = (-first /etc/kwick/prompt) }
if (not (has-value [kwick minimal powerline starship] $style)) { set style = kwick }
if (and (eq $style starship) (not (has-external starship))) { set style = kwick }
var layout = (-first $cfg/layout)
var hi = '#0087ff'
if (eq $layout windows) { set hi = '#0087d7' } elif (eq $layout linux) { set hi = '#5f87ff' }
var utf = $false
if (and (not (has-value [linux dumb ''] $E:TERM)) (str:contains (str:to-lower $E:LC_ALL$E:LC_CTYPE$E:LANG) utf)) { set utf = $true }
var root = (eq (e:id -u) '0')
var userhost = (e:id -un)'@'(str:trim-space (slurp < /proc/sys/kernel/hostname))
var failed = $false
set edit:after-command = [$@edit:after-command {|m| set failed = (not-eq $m[error] $nil) }]

fn git-branch {
  var d = $pwd
  while $true {
    if (path:is-regular $d/.git/HEAD) {
      var h = (str:trim-space (slurp < $d/.git/HEAD))
      if (str:has-prefix $h 'ref: refs/heads/') { put (str:trim-prefix $h 'ref: refs/heads/') } else { put $h[0..7] }
      return
    }
    if (or (eq $d /) (eq $d '')) { put ''; return }
    set d = (path:dir $d)
  }
}

fn dir {
  if (eq $pwd $E:HOME) { put '~' } elif (eq $pwd /) { put / } else { path:base $pwd }
}

fn ll {|@a| e:ls -alF --color=auto $@a }
fn la {|@a| e:ls -A --color=auto $@a }
fn l {|@a| e:ls -CF --color=auto $@a }
fn ls {|@a| e:ls --color=auto $@a }
fn grep {|@a| e:grep --color=auto $@a }
edit:add-vars [&ll~=$ll~ &la~=$la~ &l~=$l~ &ls~=$ls~ &grep~=$grep~]

set edit:rprompt = { put '' }
if (eq $style starship) {
  if (and (not (has-env STARSHIP_CONFIG)) (not (path:is-regular $E:HOME/.config/starship.toml))) { set-env STARSHIP_CONFIG /usr/share/kwick/shell/starship.toml }
  set-env STARSHIP_SHELL elvish
  set edit:prompt = {
    var st = 0
    if $failed { set st = 1 }
    e:starship prompt --status=$st
  }
} elif (eq $style minimal) {
  set edit:prompt = {
    var a = '>'
    if $utf { set a = "❯" }
    var c = $hi
    if $failed { set c = red }
    styled (dir) bold 'fg-'$hi
    styled ' '$a' ' 'fg-'$c
  }
} elif (eq $style powerline) {
  set edit:prompt = {
    var sep = ''
    var br = 'git:'
    if $utf { set sep = ""; set br = " " }
    var bgu = '#444444'
    if $root { set bgu = '#cd0000' }
    styled ' '$userhost' ' 'bg-'$bgu 'fg-#d0d0d0'
    styled $sep 'fg-'$bgu 'bg-'$hi
    styled ' '(dir)' ' bold 'fg-#ffffff' 'bg-'$hi
    var b = (git-branch)
    var last = $hi
    if (not-eq $b '') {
      styled $sep 'fg-'$hi 'bg-#303030'
      styled ' '$br$b' ' 'fg-#bcbcbc' 'bg-#303030'
      set last = '#303030'
    }
    if $failed { set last = red }
    styled $sep' ' 'fg-'$last
  }
} else {
  set edit:prompt = {
    var ch = '$'
    if $root { set ch = '#' }
    if $root { styled $userhost red } else { styled $userhost 'fg-#8a8a8a' }
    put ' '
    styled (dir) bold 'fg-'$hi
    if $failed { styled ' '$ch' ' red } else { put ' '$ch' ' }
  }
}
