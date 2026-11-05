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
// Gallowmere - accum: accumulo temporale della luce (rapporto scena rifatta / immagine del gioco). Ogni pixel della scena rifatta viene riproiettato nel
// fotogramma precedente (telecamera di questo e del precedente fotogramma) e mediato con la
// storia, limitata ai colori dei vicini di questo fotogramma (niente scie su chi si muove).
// Stabilizza acqua, riflessi, ombre e occlusione e media il loro rumore.

#include "common.inc"

layout(set = 0, binding = 6) uniform sampler2D Source;
layout(set = 0, binding = 7) uniform sampler2D AccumFeedback;
layout(set = 0, binding = 8) uniform sampler2D Original;

#include "vertex.inc"

vec3 ratioAt(vec2 uv)
{
    return texture(Source, uv).rgb / accumBase(texture(Original, uv).rgb, uv);
}

void main()
{
    vec4 current = texture(Source, vTexCoord);
    if (current.a < 0.5) { FragColor = current; return; }
    vec3 ratio = current.rgb / accumBase(texture(Original, vTexCoord).rgb, vTexCoord);
    if (global.GM_TEMPORAL <= 0.0) { FragColor = vec4(ratio, 1.0); return; }

    float d = depthAt(vTexCoord);
    vec2 prev = vTexCoord;
    if (hasGeometry(d) && global.CameraAvailable > 0.5 && global.PreviousCameraAvailable > 0.5)
    {
        vec3 w = toWorld(viewPos(vTexCoord, d)) - global.PreviousCameraTranslation.xyz;
        vec3 v = vec3(dot(global.PreviousCameraRow0.xyz, w), dot(global.PreviousCameraRow1.xyz, w), dot(global.PreviousCameraRow2.xyz, w));
        prev = v.z > 1.0 ? project(v) : vec2(-1.0);
    }
    if (any(lessThan(prev, vec2(0.0))) || any(greaterThan(prev, vec2(1.0)))) { FragColor = vec4(ratio, 1.0); return; }

    vec4 history = texture(AccumFeedback, prev);
    if (history.a < 0.5) { FragColor = vec4(ratio, 1.0); return; }

    vec2 px = global.SourceSize.zw;
    vec3 lo = ratio, hi = ratio;
    for (int y = -1; y <= 1; y++)
    for (int x = -1; x <= 1; x++)
    {
        vec3 c = ratioAt(vTexCoord + vec2(x, y) * px);
        lo = min(lo, c);
        hi = max(hi, c);
    }
    FragColor = vec4(mix(ratio, clamp(history.rgb, lo, hi), global.GM_TEMPORAL), 1.0);
}
