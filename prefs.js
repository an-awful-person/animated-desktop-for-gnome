// SPDX-License-Identifier: GPL-2.0-or-later
import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

export default class LowpolyWavesPrefs extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        const page = new Adw.PreferencesPage();
        const group = new Adw.PreferencesGroup({
            title: 'Low-poly Waves',
            description: 'Changes apply immediately.',
        });
        page.add(group);

        const styles = [['aubergine', 'Aubergine sea (24.04 colours)'], ['lowpoly', 'Classic (purple to orange)']];
        const styleRow = new Adw.ComboRow({
            title: 'Style',
            model: Gtk.StringList.new(styles.map(s => s[1])),
            selected: Math.max(0, styles.findIndex(s => s[0] === settings.get_string('style'))),
        });
        styleRow.connect('notify::selected', () =>
            settings.set_string('style', styles[styleRow.selected][0]));
        group.add(styleRow);

        const spin = (key, title, subtitle, lower, upper, step, digits) => {
            const row = new Adw.SpinRow({
                title, subtitle, digits,
                adjustment: new Gtk.Adjustment({lower, upper, step_increment: step}),
            });
            settings.bind(key, row, 'value', Gio.SettingsBindFlags.DEFAULT);
            group.add(row);
        };
        spin('fps', 'Frame rate', 'Maximum redraws per second', 1, 60, 1, 0);
        spin('speed', 'Wave speed', 'Multiplier', 0.05, 5, 0.05, 2);
        spin('rows', 'Triangle size', 'Rows of triangles; fewer = bigger. Wave size is fixed', 2, 30, 0.5, 1);
        spin('drift', 'Drift', 'Sideways wobble of the triangle corners', 0, 0.08, 0.01, 2);

        const pause = new Adw.SwitchRow({
            title: 'Pause when covered',
            subtitle: 'Stop animating a monitor behind maximized or fullscreen windows',
        });
        settings.bind('pause-when-covered', pause, 'active', Gio.SettingsBindFlags.DEFAULT);
        group.add(pause);

        window.add(page);
    }
}
