#version 450
// SPDX-License-Identifier: GPL-3.0-or-later
// Gallowmere - final: esposizione, compressione delle luci forti, interfaccia
// Copyright (C) 2026
// Author: https://github.com/Leproide
//
// This program is free software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version. This program is distributed WITHOUT
// ANY WARRANTY. See <https://www.gnu.org/licenses/>.
//
// Sotto 0.8 il colore resta quello calcolato (identico al gioco con la luce del gioco sola):
// solo le parti piu' luminose vengono compresse, cosi' le luci aggiunte non bruciano e i pixel
// lasciati all'immagine del gioco (effetti, trasparenze senza superficie sotto) non stonano.

#include "common.inc"

layout(set = 0, binding = 6) uniform sampler2D Accum;
layout(set = 0, binding = 7) uniform sampler2D Original;
layout(set = 0, binding = 8) uniform sampler2D Bloom;
layout(set = 0, binding = 9) uniform sampler2D Shafts;

#include "vertex.inc"

vec3 knee(vec3 x)
{
    const float k = 0.8;
    vec3 over = max(x - k, 0.0);
    return min(x, vec3(k)) + (1.0 - k) * (1.0 - exp(-over / (1.0 - k)));
}

void main()
{
    vec3 original = texture(Original, vTexCoord).rgb;
    vec4 lit = texture(Accum, vTexCoord);
    // debug: livello interfaccia di RecompOne (rosso = coperto da interfaccia/menu, verde = trasparenza)
    if (int(global.GM_VIEW + 0.5) == 12)
    {
        vec4 u = uiLayer(vTexCoord);
        FragColor = vec4(1.0 - u.a, global.UiLayerAvailable > 0.5 ? 0.3 : 0.0, luma(u.rgb), 1.0);
        return;
    }
    vec3 shafts = texture(Shafts, vTexCoord).rgb * global.GM_SHAFTS;
    if (lit.a < 0.5)
    {
        // cielo e schermate senza scena: immagine del gioco, con i raggi della luna sul cielo
        if (max(shafts.r, max(shafts.g, shafts.b)) < 0.002)
        {
            FragColor = vec4(original, 1.0);
            return;
        }
        vec4 sky = uiLayer(vTexCoord);
        vec3 c = toGamma(toLinear(sceneUnderUi(original, sky)) + shafts);
        FragColor = vec4(clamp(c * sky.a + sky.rgb, 0.0, 1.0), 1.0);
        return;
    }

    vec3 col = lit.rgb * accumBase(original, vTexCoord);
    if (int(global.GM_VIEW + 0.5) == 0)
    {
        col += texture(Bloom, vTexCoord).rgb * global.GM_BLOOM;
        col += shafts * (1.0 - 0.5 * clamp(luma(col) * 2.0, 0.0, 1.0));
        col = knee(col * exp2(global.GM_EXPOSURE));
        // tinta "maledetta" e colori smorzati nelle parti scure, come in Dan's Curse
        float gray = luma(col);
        float dark = 1.0 - smoothstep(0.0, 0.25, gray);
        col = mix(col, gray * CURSE_TINT / luma(CURSE_TINT), dark * global.GM_DARK_DESAT);
        col = mix(col, col * CURSE_TINT / luma(CURSE_TINT), dark * global.GM_CURSE * 0.5);
        gray = luma(col);
        col = max(mix(vec3(gray), col, global.GM_SATURATION), 0.0);
        vec2 c = vTexCoord - 0.5;
        col *= 1.0 - global.GM_VIGNETTE * smoothstep(0.1, 0.5, dot(c, c));
    }
    col = toGamma(col);

    // sotto menu e pannelli semitrasparenti (inventario, pausa): niente effetti dello shader,
    // solo l'immagine del gioco, e il pannello piu' coprente
    vec4 ui = uiLayer(vTexCoord);
    float panel = 1.0 - smoothstep(0.9, 0.99, ui.a);
    col = mix(col, sceneUnderUi(original, ui), panel);
    // testo dei menu: il gioco lo somma all'immagine (additivo, senza copertura). Sotto lo si scurisce,
    // cosi' resta leggibile anche sulla scena rischiarata dallo shader
    float additive = clamp(luma(ui.rgb) * 4.0, 0.0, 1.0) * smoothstep(0.9, 0.99, ui.a);
    float through = ui.a * (1.0 - panel * global.GM_MENU_OPACITY) * (1.0 - additive * global.GM_MENU_OPACITY);
    FragColor = vec4(clamp(col * through + ui.rgb, 0.0, 1.0), 1.0);
}
