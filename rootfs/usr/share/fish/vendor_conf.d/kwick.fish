if not set -q KWICK_ENV; and test -x /usr/lib/kwick/shell-env
    for l in (/usr/lib/kwick/shell-env)
        set -l kv (string split -m 1 = -- $l)
        if test "$kv[1]" = PATH
            set -gx PATH (string split : -- $kv[2])
        else
            set -gx $kv[1] $kv[2]
        end
    end
end

status is-interactive; or exit 0

set -g fish_greeting
set -l kwick_cfg (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo $HOME/.config)/kwick
set -g kwick_layout macos
test -r $kwick_cfg/layout; and read kwick_layout <$kwick_cfg/layout
set -g kwick_style
set -q KWICK_PROMPT; and set kwick_style $KWICK_PROMPT
test -z "$kwick_style"; and test -r $kwick_cfg/prompt; and read kwick_style <$kwick_cfg/prompt
test -z "$kwick_style"; and test -r /etc/kwick/prompt; and read kwick_style </etc/kwick/prompt
contains -- $kwick_style kwick minimal powerline starship; or set kwick_style kwick
switch $kwick_layout
    case windows
        set -g kwick_hi 0087d7
    case linux
        set -g kwick_hi 5f87ff
    case '*'
        set -g kwick_hi 0087ff
end
set -g kwick_utf
switch "$TERM"
    case linux 'vt*' dumb ''
    case '*'
        string match -qri 'utf-?8' -- "$LC_ALL$LC_CTYPE$LANG"; and set kwick_utf 1
end

alias ls 'ls --color=auto'
alias ll 'ls -alF'
alias la 'ls -A'
alias l 'ls -CF'
alias grep 'grep --color=auto'
alias .. 'cd ..'
alias ... 'cd ../..'

function kwick_git_branch
    set -l d $PWD
    while true
        if test -f $d/.git/HEAD
            read -l h <$d/.git/HEAD
            if string match -q 'ref: refs/heads/*' -- $h
                string replace 'ref: refs/heads/' '' -- $h
            else
                string sub -l 7 -- $h
            end
            return 0
        end
        test -z "$d" -o "$d" = /; and return 1
        set d (string replace -r '/[^/]*$' '' -- $d)
    end
end

function kwick_dir
    if test "$PWD" = "$HOME"
        echo '~'
    else if test "$PWD" = /
        echo /
    else
        string replace -r '.*/' '' -- $PWD
    end
end

if test "$kwick_style" = starship; and command -q starship
    if not set -q STARSHIP_CONFIG; and not test -e (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo $HOME/.config)/starship.toml
        set -gx STARSHIP_CONFIG /usr/share/kwick/shell/starship.toml
    end
    starship init fish | source
    exit 0
end
test "$kwick_style" = starship; and set kwick_style kwick

function fish_title
    echo (whoami)@(prompt_hostname): (prompt_pwd)
end

switch $kwick_style
    case minimal
        function fish_prompt
            set -l st $status
            set -l arrow '>'
            test -n "$kwick_utf"; and set arrow ❯
            set_color --bold $kwick_hi
            printf '%s' (kwick_dir)
            set_color normal
            test $st -eq 0; and set_color $kwick_hi; or set_color red
            printf ' %s ' $arrow
            set_color normal
        end
    case powerline
        function fish_prompt
            set -l st $status
            set -l sep ''
            set -l br 'git:'
            if test -n "$kwick_utf"
                set sep 
                set br ' '
            end
            set -l bgu 444444
            fish_is_root_user; and set bgu red
            set_color -b $bgu d0d0d0
            printf ' %s@%s ' (whoami) (prompt_hostname)
            set_color -b $kwick_hi $bgu
            printf '%s' $sep
            set_color -o -b $kwick_hi white
            printf ' %s ' (kwick_dir)
            set_color normal
            set -l b (kwick_git_branch)
            set -l last $kwick_hi
            if test -n "$b"
                set_color -b 303030 $kwick_hi
                printf '%s' $sep
                set_color -b 303030 bcbcbc
                printf ' %s%s ' $br $b
                set last 303030
            end
            set_color normal
            test $st -eq 0; and set_color $last; or set_color red
            printf '%s ' $sep
            set_color normal
        end
    case '*'
        function fish_prompt
            set -l st $status
            set -l ch '$'
            fish_is_root_user; and set ch '#'
            if fish_is_root_user
                set_color red
            else
                set_color 8a8a8a
            end
            printf '%s@%s ' (whoami) (prompt_hostname)
            set_color --bold $kwick_hi
            printf '%s' (kwick_dir)
            set_color normal
            test $st -eq 0; or set_color red
            printf ' %s ' $ch
            set_color normal
        end
end
