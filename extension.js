// SPDX-License-Identifier: GPL-2.0-or-later
// Low-poly Waves: animated desktop background for GNOME Shell 50.
//
// How it stays cheap:
//  * A Shell.GLSLEffect (GPU fragment shader) on each monitor's existing
//    background actor. No extra process, window, texture or video decoding.
//  * Frames come from a plain GLib timeout at the configured fps and call
//    effect.queue_repaint(). For an offscreen effect that re-runs only the
//    shader pass and doesn't re-render the wallpaper underneath.
//  * While a monitor is covered by a maximized/fullscreen window (or the
//    screen is locked / overview open) nothing is repainted. When nothing
//    animates, the timer drops to a 2 Hz check.

import Cogl from 'gi://Cogl';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const EFFECT_NAME = 'lowpoly-waves';
const IDLE_CHECK_MS = 500;

const EXT_DIR = GLib.path_get_dirname(GLib.filename_from_uri(import.meta.url)[0]);
// style -> shader file + palette uniform
const STYLES = {
    aubergine: {shader: 'lowpoly', palette: 1},
    lowpoly: {shader: 'lowpoly', palette: 0},
};
const DEFAULT_STYLE = 'aubergine';
const UNIFORMS = ['u_time', 'u_aspect', 'u_rows', 'u_amp', 'u_seed', 'u_px', 'u_palette'];
const SHADER_CODE = 'cogl_color_out = vec4(background(cogl_tex_coord_in[0].xy), 1.0);\n';

// Shell.GLSLEffect caches its pipeline per GType, so every shader file needs
// its own class. Registered lazily, once per shell session (survives disable/enable).
const effectClasses = new Map();

function effectClassFor(shader) {
    if (effectClasses.has(shader))
        return effectClasses.get(shader);

    const declarations = new TextDecoder().decode(GLib.file_get_contents(
        GLib.build_filenamev([EXT_DIR, 'shaders', `${shader}.glsl`]))[1]);

    const cls = GObject.registerClass({
        GTypeName: `LowpolyWavesEffect_${shader}`,
    }, class extends Shell.GLSLEffect {
        _init(params) {
            super._init(params);
            this._loc = {};
            for (const name of UNIFORMS)
                this._loc[name] = this.get_uniform_location(name);
        }

        vfunc_build_pipeline() {
            // `true` = replace the actor's output entirely with the shader colour.
            this.add_glsl_snippet(Cogl.SnippetHook.FRAGMENT,
                declarations, SHADER_CODE, true);
        }

        setUniform(name, value) {
            const loc = this._loc[name];
            if (loc >= 0) // unused uniforms are optimised out of the shader
                this.set_uniform_float(loc, 1, [value]);
        }
    });
    effectClasses.set(shader, cls);
    return cls;
}

function isMaximized(win) {
    if (typeof win.is_maximized === 'function')
        return win.is_maximized();
    return win.get_maximized?.() === Meta.MaximizeFlags.BOTH;
}

export default class LowpolyWavesExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._time = 0;
        this._lastUs = GLib.get_monotonic_time();
        this._timerId = 0;
        this._interval = 0;
        this._actors = new Set();

        this._settingsId = this._settings.connect('changed', () => this._applySettings());
        this._monitorsId = Main.layoutManager.connect('monitors-changed',
            () => this._restartTimer(IDLE_CHECK_MS));

        this._applySettings();
    }

    disable() {
        if (this._timerId)
            GLib.source_remove(this._timerId);
        this._timerId = 0;
        this._settings.disconnect(this._settingsId);
        Main.layoutManager.disconnect(this._monitorsId);
        for (const actor of this._actors) {
            try {
                actor.disconnectObject(this);
                actor.remove_effect_by_name(EFFECT_NAME);
            } catch {
                // actor already destroyed
            }
        }
        this._actors = null;
        this._settings = null;
    }

    _applySettings() {
        const s = this._settings;
        this._frameMs = Math.round(1000 / s.get_int('fps'));
        this._speed = s.get_double('speed');
        this._rows = s.get_double('rows');
        this._drift = Math.min(s.get_double('drift'), 0.08); // shader bound
        this._pauseWhenCovered = s.get_boolean('pause-when-covered');
        const style = STYLES[s.get_string('style')] ?? STYLES[DEFAULT_STYLE];
        this._effectClass = effectClassFor(style.shader);
        this._palette = style.palette;
        this._forceRepaint = true;
        this._restartTimer(this._frameMs);
    }

    _restartTimer(ms) {
        if (this._timerId)
            GLib.source_remove(this._timerId);
        this._interval = ms;
        this._timerId = GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, ms, () => this._tick());
        GLib.Source.set_name_by_id(this._timerId, '[lowpoly-waves] tick');
    }

    // Make sure every current background actor carries our effect. Background
    // actors are replaced on wallpaper or monitor changes, so this runs on
    // every tick; it is a loop over one entry per monitor.
    _syncEffects() {
        const effects = [];
        for (const mgr of Main.layoutManager._bgManagers ?? []) {
            const actor = mgr.backgroundActor;
            if (!actor)
                continue;
            let effect = actor.get_effect(EFFECT_NAME);
            if (effect && !(effect instanceof this._effectClass)) {
                actor.remove_effect(effect); // style changed
                effect = null;
            }
            if (!effect) {
                effect = new this._effectClass();
                actor.add_effect_with_name(EFFECT_NAME, effect);
                if (!this._actors.has(actor)) {
                    this._actors.add(actor);
                    actor.connectObject('destroy', () => this._actors?.delete(actor), this);
                }
                effect._configured = null;
            }
            const monitor = actor.monitor ?? 0;
            const height = actor.height > 0 ? actor.height : 1080;
            const aspect = actor.width > 0 ? actor.width / height : 16 / 9;
            const key = `${aspect}|${height}|${this._rows}|${this._drift}|${monitor}|${this._palette}`;
            if (effect._configured !== key) {
                effect.setUniform('u_aspect', aspect);
                effect.setUniform('u_rows', this._rows);
                effect.setUniform('u_amp', this._drift);
                effect.setUniform('u_px', 1 / height);
                effect.setUniform('u_palette', this._palette);
                effect.setUniform('u_seed', monitor * 31.7);
                effect._configured = key;
                effect._dirty = true;
            }
            effects.push({effect, monitor});
        }
        return effects;
    }

    _coveredMonitors() {
        const covered = new Set();
        if (!this._pauseWhenCovered)
            return covered;
        const ws = global.workspace_manager.get_active_workspace();
        for (const windowActor of global.get_window_actors()) {
            const win = windowActor.meta_window;
            if (!win || win.minimized || !win.showing_on_its_workspace() ||
                !win.located_on_workspace(ws) ||
                win.get_window_type() !== Meta.WindowType.NORMAL)
                continue;
            const m = win.get_monitor();
            if (m < 0 || covered.has(m))
                continue;
            if (win.is_fullscreen() || isMaximized(win)) {
                covered.add(m);
                continue;
            }
            // Tiled/resized windows that still fill the whole work area.
            const r = win.get_frame_rect();
            const wa = ws.get_work_area_for_monitor(m);
            if (r.x <= wa.x && r.y <= wa.y &&
                r.x + r.width >= wa.x + wa.width && r.y + r.height >= wa.y + wa.height)
                covered.add(m);
        }
        return covered;
    }

    _globallyPaused() {
        return Main.sessionMode.isLocked ||
            Main.screenShield?.locked ||
            Main.overview.visible;
    }

    _tick() {
        const nowUs = GLib.get_monotonic_time();
        const dt = Math.min((nowUs - this._lastUs) / 1e6, 0.1); // no jumps after pauses
        this._lastUs = nowUs;

        const effects = this._syncEffects();
        const paused = this._globallyPaused();
        const covered = paused ? null : this._coveredMonitors();

        let animating = false;
        if (!paused) {
            const active = effects.filter(e => !covered.has(e.monitor));
            if (active.length > 0) {
                animating = true;
                this._time += dt * this._speed;
            }
            for (const {effect, monitor} of effects) {
                if (!covered.has(monitor) || effect._dirty || this._forceRepaint) {
                    effect.setUniform('u_time', this._time);
                    effect.queue_repaint();
                    effect._dirty = false;
                }
            }
            this._forceRepaint = false;
        }

        const wanted = animating ? this._frameMs : IDLE_CHECK_MS;
        if (wanted !== this._interval) {
            this._timerId = 0;
            this._restartTimer(wanted);
            return GLib.SOURCE_REMOVE;
        }
        return GLib.SOURCE_CONTINUE;
    }
}
