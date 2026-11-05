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
// Gallowmere - bloom_bright: parti luminose della scena rifatta (solo dove la luce e' stata rifatta)

#include "common.inc"

layout(set = 0, binding = 6) uniform sampler2D Accum;
layout(set = 0, binding = 7) uniform sampler2D Original;

#include "vertex.inc"

void main()
{
    vec4 lit = texture(Accum, vTexCoord);
    if (lit.a < 0.5) { FragColor = vec4(0.0); return; }
    lit.rgb *= accumBase(texture(Original, vTexCoord).rgb, vTexCoord);
    float l = luma(lit.rgb);
    float over = max(l - global.GM_BLOOM_THRESHOLD, 0.0);
    FragColor = vec4(lit.rgb * (over / max(l, 1e-4)), 1.0);
}
