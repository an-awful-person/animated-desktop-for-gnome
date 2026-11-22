#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build preview.html: runs the shaders in shaders/ in WebGL so the look can be
tuned without logging out of GNOME. Open the output in a browser.
Query params: ?style=aubergine|lowpoly  ?t=<seconds> freezes time
              ?speed=1 ?rows=2.5 ?amp=0.08 override tunables."""
import json
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
shaders = {p.stem: p.read_text() for p in sorted((root / "shaders").glob("*.glsl"))}

html = """<!doctype html>
<meta charset="utf-8"><title>Animated wallpaper preview</title>
<style>html,body{margin:0;height:100%;background:#000;color:#fff;font:16px monospace;overflow:hidden}canvas{width:100%;height:100%;display:block}</style>
<canvas id="c"></canvas>
<script>
const SHADERS = @@SHADERS@@;
const q = new URLSearchParams(location.search);
const style = q.get('style') ?? 'aubergine';
const STYLE = {aubergine: ['lowpoly', 1], lowpoly: ['lowpoly', 0]}[style];
const c = document.getElementById('c');
const gl = c.getContext('webgl', {preserveDrawingBuffer: true});
if (!gl) { document.body.innerText = 'NO WEBGL'; throw 0; }
const fs = `precision highp float;
varying vec2 vUv;
${SHADERS[STYLE[0]]}
void main() { gl_FragColor = vec4(background(vUv), 1.0); }`;
const vs = `attribute vec2 p; varying vec2 vUv;
void main() { vUv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5); gl_Position = vec4(p, 0.0, 1.0); }`;
function sh(type, src) {
  const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) { document.title = 'ERR'; document.body.innerText = gl.getShaderInfoLog(s); throw 0; }
  return s;
}
const pr = gl.createProgram();
gl.attachShader(pr, sh(gl.VERTEX_SHADER, vs)); gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, fs));
gl.linkProgram(pr); gl.useProgram(pr);
gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 3,-1, -1,3]), gl.STATIC_DRAW);
gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
const set = (n, v) => { const l = gl.getUniformLocation(pr, n); if (l !== null) gl.uniform1f(l, v); };
const num = (k, d) => parseFloat(q.get(k) ?? d);
const fixedT = q.has('t') ? parseFloat(q.get('t')) : null;
const t0 = performance.now();
function frame() {
  c.width = innerWidth; c.height = innerHeight; gl.viewport(0, 0, c.width, c.height);
  set('u_time', fixedT ?? num('speed', 1) * (performance.now() - t0) / 1000);
  set('u_aspect', c.width / c.height);
  set('u_rows', num('rows', 2.5));
  set('u_palette', STYLE[1]);
  set('u_amp', num('amp', 0.08));
  set('u_px', 1 / c.height);
  set('u_seed', 0.0);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
  if (fixedT === null) { setTimeout(() => requestAnimationFrame(frame), 33); return; }
  // Frozen frame: swap in an <img> (headless screenshots skip GL canvases).
  const img = new Image(); img.src = c.toDataURL(); img.style.cssText = 'width:100%;height:100%;display:block';
  c.replaceWith(img);
}
frame();
</script>
""".replace("@@SHADERS@@", json.dumps(shaders))

out = root / "preview.html"
out.write_text(html)
print(out)
