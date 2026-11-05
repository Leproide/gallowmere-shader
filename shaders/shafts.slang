#version 450
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026
// Author: https://github.com/Leproide
//
// This program is free software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version. This program is distributed WITHOUT
// ANY WARRANTY. See <https://www.gnu.org/licenses/>.
//
// Gallowmere - shafts: raggi della luna. Sfocatura radiale verso la luna del cielo visibile
// (pixel senza geometria): dove la scena copre il cielo nascono i raggi. Mezza risoluzione.

#include "common.inc"

layout(set = 0, binding = 6) uniform sampler2D Source;
layout(set = 0, binding = 7) uniform sampler2D Original;

#include "vertex.inc"

void main()
{
    vec3 l = moonDir();
    if (global.GM_SHAFTS <= 0.0 || l.z <= -0.3 || global.DepthAvailable < 0.5)
    {
        FragColor = vec4(0.0);
        return;
    }
    vec2 moon = l.z > 0.05 ? project(l * 10000.0) : vTexCoord + normalize(vec2(l.x, -l.y) + 1e-4) * 2.0;
    vec2 delta = (moon - vTexCoord) / 40.0;
    vec2 uv = vTexCoord;
    float jitter = ign(gl_FragCoord.xy);
    uv += delta * jitter;
    float sum = 0.0, weight = 1.0;
    for (int i = 0; i < 40; i++)
    {
        if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) break;
        float sky = hasGeometry(depthAt(uv)) ? 0.0 : 1.0;
        sum += sky * weight * (0.3 + luma(texture(Original, uv).rgb));
        weight *= 0.96;
        uv += delta;
    }
    // piu' forti guardando verso la luna
    // piu' forti guardando verso la luna, deboli di lato, niente alle spalle
    float facing = smoothstep(-0.3, 0.9, l.z) * 0.8;
    FragColor = vec4(MOON_COLOR * sum / 40.0 * facing, 1.0);
}
