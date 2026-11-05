// SPDX-License-Identifier: GPL-3.0-or-later
// Gallowmere - common.inc: parametri, dati di RecompOne e funzioni comuni
// Copyright (C) 2026
// Author: https://github.com/Leproide
//
// This program is free software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version. This program is distributed WITHOUT
// ANY WARRANTY. See <https://www.gnu.org/licenses/>.
//
// Dati usati (patch recompone-fixes/shader-gbuffer.patch di MediEvilRecomp ITA):
//  - Albedo: colore della texture senza la luce dei vertici (a = 1 dove c'e' geometria opaca);
//  - Shading: colore dei vertici, cioe' la luce "cotta" dal gioco (0.5 = neutro), id del triangolo in a;
//  - Depth, Material, UiLayer, SceneLights, camera: come in RecompOne.
// Il gioco calcola colore = texture x vertici x 2. Gallowmere ricalcola solo la luce: la parte
// del gioco resta (con occlusione ambientale) e si aggiungono luna e luci puntiformi, applicate
// come rapporto sull'immagine del gioco. Cosi' anche decalcomanie, scritte e trasparenze sopra
// una superficie prendono la stessa luce, e dove il gioco ha messo il nero (bordi, buchi) resta nero.

#pragma parameter GM_VIEW "View (0 final, 1 albedo, 2 game light, 3 normals, 4 triangles, 5 depth, 6 material, 7 occlusion, 8 light ratio, 9 new light, 10 metal, 11 water, 12 menu layer)" 0.0 0.0 12.0 1.0
#pragma parameter GM_GAME_LIGHT "Game lighting" 1.0 0.0 1.5 0.05
#pragma parameter GM_AO "Ambient occlusion" 0.8 0.0 2.0 0.05
#pragma parameter GM_AO_RADIUS "Occlusion radius" 90.0 10.0 400.0 5.0
#pragma parameter GM_MOON "Moonlight" 0.35 0.0 2.0 0.05
#pragma parameter GM_SKY_FILL "Sky fill light (back and sides)" 0.5 0.0 2.0 0.05
#pragma parameter GM_MOON_YAW "Moon direction" 320.0 0.0 360.0 5.0
#pragma parameter GM_MOON_PITCH "Moon height" 35.0 5.0 90.0 1.0
#pragma parameter GM_LAMPS "Light sources" 2.2 0.0 4.0 0.1
#pragma parameter GM_LAMP_RANGE "Light source range" 1.2 0.25 4.0 0.05
#pragma parameter GM_LAMP_MIN "Light source minimum reach" 650.0 0.0 2000.0 25.0
#pragma parameter GM_MENU_OPACITY "Menu opacity boost" 0.45 0.0 1.0 0.05
#pragma parameter GM_OVERLAY_LIGHT "Light on overlays (menus, effects)" 0.25 0.0 1.0 0.05
#pragma parameter GM_FOG "Fog" 0.6 0.0 1.0 0.05
#pragma parameter GM_FOG_START "Fog start" 2500.0 0.0 30000.0 100.0
#pragma parameter GM_FOG_END "Fog end" 12000.0 500.0 40000.0 250.0
#pragma parameter GM_FOG_BRIGHT "Fog brightness" 0.35 0.0 2.0 0.05
#pragma parameter GM_HAZE "Base haze" 0.04 0.0 1.0 0.02
#pragma parameter GM_FOG_SKY "Fog over sky" 0.35 0.0 1.0 0.05
#pragma parameter GM_EDGE "Draw distance fade" 1.0 0.0 1.0 0.05
#pragma parameter GM_SHADOW_GAME "Shadows on game light" 0.45 0.0 1.0 0.05
#pragma parameter GM_CURSE "Curse tint" 0.15 0.0 1.0 0.05
#pragma parameter GM_DARK_DESAT "Dark desaturation" 0.2 0.0 1.0 0.05
#pragma parameter GM_INDOOR "Indoor darkness" 0.5 0.0 1.0 0.05
#pragma parameter GM_BLOOM "Bloom" 0.6 0.0 2.0 0.05
#pragma parameter GM_BLOOM_THRESHOLD "Bloom threshold" 0.55 0.0 1.0 0.05
#pragma parameter GM_SPECULAR "Specular" 0.15 0.0 1.0 0.05
#pragma parameter GM_METAL "Metal reflections (sword, shield)" 0.7 0.0 2.0 0.05
#pragma parameter GM_METAL_GUESS "Guess metal from colour" 1.0 0.0 1.0 1.0
#pragma parameter GM_WATER "Water reflections" 0.7 0.0 1.0 0.05
#pragma parameter GM_WATER_WAVES "Water waves" 1.2 0.0 3.0 0.05
#pragma parameter GM_WATER_DENSITY "Water density" 1.2 0.0 5.0 0.05
#pragma parameter GM_CAUSTICS "Water caustics" 0.4 0.0 2.0 0.05
#pragma parameter GM_GLOW "Effect light (life sources, magic)" 1.5 0.0 5.0 0.1
#pragma parameter GM_GLOW_RANGE "Effect light range" 700.0 100.0 3000.0 50.0
#pragma parameter GM_SHAFTS "Moon shafts" 0.15 0.0 2.0 0.05
#pragma parameter GM_MOON_HAZE "Moon glow in fog" 0.5 0.0 2.0 0.05
#pragma parameter GM_TEMPORAL "Temporal smoothing" 0.85 0.0 0.97 0.01
#pragma parameter GM_SMOOTH "Smooth surfaces" 1.0 0.0 1.0 0.05
#pragma parameter GM_SHADOWS "Shadows" 0.8 0.0 1.0 0.05
#pragma parameter GM_SHADOW_LENGTH "Shadow length" 250.0 20.0 1000.0 10.0
#pragma parameter GM_FLICKER "Fire flicker" 0.5 0.0 1.0 0.05
#pragma parameter GM_MIST "Ground mist" 0.3 0.0 1.0 0.05
#pragma parameter GM_MIST_HEIGHT "Ground mist height" 300.0 25.0 2000.0 25.0
#pragma parameter GM_MAX_BOOST "Maximum brightening" 3.0 1.0 8.0 0.25
#pragma parameter GM_EXPOSURE "Exposure" 0.2 -2.0 2.0 0.1
#pragma parameter GM_SATURATION "Saturation" 1.0 0.0 2.0 0.05
#pragma parameter GM_VIGNETTE "Vignette" 0.15 0.0 1.0 0.05

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
    vec4 SourceSize;
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 ShadingSize;
    vec4 Projection;
    vec4 CameraRow0;
    vec4 CameraRow1;
    vec4 CameraRow2;
    vec4 CameraInverseRow0;
    vec4 CameraInverseRow1;
    vec4 CameraInverseRow2;
    vec4 CameraTranslation;
    vec4 PreviousCameraRow0;
    vec4 PreviousCameraRow1;
    vec4 PreviousCameraRow2;
    vec4 PreviousCameraTranslation;
    vec4 SceneWaterPlane;
    vec4 SceneWaterLevel;
    vec4 SceneIndoor;
    vec4 SceneViewDistance;
    uint FrameCount;
    float Time;
    float DepthAvailable;
    float GbufferAvailable;
    float MaterialAvailable;
    float UiLayerAvailable;
    float CameraAvailable;
    float PreviousCameraAvailable;
    float SceneLightCount;
    float GM_VIEW;
    float GM_GAME_LIGHT;
    float GM_AO;
    float GM_AO_RADIUS;
    float GM_MOON;
    float GM_SKY_FILL;
    float GM_MOON_YAW;
    float GM_MOON_PITCH;
    float GM_LAMPS;
    float GM_LAMP_RANGE;
    float GM_LAMP_MIN;
    float GM_MENU_OPACITY;
    float GM_OVERLAY_LIGHT;
    float GM_FOG;
    float GM_FOG_START;
    float GM_FOG_END;
    float GM_FOG_BRIGHT;
    float GM_HAZE;
    float GM_FOG_SKY;
    float GM_EDGE;
    float GM_SHADOW_GAME;
    float GM_CURSE;
    float GM_DARK_DESAT;
    float GM_INDOOR;
    float GM_BLOOM;
    float GM_BLOOM_THRESHOLD;
    float GM_SPECULAR;
    float GM_METAL;
    float GM_METAL_GUESS;
    float GM_WATER;
    float GM_WATER_WAVES;
    float GM_WATER_DENSITY;
    float GM_CAUSTICS;
    float GM_GLOW;
    float GM_GLOW_RANGE;
    float GM_SHAFTS;
    float GM_MOON_HAZE;
    float GM_TEMPORAL;
    float GM_SMOOTH;
    float GM_SHADOWS;
    float GM_SHADOW_LENGTH;
    float GM_FLICKER;
    float GM_MIST;
    float GM_MIST_HEIGHT;
    float GM_MAX_BOOST;
    float GM_EXPOSURE;
    float GM_SATURATION;
    float GM_VIGNETTE;
} global;

layout(set = 0, binding = 1) uniform sampler2D Depth;
layout(set = 0, binding = 2) uniform sampler2D Albedo;
layout(set = 0, binding = 3) uniform sampler2D Shading;
layout(set = 0, binding = 4) uniform sampler2D Material;
layout(set = 0, binding = 5) uniform sampler2D UiLayer;

const float OVERLAY_DEPTH = 0.999997;
const int MATERIAL_WATER = 1;
const int MATERIAL_METAL = 4;
const int MATERIAL_EMISSIVE = 5;
const int MATERIAL_GLASS = 6;
const int MATERIAL_WET = 15;
const int MATERIAL_TRANSLUCENT = 255;
const vec3 MOON_COLOR = vec3(0.55, 0.66, 1.0);
const vec3 CURSE_FOG = vec3(0.020, 0.034, 0.038);
const vec3 CURSE_TINT = vec3(0.60, 0.82, 0.84);
const vec2 ATMOS_SKY = vec2(0.25, 0.5);
const vec2 ATMOS_SCENE = vec2(0.75, 0.5);

vec3 toLinear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }
vec3 toGamma(vec3 c) { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec4 uiLayer(vec2 uv);
vec3 sceneUnderUi(vec3 color, vec4 ui);

vec4 uiLayer(vec2 uv)
{
    return global.UiLayerAvailable > 0.5 ? texture(UiLayer, uv) : vec4(0.0, 0.0, 0.0, 1.0);
}

vec3 sceneUnderUi(vec3 color, vec4 ui)
{
    return ui.a > 0.02 ? clamp((color - ui.rgb) / ui.a, 0.0, 1.0) : color;
}

bool gbuffer() { return global.GbufferAvailable > 0.5; }

// accumulo: la storia contiene il rapporto tra la scena rifatta e l'immagine del gioco (la luce),
// non il colore, cosi' le texture restano nitide anche su cio' che si muove (Dan, nemici)
vec3 accumBase(vec3 original, vec2 uv)
{
    return toLinear(sceneUnderUi(original, uiLayer(uv))) + 0.01;
}

float depthAt(vec2 uv) { return global.DepthAvailable > 0.5 ? texture(Depth, uv).r : 1.0; }

bool hasGeometry(float d) { return global.DepthAvailable > 0.5 && d < OVERLAY_DEPTH; }

float viewZ(float d) { return 1.0 / max(1.0 - d, 1e-7); }

vec3 viewPos(vec2 uv, float d)
{
    float z = viewZ(d);
    return vec3((uv - global.Projection.zw) * global.Projection.xy * z, z);
}

vec2 project(vec3 p)
{
    return p.xy / (p.z * global.Projection.xy) + global.Projection.zw;
}

// id del triangolo (0-255) scritto da RecompOne; -1 dove non c'e' geometria opaca
float triangleId(vec2 uv)
{
    return texture(Albedo, uv).a > 0.5 ? floor(texture(Shading, uv).a * 255.0 + 0.5) : -1.0;
}

vec3 toView(vec3 w)
{
    if (global.CameraAvailable < 0.5) return w;
    return vec3(dot(global.CameraRow0.xyz, w), dot(global.CameraRow1.xyz, w), dot(global.CameraRow2.xyz, w));
}

vec3 toWorldDirection(vec3 v)
{
    if (global.CameraAvailable < 0.5) return v;
    return vec3(dot(global.CameraInverseRow0.xyz, v), dot(global.CameraInverseRow1.xyz, v), dot(global.CameraInverseRow2.xyz, v));
}

vec3 toWorld(vec3 p)
{
    return toWorldDirection(p) + global.CameraTranslation.xyz;
}

float seconds()
{
    return global.Time > 0.0 ? global.Time : float(global.FrameCount) / 60.0;
}

float hash12(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float valueNoise(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
               mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// direzione verso la luna nello spazio di vista (y del mondo PS1 verso il basso)
vec3 moonDir()
{
    float yaw = radians(global.GM_MOON_YAW), pitch = radians(global.GM_MOON_PITCH);
    vec3 world = normalize(vec3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw)));
    return normalize(global.CameraAvailable > 0.5 ? toView(world) : vec3(world.xy, -world.z));
}

// rumore per pixel che cambia a ogni fotogramma: con l'accumulo temporale si media
float ign(vec2 pixel)
{
    pixel += 5.588238 * float(global.FrameCount % 16u);
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}
