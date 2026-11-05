#version 450
// SPDX-License-Identifier: GPL-3.0-or-later
// Gallowmere - surface: normale vera di ogni pixel e occlusione ambientale
// Copyright (C) 2026
// Author: https://github.com/Leproide
//
// This program is free software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version. This program is distributed WITHOUT
// ANY WARRANTY. See <https://www.gnu.org/licenses/>.
//
// Normale: dalla profondita', usando solo i pixel vicini dello stesso triangolo (G-buffer),
// quindi esatta e senza rumore sui bordi tra superfici diverse.
// Occlusione: 12 campioni nell'emisfero della normale, confrontati con la profondita'.
// Uscita: rgb = normale (spazio di vista), a = occlusione (1 = libero).

#include "common.inc"

layout(set = 0, binding = 6) uniform sampler2D Source;

#include "vertex.inc"

vec3 normalAt(vec2 uv, vec3 p, float id)
{
    vec2 px = global.ShadingSize.zw;
    vec3 best[2];
    for (int axis = 0; axis < 2; axis++)
    {
        vec2 step = axis == 0 ? vec2(px.x, 0.0) : vec2(0.0, px.y);
        vec2 ua = uv + step, ub = uv - step;
        vec3 pa = viewPos(ua, depthAt(ua)), pb = viewPos(ub, depthAt(ub));
        bool sa = triangleId(ua) == id, sb = triangleId(ub) == id;
        vec3 da = pa - p, db = p - pb;
        if (sa && !sb) best[axis] = da;
        else if (sb && !sa) best[axis] = db;
        else best[axis] = abs(da.z) < abs(db.z) ? da : db;
    }
    vec3 n = normalize(cross(best[0], best[1]));
    return dot(n, -p) < 0.0 ? -n : n;
}

float occlusion(vec2 uv, vec3 p, vec3 n)
{
    if (global.GM_AO <= 0.0) return 1.0;
    float radius = global.GM_AO_RADIUS;
    float angle = ign(gl_FragCoord.xy) * 6.2831853;
    vec3 t = normalize(abs(n.y) < 0.9 ? cross(n, vec3(0.0, 1.0, 0.0)) : cross(n, vec3(1.0, 0.0, 0.0)));
    vec3 b = cross(n, t);
    float hidden = 0.0;
    const int COUNT = 12;
    for (int i = 0; i < COUNT; i++)
    {
        float fi = (float(i) + 0.5) / float(COUNT);
        float a = angle + float(i) * 2.399963;
        float r = sqrt(fi);
        vec3 dir = t * (cos(a) * r) + b * (sin(a) * r) + n * sqrt(max(1.0 - r * r, 0.0));
        vec3 s = p + dir * radius * mix(0.2, 1.0, fi);
        vec2 suv = project(s);
        if (any(lessThan(suv, vec2(0.0))) || any(greaterThan(suv, vec2(1.0)))) continue;
        float sd = depthAt(suv);
        if (!hasGeometry(sd)) continue;
        float sz = viewZ(sd);
        float diff = s.z - sz;
        if (diff > 2.0) hidden += smoothstep(radius * 2.0, radius * 0.5, diff);
    }
    return 1.0 - hidden / float(COUNT);
}

void main()
{
    float d = depthAt(vTexCoord);
    if (!gbuffer() || !hasGeometry(d) || texture(Albedo, vTexCoord).a < 0.5)
    {
        FragColor = vec4(0.0, 0.0, -1.0, 1.0);
        return;
    }
    vec3 p = viewPos(vTexCoord, d);
    vec3 n = normalAt(vTexCoord, p, triangleId(vTexCoord));
    FragColor = vec4(n, occlusion(vTexCoord, p, n));
}
