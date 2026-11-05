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
// Gallowmere - bloom_blur_v: sfocatura gaussiana larga del bloom

#include "common.inc"

layout(set = 0, binding = 6) uniform sampler2D Source;

#include "vertex.inc"

void main()
{
    vec2 step = vec2(0.0, global.SourceSize.w) * 1.5;
    const float w[5] = float[5](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    vec3 sum = texture(Source, vTexCoord).rgb * w[0];
    for (int i = 1; i < 5; i++)
    {
        sum += texture(Source, vTexCoord + step * float(i)).rgb * w[i];
        sum += texture(Source, vTexCoord - step * float(i)).rgb * w[i];
    }
    FragColor = vec4(sum, 1.0);
}
