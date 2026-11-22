// SPDX-License-Identifier: GPL-2.0-or-later
// Low-poly sea: a jittered triangle mesh riding a few big, slow swells.
//
// This file is the *declarations* part of a Cogl fragment snippet. The
// extension's snippet body is just:
//     cogl_color_out = vec4(background(cogl_tex_coord_in[0].xy), 1.0);
// Written to stay valid as GLSL 1.10 (Cogl) and GLSL ES 1.00 (WebGL preview).
//
// Palettes (u_palette): 0 = classic Ubuntu purple->orange,
//                       1 = aubergine (Ubuntu 24.04 "Numbat" colours, deep shadows).
//
// Cost: 16 vertex evaluations (3 sin + 2 for drift each), 18 point-in-triangle
// tests and 1-2 facet shadings per pixel. No textures.

uniform float u_time;    // seconds, only advances while animating
uniform float u_aspect;  // width / height of the monitor
uniform float u_rows;    // triangle rows over the screen height (triangle size)
uniform float u_amp;     // sideways drift of the vertices, in cells (<= 0.08)
uniform float u_px;      // one pixel in screen-height units (anti-aliasing)
uniform float u_seed;    // per-monitor variation
uniform float u_palette; // 0 = orange, 1 = aubergine

// Sine-free hash (Dave Hoskins, "Hash without Sine").
vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Big swells in screen space (units of screen height), so the number of
// waves on screen doesn't depend on the triangle size: wavelengths of
// 1.3-2.6 screen heights, all rolling toward the bottom-right.
float swell(vec2 s, float t) {
    return 0.60 * sin(dot(s, vec2(2.79, 2.10)) - t * 0.33)    // ~1.8 heights, diagonal
         + 0.35 * sin(dot(s, vec2(1.39, 4.62)) - t * 0.26 + 1.7) // ~1.3 heights, downward
         + 0.25 * sin(dot(s, vec2(-1.71, 1.71)) + t * 0.19 + 4.0); // ~2.6 heights, cross swell
}

// Vertex of the lattice: xy position (cell units) and swell height z.
// Total displacement (0.25 jitter + u_amp<=0.08 + 0.1 lift) stays below
// 0.5 cell, so a pixel's triangle is always in the 3x3 cells around it.
vec3 vtx(vec2 id) {
    vec2 h = hash22(id * 1.37 + 11.3 + u_seed);     // scaled: hash is weak on ints
    vec2 p = id + (h - 0.5) * 0.5;                  // static jitter, +-0.25
    float t = u_time + u_seed;
    float z = swell(p / u_rows, t);                 // |z| <= 1.2
    p += u_amp * vec2(sin(t * 0.50 + h.x * 6.2832),
                      sin(t * 0.37 + h.y * 6.2832)); // gentle drift
    p.y -= z * 0.08;                                  // crests rise up the screen
    return vec3(p, z);
}

float edgeFn(vec2 a, vec2 b, vec2 p) {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

// Normalised "insideness" of p in triangle abc: >= 0 means inside.
float inside(vec2 a, vec2 b, vec2 c, vec2 p) {
    float area = edgeFn(a, b, c);
    float w0 = edgeFn(b, c, p) / area;
    float w1 = edgeFn(c, a, p) / area;
    float w2 = edgeFn(a, b, p) / area;
    return min(w0, min(w1, w2));
}

// Signed distance (cell units) from p to the nearest edge of abc; >0 inside.
float edgeDist(vec2 a, vec2 b, vec2 c, vec2 p) {
    float s = sign(edgeFn(a, b, c));
    float d0 = s * edgeFn(b, c, p) / length(c - b);
    float d1 = s * edgeFn(c, a, p) / length(a - c);
    float d2 = s * edgeFn(a, b, p) / length(b - a);
    return min(d0, min(d1, d2));
}

vec3 rgb(float r, float g, float b) { return vec3(r, g, b) / 255.0; }

vec3 orangePalette(float t) {
    vec3 c0 = vec3(0.502, 0.208, 0.502); // purple
    vec3 c1 = vec3(0.776, 0.282, 0.329); // raspberry
    vec3 c2 = vec3(0.914, 0.329, 0.125); // Ubuntu orange #E95420
    return t < 0.5 ? mix(c0, c1, t * 2.0) : mix(c1, c2, t * 2.0 - 1.0);
}

// Numbat wallpaper colours: near-black top-left -> aubergine, orange glow
// in the bottom-right (calibrated against the real 24.04 wallpaper).
vec3 aubergineBase(vec2 uv, out float glow) {
    float f = clamp(1.9 * uv.x + 1.1 * uv.y - 0.23, 0.0, 1.0);
    vec3 col = mix(rgb(38.0, 0.0, 25.0), rgb(92.0, 30.0, 65.0), f);
    vec2 q = vec2((uv.x - 1.0) * u_aspect, (uv.y - 1.05) * 1.4);
    glow = exp(-dot(q, q) / 0.36);
    return col + rgb(74.0, 32.0, -20.0) * glow;
}

// Colour of one facet at pixel P (cell units) / uv.
vec3 shade(vec3 A, vec3 B, vec3 C, vec2 cells, vec2 P, vec2 uv) {
    // Facet normal in screen-height units; swell height scaled to ~0.2 screen.
    vec3 n = normalize(cross(vec3((B.xy - A.xy) / u_rows, (B.z - A.z) * 0.2),
                             vec3((C.xy - A.xy) / u_rows, (C.z - A.z) * 0.2)));
    n *= sign(n.z);

    if (u_palette < 0.5) {
        // Classic: flat colour per facet from its centroid.
        vec2 g = (A.xy + B.xy + C.xy) / (3.0 * cells);
        float t = clamp(g.x * 0.95 + (0.5 - g.y) * 0.15 + 0.02, 0.0, 1.0);
        vec3 L = normalize(vec3(0.45, -0.55, 1.0));
        return clamp(orangePalette(t) * (1.0 + (dot(n, L) - L.z) * 0.6), 0.0, 1.0);
    }

    // Aubergine: smooth Numbat gradient per pixel, hard light per facet and
    // soft shadows in the troughs (height interpolated across the facet).
    float glow;
    vec3 col = aubergineBase(uv, glow);
    float area = edgeFn(A.xy, B.xy, C.xy);
    float zp = (edgeFn(B.xy, C.xy, P) * A.z + edgeFn(C.xy, A.xy, P) * B.z +
                edgeFn(A.xy, B.xy, P) * C.z) / area;

    vec3 L = normalize(vec3(0.55, -0.65, 0.75));  // light from the upper right
    float d = dot(n, L) - L.z;                     // 0 for a flat facet
    float shFacet = clamp(-d * 2.6, 0.0, 0.7);
    float shSoft = 0.5 * smoothstep(-0.1, -1.15, zp);
    float sh = (1.0 - (1.0 - shFacet) * (1.0 - shSoft)) * (1.0 - 0.6 * glow);
    // wine-red shadows: green/blue fall faster than red
    col *= clamp(vec3(1.0) - sh * vec3(1.0, 1.3, 1.3), 0.0, 1.0);
    float lit = clamp(d * 3.0, 0.0, 0.7) * (1.0 - shSoft);
    col += lit * mix(rgb(42.0, 12.0, 32.0), rgb(80.0, 30.0, 8.0), glow);
    return clamp(col, 0.0, 1.0);
}

vec3 background(vec2 uv) {
    vec2 cells = vec2(u_rows * u_aspect, u_rows);
    vec2 P = uv * cells;
    vec2 f = floor(P);

    // 4x4 vertex neighbourhood, evaluated once.
    vec3 v[16];
    for (int j = 0; j < 4; j++)
        for (int i = 0; i < 4; i++)
            v[j * 4 + i] = vtx(f + vec2(float(i - 1), float(j - 1)));

    // Best (containing) and second-best (neighbour) triangle, for anti-aliasing.
    float best = -1e9, second = -1e9;
    vec3 A = v[0], B = v[1], C = v[4];
    vec3 A2 = A, B2 = B, C2 = C;
    for (int j = 0; j < 3; j++) {
        for (int i = 0; i < 3; i++) {
            vec3 a = v[j * 4 + i];
            vec3 b = v[j * 4 + i + 1];
            vec3 c = v[j * 4 + i + 4];
            vec3 d = v[j * 4 + i + 5];
            // Pick the quad's diagonal per cell for a less regular mesh.
            bool flip = hash22((f + vec2(float(i), float(j))) * 1.71 + 17.0 + u_seed).x > 0.5;
            vec3 t0a = a, t0b = b, t0c = flip ? d : c;
            vec3 t1a = flip ? a : b, t1b = d, t1c = c;
            float s0 = inside(t0a.xy, t0b.xy, t0c.xy, P);
            if (s0 > best) {
                second = best; A2 = A; B2 = B; C2 = C;
                best = s0; A = t0a; B = t0b; C = t0c;
            } else if (s0 > second) {
                second = s0; A2 = t0a; B2 = t0b; C2 = t0c;
            }
            float s1 = inside(t1a.xy, t1b.xy, t1c.xy, P);
            if (s1 > best) {
                second = best; A2 = A; B2 = B; C2 = C;
                best = s1; A = t1a; B = t1b; C = t1c;
            } else if (s1 > second) {
                second = s1; A2 = t1a; B2 = t1b; C2 = t1c;
            }
        }
    }

    vec3 col = shade(A, B, C, cells, P, uv);
    // Anti-alias the facet edge: blend with the neighbour within ~1 pixel.
    float dpx = edgeDist(A.xy, B.xy, C.xy, P) / (u_rows * u_px);
    if (dpx < 1.0)
        col = mix(shade(A2, B2, C2, cells, P, uv), col, clamp(0.5 + dpx, 0.5, 1.0));
    return col;
}
