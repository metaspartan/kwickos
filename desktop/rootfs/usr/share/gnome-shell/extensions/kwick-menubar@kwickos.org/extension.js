import St from 'gi://St';
import Gio from 'gi://Gio';
import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

export default class KwickMenubar extends Extension {
    enable() {
        const panel = Main.panel;
        const activities = panel.statusArea.activities;
        this._hidden = [];
        if (activities) {
            const kids = activities.get_children();
            const box = kids.find(c => c instanceof St.BoxLayout) ?? null;
            const host = box ?? activities;
            for (const child of host.get_children()) {
                this._hidden.push([child, child.visible]);
                child.hide();
            }
            this._logo = new St.Icon({
                gicon: new Gio.ThemedIcon({name: 'kwickos-menubar'}),
                icon_size: 22,
                y_align: Clutter.ActorAlign.CENTER,
                x_align: Clutter.ActorAlign.CENTER,
                style: 'color: #ffffff;',
            });
            host.add_child(this._logo);
        }
        const clock = panel.statusArea.dateMenu;
        if (clock) {
            this._clock = clock.container;
            this._clockParent = this._clock.get_parent();
            this._clockParent.remove_child(this._clock);
            panel._rightBox.add_child(this._clock);
        }
    }

    disable() {
        const panel = Main.panel;
        if (this._logo) {
            this._logo.destroy();
            this._logo = null;
        }
        for (const [child, visible] of this._hidden ?? []) {
            if (visible)
                child.show();
        }
        this._hidden = null;
        if (this._clock) {
            panel._rightBox.remove_child(this._clock);
            this._clockParent.insert_child_at_index(this._clock, 0);
            this._clock = null;
            this._clockParent = null;
        }
    }
}
