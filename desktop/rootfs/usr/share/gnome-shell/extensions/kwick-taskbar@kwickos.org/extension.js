import St from 'gi://St';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

function iconButton(name, icon, cb) {
    const button = new PanelMenu.Button(0.0, name, true);
    button.add_style_class_name('kwick-taskbar-button');
    button.add_child(new St.Icon({
        gicon: new Gio.ThemedIcon({names: icon}),
        icon_size: 24,
        y_align: Clutter.ActorAlign.CENTER,
        x_align: Clutter.ActorAlign.CENTER,
    }));
    button.connect('button-release-event', () => {
        cb();
        return Clutter.EVENT_STOP;
    });
    return button;
}

export default class KwickTaskbar extends Extension {
    enable() {
        Main.layoutManager.uiGroup.add_style_class_name('kwick-windows');
        if (Main.layoutManager._startingUp) {
            this._hadOverview = Main.sessionMode.hasOverview;
            Main.sessionMode.hasOverview = false;
            this._startupId = Main.layoutManager.connect('startup-complete', () => this._restoreOverview());
        }
        this._search = iconButton('kwick-search', ['kwick-search-taskbar-symbolic', 'edit-find-symbolic'], () => {
            if (GLib.find_program_in_path('kwick-spotlight')) {
                GLib.spawn_command_line_async('kwick-search');
                return;
            }
            Main.overview.show();
            const entry = Main.overview.searchEntry;
            if (entry)
                entry.grab_key_focus();
        });
        this._view = iconButton('kwick-taskview', ['kwick-taskview-symbolic', 'kwick-taskview'], () => Main.overview.toggle());
        Main.panel.addToStatusArea('kwick-search', this._search, 0, 'left');
        Main.panel.addToStatusArea('kwick-taskview', this._view, 1, 'left');

        const dateMenu = Main.panel.statusArea.dateMenu;
        this._clockLabel = dateMenu?._clockDisplay ?? null;
        this._wallClock = dateMenu?._clock ?? null;
        if (this._clockLabel) {
            dateMenu.add_style_class_name('kwick-clock');
            this._clockLabel.add_style_class_name('kwick-clock-label');
            this._clockLabel.clutter_text.single_line_mode = false;
            this._clockLabel.clutter_text.line_alignment = 1;
            this._textId = this._clockLabel.connect('notify::text', () => this._tick());
            this._tick();
        }
    }

    _tick() {
        const now = GLib.DateTime.new_now_local();
        const text = `${now.format('%-l:%M %p')}\n${now.format('%-m/%-d/%Y')}`;
        if (this._clockLabel.text !== text)
            this._clockLabel.text = text;
    }

    _restoreOverview() {
        if (!this._startupId)
            return;
        Main.layoutManager.disconnect(this._startupId);
        this._startupId = 0;
        Main.sessionMode.hasOverview = this._hadOverview;
    }

    disable() {
        Main.layoutManager.uiGroup.remove_style_class_name('kwick-windows');
        this._restoreOverview();
        if (this._textId) {
            this._clockLabel.disconnect(this._textId);
            this._textId = 0;
        }
        if (this._clockLabel) {
            Main.panel.statusArea.dateMenu?.remove_style_class_name('kwick-clock');
            this._clockLabel.remove_style_class_name('kwick-clock-label');
            this._clockLabel.clutter_text.single_line_mode = true;
            this._clockLabel.text = this._wallClock?.clock ?? '';
        }
        this._clockLabel = null;
        this._wallClock = null;
        this._search?.destroy();
        this._view?.destroy();
        this._search = this._view = null;
    }
}
