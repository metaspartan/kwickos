import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const LIMIT = 200;
const MAX_BYTES = 1048576;

export default class KwickClipboard extends Extension {
    enable() {
        this._dir = GLib.build_filenamev([GLib.get_user_data_dir(), 'kwick', 'clipboard', 'history']);
        GLib.mkdir_with_parents(this._dir, 0o700);
        this._selection = global.display.get_selection();
        this._ownerId = this._selection.connect('owner-changed', (selection, type) => {
            if (type === Meta.SelectionType.SELECTION_CLIPBOARD)
                this._read();
        });
        this._keys = new Map();
        this._grabAll();
        this._keysFile = Gio.File.new_for_path(GLib.build_filenamev([GLib.get_user_config_dir(), 'kwick', 'keys', 'gnome.json']));
        this._monitor = this._keysFile.monitor_file(Gio.FileMonitorFlags.NONE, null);
        this._monitorId = this._monitor.connect('changed', (monitor, file, other, event) => {
            if (event === Gio.FileMonitorEvent.CHANGES_DONE_HINT || event === Gio.FileMonitorEvent.CREATED || event === Gio.FileMonitorEvent.DELETED) {
                this._ungrabAll();
                this._grabAll();
            }
        });
        this._acceleratorId = global.display.connect('accelerator-activated', (display, action) => {
            const argv = this._keys.get(action);
            if (argv && GLib.find_program_in_path(argv[0]))
                Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE);
        });
    }

    disable() {
        if (this._ownerId)
            this._selection.disconnect(this._ownerId);
        this._ownerId = 0;
        this._selection = null;
        if (this._monitorId)
            this._monitor.disconnect(this._monitorId);
        this._monitorId = 0;
        this._monitor?.cancel();
        this._monitor = null;
        this._keysFile = null;
        if (this._acceleratorId)
            global.display.disconnect(this._acceleratorId);
        this._acceleratorId = 0;
        this._ungrabAll();
        this._keys = null;
    }

    _ungrabAll() {
        for (const action of this._keys.keys()) {
            global.display.ungrab_accelerator(action);
            Main.wm.allowKeybinding(Meta.external_binding_name_for_action(action), Shell.ActionMode.NONE);
        }
        this._keys.clear();
    }

    _grabAll() {
        const chords = {clipboard: ['<Super>v'], capture: ['<Super><Shift>s']};
        try {
            const path = GLib.build_filenamev([GLib.get_user_config_dir(), 'kwick', 'keys', 'gnome.json']);
            const [ok, bytes] = GLib.file_get_contents(path);
            if (ok) {
                const saved = JSON.parse(new TextDecoder().decode(bytes));
                for (const name of Object.keys(chords)) {
                    if (Array.isArray(saved[name]))
                        chords[name] = saved[name].filter(a => typeof a === 'string');
                }
            }
        } catch (e) {
        }
        for (const accelerator of chords.clipboard)
            this._grab(accelerator, ['kwick-search', '--mode', 'clipboard']);
        for (const accelerator of chords.capture)
            this._grab(accelerator, ['kwick-capture']);
    }

    _grab(accelerator, argv) {
        if (!GLib.find_program_in_path(argv[0]))
            return;
        const action = global.display.grab_accelerator(accelerator, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT);
        if (action === Meta.KeyBindingAction.NONE)
            return;
        Main.wm.allowKeybinding(Meta.external_binding_name_for_action(action), Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW);
        this._keys.set(action, argv);
    }

    _read() {
        const mimes = this._selection.get_mimetypes(Meta.SelectionType.SELECTION_CLIPBOARD);
        if (mimes.includes('x-kde-passwordManagerHint') || mimes.includes('x-kwick-secret'))
            return;
        St.Clipboard.get_default().get_text(St.ClipboardType.CLIPBOARD, (clipboard, text) => {
            if (text && text.trim() !== '')
                this._store(text);
        });
    }

    _entries() {
        const out = [];
        const dir = Gio.File.new_for_path(this._dir);
        const iter = dir.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
        let info;
        while ((info = iter.next_file(null)) !== null) {
            const name = info.get_name();
            if (name.endsWith('.txt'))
                out.push(name);
        }
        iter.close(null);
        return out.sort().reverse();
    }

    _store(text) {
        try {
            const bytes = new TextEncoder().encode(text).slice(0, MAX_BYTES);
            const value = new TextDecoder().decode(bytes);
            const names = this._entries();
            for (const name of names) {
                const path = GLib.build_filenamev([this._dir, name]);
                const [ok, contents] = GLib.file_get_contents(path);
                if (ok && new TextDecoder().decode(contents) === value)
                    GLib.unlink(path);
            }
            const stamp = `${Math.floor(GLib.get_real_time() / 1000)}`.padStart(13, '0');
            GLib.file_set_contents(GLib.build_filenamev([this._dir, `${stamp}.txt`]), bytes);
            for (const name of this._entries().slice(LIMIT))
                GLib.unlink(GLib.build_filenamev([this._dir, name]));
        } catch (e) {
            console.warn(`kwick-clipboard: ${e.message}`);
        }
    }
}
