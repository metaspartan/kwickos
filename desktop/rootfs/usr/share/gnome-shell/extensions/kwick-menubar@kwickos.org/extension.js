import St from 'gi://St';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
import Shell from 'gi://Shell';
import Meta from 'gi://Meta';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const FILES = 'org.gnome.Nautilus.desktop';
const LOGO = '/usr/share/icons/hicolor/scalable/apps/kwickos-menubar.svg';

function clockText(text) {
    return text
        .replace(/[\s\u2002\u2003\u2009\u202f]+(?=\d{1,2}[:\u2236]\d)/, '  ')
        .replace(/\u2236/g, ':')
        .replace(/(\d)[\u2009\u202f](AM|PM)/, '$1 $2');
}

function menuButton(name, text, bold) {
    const button = new PanelMenu.Button(0.0, name, false);
    button.add_style_class_name('kwick-menu-button');
    const label = new St.Label({
        text,
        y_align: Clutter.ActorAlign.CENTER,
        style_class: bold ? 'kwick-app-name' : 'kwick-menu-title',
    });
    button.add_child(label);
    button._kwickLabel = label;
    return button;
}

export default class KwickMenubar extends Extension {
    enable() {
        const panel = Main.panel;
        const activities = panel.statusArea.activities;
        this._hidden = [];
        Main.layoutManager.uiGroup.add_style_class_name('kwick-macos');
        if (activities) {
            const kids = activities.get_children();
            const box = kids.find(c => c instanceof St.BoxLayout) ?? null;
            const host = box ?? activities;
            for (const child of host.get_children()) {
                this._hidden.push([child, child.visible]);
                child.hide();
            }
            this._logo = new St.Icon({
                gicon: Gio.File.new_for_path(LOGO).query_exists(null)
                    ? new Gio.FileIcon({file: Gio.File.new_for_path(LOGO)})
                    : new Gio.ThemedIcon({name: 'kwickos-menubar'}),
                icon_size: 22,
                y_align: Clutter.ActorAlign.CENTER,
                x_align: Clutter.ActorAlign.CENTER,
                style_class: 'kwick-logo',
            });
            host.add_child(this._logo);
        }
        const clock = panel.statusArea.dateMenu;
        if (clock) {
            this._clock = clock.container;
            this._clockParent = this._clock.get_parent();
            this._clockParent.remove_child(this._clock);
            panel._rightBox.add_child(this._clock);
            this._clockLabel = clock._clockDisplay ?? null;
            if (this._clockLabel) {
                const fix = () => {
                    const t = clockText(this._clockLabel.text ?? '');
                    if (t !== this._clockLabel.text)
                        this._clockLabel.text = t;
                };
                this._clockId = this._clockLabel.connect('notify::text', fix);
                fix();
            }
        }

        this._tracker = Shell.WindowTracker.get_default();
        this._appButton = menuButton('kwick-app-menu', 'Files', true);
        this._windowButton = menuButton('kwick-window-menu', 'Window', false);
        this._helpButton = menuButton('kwick-help-menu', 'Help', false);
        this._buildAppMenu();
        this._buildWindowMenu();
        this._buildHelpMenu();
        panel.addToStatusArea('kwick-app-menu', this._appButton, 1, 'left');
        panel.addToStatusArea('kwick-window-menu', this._windowButton, 2, 'left');
        panel.addToStatusArea('kwick-help-menu', this._helpButton, 3, 'left');
        this._focusId = this._tracker.connect('notify::focus-app', () => this._sync());
        this._sync();
        this._powerTries = 0;
        this._powerSource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 250, () => this._hookPower());
    }

    _hookPower() {
        const sys = Main.panel.statusArea.quickSettings?._system;
        if (!sys?._indicator) {
            this._powerTries++;
            if (this._powerTries < 40)
                return GLib.SOURCE_CONTINUE;
            this._powerSource = 0;
            return GLib.SOURCE_REMOVE;
        }
        this._powerSource = 0;
        this._power = sys;
        const icon = new Gio.FileIcon({file: this.dir.get_child('power.svg')});
        const fix = () => {
            if (sys._indicator.icon_name === 'system-shutdown-symbolic')
                sys._indicator.gicon = icon;
        };
        this._powerId = sys._indicator.connect('notify::icon-name', fix);
        fix();
        return GLib.SOURCE_REMOVE;
    }

    _app() {
        return this._tracker.focus_app ?? Shell.AppSystem.get_default().lookup_app(FILES);
    }

    _sync() {
        const app = this._tracker.focus_app;
        this._appButton._kwickLabel.text = app ? app.get_name() : 'Files';
    }

    _item(menu, text, cb) {
        const item = new PopupMenu.PopupMenuItem(text);
        item.connect('activate', cb);
        menu.addMenuItem(item);
        return item;
    }

    _buildAppMenu() {
        const menu = this._appButton.menu;
        this._item(menu, 'New Window', () => {
            const app = this._app();
            if (app)
                app.open_new_window(-1);
        });
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._item(menu, 'Hide', () => {
            const app = this._tracker.focus_app;
            if (app)
                app.get_windows().forEach(w => w.minimize());
        });
        this._item(menu, 'Show All', () => {
            Main.overview.show();
        });
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._item(menu, 'Quit', () => {
            const app = this._tracker.focus_app;
            if (app)
                app.request_quit();
        });
    }

    _buildWindowMenu() {
        const menu = this._windowButton.menu;
        const win = () => global.display.get_focus_window();
        this._item(menu, 'Minimize', () => win()?.minimize());
        this._item(menu, 'Zoom', () => {
            const w = win();
            if (!w)
                return;
            if (w.get_maximized() === Meta.MaximizeFlags.BOTH)
                w.unmaximize(Meta.MaximizeFlags.BOTH);
            else
                w.maximize(Meta.MaximizeFlags.BOTH);
        });
        this._item(menu, 'Close Window', () => win()?.delete(global.get_current_time()));
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._item(menu, 'Bring All to Front', () => {
            const app = this._tracker.focus_app;
            if (app)
                app.activate();
        });
    }

    _buildHelpMenu() {
        const menu = this._helpButton.menu;
        this._item(menu, 'Keyboard Shortcuts', () => {
            try {
                Gio.Subprocess.new(['kwick-keys'], Gio.SubprocessFlags.NONE);
            } catch (e) {
                logError(e);
            }
        });
        this._item(menu, 'KwickOS Settings', () => {
            const app = Shell.AppSystem.get_default().lookup_app('kwick-settings.desktop');
            if (app)
                app.activate();
        });
    }

    disable() {
        const panel = Main.panel;
        Main.layoutManager.uiGroup.remove_style_class_name('kwick-macos');
        if (this._focusId) {
            this._tracker.disconnect(this._focusId);
            this._focusId = 0;
        }
        for (const b of [this._appButton, this._windowButton, this._helpButton])
            b?.destroy();
        this._appButton = this._windowButton = this._helpButton = null;
        this._tracker = null;
        if (this._logo) {
            this._logo.destroy();
            this._logo = null;
        }
        for (const [child, visible] of this._hidden ?? []) {
            if (visible)
                child.show();
        }
        this._hidden = null;
        if (this._powerSource) {
            GLib.source_remove(this._powerSource);
            this._powerSource = 0;
        }
        if (this._powerId) {
            this._power._indicator.disconnect(this._powerId);
            this._powerId = 0;
            this._power._sync();
            this._power = null;
        }
        if (this._clockId) {
            this._clockLabel.disconnect(this._clockId);
            this._clockId = 0;
            this._clockLabel = null;
        }
        if (this._clock) {
            panel._rightBox.remove_child(this._clock);
            this._clockParent.insert_child_at_index(this._clock, 0);
            this._clock = null;
            this._clockParent = null;
        }
    }
}
