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
// Gallowmere - emitters: le luci degli effetti come punti 3D. Lo schermo e' diviso in 16x9
// celle; per ogni cella si somma la luce degli effetti (pass emit) e se ne calcola la posizione
// media nello spazio di vista. Uscita 32x9: x pari = colore, x dispari = (uv.x, uv.y, z, 1).
// light.slang usa ogni cella accesa come una luce puntiforme, che illumina anche le superfici
// rivolte dall'altra parte rispetto alla telecamera (es. Dan di spalle alla fonte di vita).

#include "common.inc"

layout(set = 0, binding = 6) uniform sampler2D Source;

#include "vertex.inc"

void main()
{
    ivec2 texel = ivec2(gl_FragCoord.xy);
    int cell = texel.x / 2;
    vec2 lo = vec2(float(cell) / 16.0, float(texel.y) / 9.0);
    vec2 size = vec2(1.0 / 16.0, 1.0 / 9.0);
    vec3 sum = vec3(0.0);
    vec3 at = vec3(0.0);
    float weight = 0.0;
    for (int y = 0; y < 8; y++)
    for (int x = 0; x < 8; x++)
    {
        vec2 uv = lo + (vec2(x, y) + 0.5) / 8.0 * size;
        vec3 e = texture(Source, uv).rgb;
        float w = luma(e);
        if (w <= 0.0005) continue;
        float d = depthAt(uv);
        if (!hasGeometry(d)) continue;
        sum += e;
        at += vec3(uv, viewZ(d)) * w;
        weight += w;
    }
    if (weight <= 0.0) { FragColor = vec4(0.0); return; }
    FragColor = (texel.x & 1) == 0 ? vec4(sum / 64.0, 1.0) : vec4(at / weight, 1.0);
}
