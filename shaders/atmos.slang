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
// Gallowmere - atmos: dati della scena (2x1), mediati nel tempo.
//  texel 0: rgb = colore medio del cielo visibile (base della nebbia), a = apertura
//           (1 = all'aperto con cielo visibile in alto, 0 = interno/caverna)
//  texel 1: x = limite di disegno (distanza del gioco o geometria piu' lontana), y = vuoto
//           sotto l'orizzonte, z = presenza della scena 3D (0 = schermata 2D/menu),
//           w = 0.5 + 0.5 * luce media del gioco sulla geometria (non mediata: vicino a 0 durante
//           le dissolvenze al nero del gioco, li' lo shader non aggiunge luce)

#include "common.inc"

layout(set = 0, binding = 6) uniform sampler2D Source;
layout(set = 0, binding = 7) uniform sampler2D Original;
layout(set = 0, binding = 8) uniform sampler2D AtmosFeedback;

#include "vertex.inc"

void main()
{
    vec4 previous = texture(AtmosFeedback, vTexCoord);
    bool hasPrevious = previous.a > 0.25;
    vec3 sky = vec3(0.0);
    float skyCount = 0.0, open = 0.0, upper = 0.0, below = 0.0, geometry = 0.0, far = 0.0;
    float gameLight = 0.0, lit = 0.0;
    const int GX = 24, GY = 16;
    for (int y = 0; y < GY; y++)
    for (int x = 0; x < GX; x++)
    {
        vec2 uv = (vec2(x, y) + 0.5) / vec2(GX, GY);
        if (uiLayer(uv).a < 0.9) continue;
        float d = depthAt(uv);
        bool geo = hasGeometry(d);
        // cielo visibile sopra l'orizzonte (non solo in alto sullo schermo): non dipende da dove si guarda
        vec3 r0 = vec3((uv - global.Projection.zw) * global.Projection.xy, 1.0);
        float up0 = global.CameraAvailable > 0.5 ? -normalize(toWorldDirection(r0)).y : r0.y;
        if (up0 > 0.02) { upper += 1.0; if (!geo) open += 1.0; }
        if (geo)
        {
            geometry += 1.0;
            far = max(far, viewPos(uv, d).z);
            if (gbuffer() && texture(Albedo, uv).a >= 0.5)
            {
                gameLight += luma(toLinear(texture(Shading, uv).rgb * 2.0));
                lit += 1.0;
            }
            continue;
        }
        vec3 ray = vec3((uv - global.Projection.zw) * global.Projection.xy, 1.0);
        float down = global.CameraAvailable > 0.5 ? normalize(toWorldDirection(ray)).y : -ray.y;
        if (down > 0.05) { below += 1.0; continue; }
        sky += toLinear(texture(Original, uv).rgb);
        skyCount += 1.0;
    }
    float total = float(GX * GY);
    if (vTexCoord.x < 0.5)
    {
        vec3 color = skyCount >= 4.0 ? sky / skyCount : hasPrevious ? previous.rgb : vec3(0.01, 0.015, 0.02);
        // se non si vede sopra l'orizzonte (telecamera verso il basso) si tiene il valore precedente
        float openness = upper < 8.0 && hasPrevious ? clamp((previous.a - 0.3) / 0.7, 0.0, 1.0)
                       : global.DepthAvailable > 0.5 ? smoothstep(0.01, 0.1, open / max(upper, 1.0)) : 1.0;
        if (global.SceneIndoor.y > 0.5) openness = 1.0 - global.SceneIndoor.x;
        vec4 current = vec4(color, 0.3 + 0.7 * openness);
        FragColor = hasPrevious ? mix(previous, current, 0.015) : current;
        return;
    }
    float game = global.SceneViewDistance.y > 0.5 ? global.SceneViewDistance.x : 0.0;
    float limit = game > 500.0 ? game : far;
    float meanLight = lit >= 4.0 ? gameLight / lit : 1.0;
    vec4 current = vec4(limit, below / total, geometry / total, 0.5 + 0.5 * clamp(meanLight, 0.0, 1.0));
    FragColor = hasPrevious ? vec4(game > 500.0 ? limit : (limit > previous.x ? mix(previous.x, limit, 0.05) : mix(previous.x, limit, 0.2)),
                                   mix(previous.y, current.y, 0.05), mix(previous.z, current.z, 0.35), current.w) : current;
}
