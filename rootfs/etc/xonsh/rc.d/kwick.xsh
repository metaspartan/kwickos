import os as _kw_os
import re as _kw_re
import subprocess as _kw_sp


def _kw_import_env():
    if 'KWICK_ENV' in ${...} or not _kw_os.access('/usr/lib/kwick/shell-env', _kw_os.X_OK):
        return
    try:
        out = _kw_sp.run(['/usr/lib/kwick/shell-env'], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return
    for line in out.splitlines():
        k, sep, v = line.partition('=')
        if sep and _kw_re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', k):
            ${...}[k] = v


def _kw_first(path):
    try:
        with open(path) as f:
            return f.readline().strip()
    except OSError:
        return ''


def _kw_git_branch():
    d = _kw_os.getcwd()
    while True:
        h = _kw_os.path.join(d, '.git', 'HEAD')
        if _kw_os.path.isfile(h):
            s = _kw_first(h)
            return s[16:] if s.startswith('ref: refs/heads/') else s[:7]
        if d in ('/', ''):
            return ''
        d = _kw_os.path.dirname(d)


_KW_PAL = {'33': '#0087ff', '32': '#0087d7', '69': '#5f87ff', '238': '#444444', '236': '#303030', '252': '#d0d0d0', '250': '#bcbcbc', '245': '#8a8a8a'}
_KW_NAMED = {'31': 'RED', '41': 'BACKGROUND_RED', '97': 'WHITE'}


def _kw_sgr(codes):
    if not str(${...}.get('SHELL_TYPE', 'readline')).startswith('prompt'):
        return '\001\x1b[' + codes + 'm\002'
    out, bold, parts, i = '', False, codes.split(';'), 0
    while i < len(parts):
        p = parts[i]
        if p == '0':
            out += '{RESET}'
        elif p == '1':
            bold = True
        elif p in ('38', '48') and i + 2 < len(parts):
            col = _KW_PAL.get(parts[i + 2], '#808080')
            if p == '48':
                out += '{BACKGROUND_' + col + '}'
            else:
                out += '{' + ('BOLD_' if bold else '') + col + '}'
            i += 3
            continue
        elif p in _KW_NAMED:
            name = _KW_NAMED[p]
            out += '{' + ('BOLD_' if bold and not name.startswith('BACK') else '') + name + '}'
        i += 1
    return out


def _kw_failed():
    try:
        return int(${...}.get('LAST_RETURN_CODE', 0) or 0) != 0
    except (TypeError, ValueError):
        return False


def _kw_dir():
    p = _kw_os.getcwd()
    if p == _kw_os.path.expanduser('~'):
        return '~'
    return '/' if p == '/' else _kw_os.path.basename(p)


def _kw_setup():
    cfg = _kw_os.path.join(${...}.get('XDG_CONFIG_HOME', _kw_os.path.expanduser('~/.config')), 'kwick')
    style = ${...}.get('KWICK_PROMPT', '') or _kw_first(cfg + '/prompt') or _kw_first('/etc/kwick/prompt')
    if style not in ('kwick', 'minimal', 'powerline', 'starship'):
        style = 'kwick'
    import shutil
    if style == 'starship' and not shutil.which('starship'):
        style = 'kwick'
    layout = _kw_first(cfg + '/layout')
    hi = {'windows': '32', 'linux': '69'}.get(layout, '33')
    term = ${...}.get('TERM', '')
    loc = (${...}.get('LC_ALL', '') + ${...}.get('LC_CTYPE', '') + ${...}.get('LANG', '')).lower()
    utf = term not in ('linux', 'dumb', '') and 'utf' in loc
    root = _kw_os.geteuid() == 0
    ch = '#' if root else '$'
    who = '31' if root else '38;5;245'
    S = _kw_sgr
    $XONSH_SHOW_TRACEBACK = False
    $RIGHT_PROMPT = ''
    $TITLE = '{user}@{hostname}: {cwd}'
    $PROMPT_FIELDS['kw_dir'] = _kw_dir
    $PROMPT_FIELDS['kw_git'] = _kw_git_branch
    if style == 'starship':
        if 'STARSHIP_CONFIG' not in ${...} and not _kw_os.path.exists(_kw_os.path.expanduser('~/.config/starship.toml')):
            $STARSHIP_CONFIG = '/usr/share/kwick/shell/starship.toml'
        $STARSHIP_SHELL = 'xonsh'

        def _kw_starship():
            st = $LAST_RETURN_CODE if 'LAST_RETURN_CODE' in ${...} else 0
            return _kw_sp.run(['starship', 'prompt', '--status=' + str(st)], capture_output=True, text=True, env=${...}.detype()).stdout

        $PROMPT = _kw_starship
    elif style == 'minimal':
        arrow = '❯' if utf else '>'

        def _kw_min():
            c = '31' if _kw_failed() else '38;5;' + hi
            return S('1;38;5;' + hi) + '{kw_dir}' + S('0') + ' ' + S(c) + arrow + S('0') + ' '

        $PROMPT = _kw_min
    elif style == 'powerline':
        sep = '' if utf else ''
        br = ' ' if utf else 'git:'
        bgu, fgs = ('41', '31') if root else ('48;5;238', '38;5;238')

        def _kw_pl():
            b = _kw_git_branch()
            head = S(bgu + ';38;5;252') + ' {user}@{hostname} ' + S('0;' + fgs + ';48;5;' + hi) + sep + S('1;97;48;5;' + hi) + ' {kw_dir} '
            if b:
                end = '31' if _kw_failed() else '38;5;236'
                return head + S('0;38;5;' + hi + ';48;5;236') + sep + S('0;38;5;250;48;5;236') + ' ' + br + '{kw_git} ' + S('0;' + end) + sep + S('0') + ' '
            end = '31' if _kw_failed() else '38;5;' + hi
            return head + S('0;' + end) + sep + S('0') + ' '

        $PROMPT = _kw_pl
    else:
        def _kw_std():
            c = S('31') if _kw_failed() else ''
            return S(who) + '{user}@{hostname}' + S('0') + ' ' + S('1;38;5;' + hi) + '{kw_dir}' + S('0') + ' ' + c + ch + S('0') + ' '

        $PROMPT = _kw_std


_kw_import_env()
if ${...}.get('XONSH_INTERACTIVE', True):
    aliases['ll'] = 'ls -alF --color=auto'
    aliases['la'] = 'ls -A --color=auto'
    aliases['l'] = 'ls -CF --color=auto'
    aliases['ls'] = 'ls --color=auto'
    aliases['grep'] = 'grep --color=auto'
    aliases['..'] = 'cd ..'
    aliases['...'] = 'cd ../..'
    _kw_setup()
