import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const BUS_NAME = 'org.kwickos.kwick-spotlight';
const OBJECT_PATH = '/org/kwickos/kwick_spotlight';
const APP_ID = 'kwick-search';
const CAPTURE_LIMIT = 3000;
const HANDOFF = 400;
const MODIFIERS = Clutter.ModifierType.CONTROL_MASK | Clutter.ModifierType.MOD1_MASK | Clutter.ModifierType.SUPER_MASK | Clutter.ModifierType.MOD4_MASK;

export default class KwickSpotlight extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._text = '';
        this._submit = false;
        this._cancel = false;
        this._grab = null;
        this._window = null;
        this._timeout = 0;
        this._sending = false;
        this._strayId = 0;
        this._strayTimeout = 0;
        this._strayWindow = null;
        Main.wm.addKeybinding('toggle', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW, () => this._toggle());
        this._createdId = global.display.connect('window-created', (display, window) => this._windowCreated(window));
    }

    disable() {
        Main.wm.removeKeybinding('toggle');
        global.display.disconnect(this._createdId);
        this._release();
        this._endHandoff();
        this._settings = null;
    }

    _isSpotlight(window) {
        return !!window && window.get_wm_class() === APP_ID;
    }

    _command(args, callback) {
        Gio.DBus.session.call(BUS_NAME, OBJECT_PATH, 'org.kde.KDBusService', 'CommandLine',
            new GLib.Variant('(assa{sv})', [['kwick-spotlight', ...args], GLib.get_home_dir(), {}]),
            null, Gio.DBusCallFlags.NO_AUTO_START, 3000, null, (connection, result) => {
                let ok = true;
                try {
                    connection.call_finish(result);
                } catch (e) {
                    ok = false;
                }
                callback?.(ok);
            });
    }

    _toggle() {
        if (this._grab)
            return;
        this._endHandoff();
        if (!this._isSpotlight(global.display.focus_window)) {
            if (Main.overview.visible)
                Main.overview.hide();
            this._capture();
        }
        this._command([], ok => {
            if (ok)
                return;
            try {
                GLib.spawn_async(null, ['kwick-spotlight'], null, GLib.SpawnFlags.SEARCH_PATH, null);
            } catch (e) {
                this._release();
            }
        });
    }

    _capture() {
        const grab = global.stage.grab(global.stage);
        if (!(grab.get_seat_state() & Clutter.GrabState.KEYBOARD)) {
            grab.dismiss();
            return;
        }
        this._grab = grab;
        this._text = '';
        this._submit = false;
        this._cancel = false;
        this._window = null;
        this._pressId = global.stage.connect('key-press-event', (actor, event) => this._record(event));
        this._releaseId = global.stage.connect('key-release-event', () => Clutter.EVENT_STOP);
        this._timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, CAPTURE_LIMIT, () => {
            this._timeout = 0;
            this._release();
            return GLib.SOURCE_REMOVE;
        });
    }

    _record(event) {
        if (this._submit || this._cancel)
            return Clutter.EVENT_STOP;
        const key = event.get_key_symbol();
        if (key === Clutter.KEY_Escape) {
            this._cancel = true;
        } else if (key === Clutter.KEY_Return || key === Clutter.KEY_KP_Enter || key === Clutter.KEY_ISO_Enter) {
            this._submit = true;
        } else if (key === Clutter.KEY_BackSpace) {
            this._text = [...this._text].slice(0, -1).join('');
        } else {
            this._text += this._textOf(event);
        }
        this._flush();
        return Clutter.EVENT_STOP;
    }

    _textOf(event) {
        if (event.get_state() & MODIFIERS)
            return '';
        const code = event.get_key_unicode();
        const text = typeof code === 'number' ? (code > 31 ? String.fromCodePoint(code) : '') : (code ?? '');
        return text.length > 0 && text.codePointAt(0) > 31 && text.codePointAt(0) !== 127 ? text : '';
    }

    _windowCreated(window) {
        if (!this._grab)
            return;
        const id = window.connect('shown', () => {
            window.disconnect(id);
            if (!this._grab || !this._isSpotlight(window))
                return;
            this._window = window;
            this._flush();
        });
    }

    _flush() {
        if (!this._grab || !this._window || this._sending)
            return;
        if (this._cancel) {
            this._command(['--hide']);
            this._release();
            return;
        }
        const args = [];
        if (this._text.length > 0)
            args.push(`--append=${this._text}`);
        if (this._submit)
            args.push('--submit');
        if (args.length === 0) {
            this._focus();
            return;
        }
        this._text = '';
        const submit = this._submit;
        this._sending = true;
        this._command(args, () => {
            this._sending = false;
            if (submit) {
                this._release();
                return;
            }
            if (this._text.length > 0 || this._submit || this._cancel)
                this._flush();
            else
                this._focus();
        });
    }

    _focus() {
        const window = this._window;
        if (window)
            Main.activateWindow(window, global.display.get_current_time_roundtrip());
        this._release();
        if (window)
            this._handoff(window);
    }

    _handoff(window) {
        this._endHandoff();
        this._strayWindow = window;
        this._unmanagedId = window.connect('unmanaging', () => this._endHandoff());
        this._strayId = global.stage.connect('captured-event', (actor, event) => {
            const type = event.type();
            if (type === Clutter.EventType.KEY_RELEASE)
                return Clutter.EVENT_STOP;
            if (type !== Clutter.EventType.KEY_PRESS)
                return Clutter.EVENT_PROPAGATE;
            const key = event.get_key_symbol();
            if (key === Clutter.KEY_Escape) {
                this._endHandoff();
                this._command(['--hide']);
            } else if (key === Clutter.KEY_Return || key === Clutter.KEY_KP_Enter || key === Clutter.KEY_ISO_Enter) {
                this._endHandoff();
                this._command(['--submit']);
            } else {
                const text = this._textOf(event);
                if (text.length > 0)
                    this._command([`--append=${text}`]);
            }
            return Clutter.EVENT_STOP;
        });
        this._strayTimeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, HANDOFF, () => {
            this._strayTimeout = 0;
            this._endHandoff();
            return GLib.SOURCE_REMOVE;
        });
    }

    _endHandoff() {
        if (this._strayTimeout) {
            GLib.source_remove(this._strayTimeout);
            this._strayTimeout = 0;
        }
        if (this._strayId) {
            global.stage.disconnect(this._strayId);
            this._strayId = 0;
        }
        if (this._strayWindow) {
            this._strayWindow.disconnect(this._unmanagedId);
            this._strayWindow = null;
        }
    }

    _release() {
        if (this._timeout) {
            GLib.source_remove(this._timeout);
            this._timeout = 0;
        }
        if (!this._grab)
            return;
        const grab = this._grab;
        this._grab = null;
        this._window = null;
        global.stage.disconnect(this._pressId);
        global.stage.disconnect(this._releaseId);
        grab.dismiss();
    }
}
