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
// Gallowmere - emit: luce degli effetti (fonti di vita, magie, scintille). Dove sopra una
// superficie l'immagine del gioco e' piu' luminosa di texture x vertici, il gioco ha disegnato
// un effetto additivo: quella differenza e' luce emessa. Viene sfocata molto (glow_blur_*) e
// raccolta per celle in emitters.slang, che ne fa luci puntiformi 3D.

#include "common.inc"

layout(set = 0, binding = 6) uniform sampler2D Source;
layout(set = 0, binding = 7) uniform sampler2D Original;

#include "vertex.inc"

void main()
{
    vec3 sum = vec3(0.0);
    // 4x4 campioni: l'uscita e' a 1/8 della risoluzione
    vec2 px = global.OriginalSize.zw * 2.0;
    for (int y = -2; y < 2; y++)
    for (int x = -2; x < 2; x++)
    {
        vec2 uv = vTexCoord + (vec2(x, y) + 0.5) * px;
        vec4 a = texture(Albedo, uv);
        if (a.a < 0.5) continue;
        vec3 scene = sceneUnderUi(texture(Original, uv).rgb, uiLayer(uv));
        vec3 rebuilt = min(a.rgb * texture(Shading, uv).rgb * 2.0, 1.0);
        vec3 extra = max(toLinear(scene) - toLinear(rebuilt), 0.0);
        float hi = max(extra.r, max(extra.g, extra.b)), lo = min(extra.r, min(extra.g, extra.b));
        // solo differenze nette e colorate (effetti), non le scritte chiare o il rumore
        // sopra acqua e superfici traslucide l'immagine differisce sempre dal fondo: li' conta solo
        // un effetto molto luminoso (fuoco, magie), non l'acqua stessa
        int m = global.MaterialAvailable > 0.5 ? int(texture(Material, uv).r * 255.0 + 0.5) : 0;
        float floorLevel = (m == MATERIAL_WATER || m == MATERIAL_TRANSLUCENT) ? 0.45 : 0.05;
        sum += extra * smoothstep(floorLevel, floorLevel + 0.15, hi) * mix(0.4, 1.0, smoothstep(0.1, 0.5, (hi - lo) / max(hi, 1e-3)));
    }
    FragColor = vec4(sum / 16.0, 1.0);
}
