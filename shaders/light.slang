#version 450
// SPDX-License-Identifier: GPL-3.0-or-later
// Gallowmere - light: luce rifatta sulla scena
// Copyright (C) 2026
// Author: https://github.com/Leproide
//
// This program is free software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version. This program is distributed WITHOUT
// ANY WARRANTY. See <https://www.gnu.org/licenses/>.
//
// Per ogni pixel con geometria opaca sotto:
//   luce del gioco  = colore dei vertici x 2 (lineare), con occlusione ambientale
//   luce aggiunta   = luna (normale vera) + luci puntiformi di RecompOne (fiamme, magie)
//   rapporto        = (luce del gioco + luce aggiunta) / luce del gioco, limitato
//   colore          = immagine del gioco x rapporto
// Il rapporto si applica all'immagine del gioco, non alla ricomposizione: scritte, decalcomanie
// e trasparenze sopra la superficie prendono la stessa luce. Dove il gioco ha messo il nero
// (bordi della mappa, buchi) la luce del gioco e' zero e il pixel resta nero.
// Dove sopra la superficie il gioco ha disegnato altro (menu semitrasparenti, effetti, scritte:
// l'immagine non coincide con texture x vertici) la nuova luce vale solo in parte
// (GM_OVERLAY_LIGHT), cosi' un menu scuro sopra la scena non viene schiarito.
// Nebbia di distanza su tutta la geometria, tranne dove il gioco ha gia' portato il colore al nero.
// Uscita: rgb lineare, a = 1 dove la luce e' stata rifatta, 0 dove resta l'immagine del gioco.

#include "common.inc"

layout(set = 0, binding = 6) uniform sampler2D Source;
layout(set = 0, binding = 7) uniform sampler2D Original;
layout(set = 0, binding = 8) uniform sampler2D Surface;
layout(set = 0, binding = 9) uniform sampler2D SceneLights;
layout(set = 0, binding = 10) uniform sampler2D Emitters;
layout(set = 0, binding = 11) uniform sampler2D Atmos;

#include "vertex.inc"

const int MAX_LIGHTS = 32;

float attenuation(float distance, float radius)
{
    if (radius <= 0.0 || distance >= radius) return 0.0;
    float x = distance / radius;
    float window = 1.0 - x * x * x * x;
    window *= window;
    float core = radius * 0.3;
    return window / (1.0 + (distance * distance) / (core * core));
}

// ombra nello spazio schermo: si cammina dal punto verso la luce e si controlla se la
// profondita' della scena copre il percorso (solo occlusori vicini: niente ombre da oggetti
// molto piu' avanti). 1 = in luce.
float screenShadow(vec3 p, vec3 dir, float len)
{
    if (global.GM_SHADOWS <= 0.0) return 1.0;
    const int STEPS = 24;
    float jitter = ign(gl_FragCoord.xy);   // mediato dall'accumulo temporale
    vec3 start = p + dir * (2.0 + 0.004 * p.z);
    for (int i = 0; i < STEPS; i++)
    {
        float t = (float(i) + jitter) / float(STEPS);
        vec3 s = start + dir * len * t * t;
        if (s.z <= 1.0) break;
        vec2 uv = project(s);
        if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) break;
        float d = depthAt(uv);
        if (!hasGeometry(d)) continue;
        float diff = s.z - viewZ(d);
        float thickness = 60.0 + s.z * 0.01;
        if (diff > 1.0 + s.z * 0.002 && diff < thickness) return 1.0 - global.GM_SHADOWS;
    }
    return 1.0;
}

// tremolio delle luci color fuoco, legato alla posizione nel mondo
float flicker(vec3 position, vec3 color)
{
    if (global.GM_FLICKER <= 0.0) return 1.0;
    float warm = smoothstep(0.08, 0.35, color.r - color.b);
    if (warm <= 0.0) return 1.0;
    vec2 seed = floor(toWorld(position).xz / 96.0);
    float t = seconds();
    float n = valueNoise(vec2(t * 7.0, hash12(seed) * 97.0)) * 0.65 + valueNoise(vec2(t * 17.0, hash12(seed + 3.1) * 53.0)) * 0.35;
    return 1.0 + (n - 0.5) * 0.7 * warm * global.GM_FLICKER;
}

// cielo/ambiente notturno riflesso in una direzione (spazio di vista), se il riflesso esce dallo schermo
vec3 environment(vec3 r)
{
    float up = global.CameraAvailable > 0.5 ? -toWorldDirection(r).y : -r.y;
    vec3 night = toLinear(vec3(0.10, 0.13, 0.22));
    vec3 ground = toLinear(vec3(0.04, 0.045, 0.04));
    vec3 env = mix(ground, night, smoothstep(-0.2, 0.3, up));
    env += MOON_COLOR * global.GM_MOON * 0.8 * pow(max(dot(r, moonDir()), 0.0), 400.0);
    return env;
}

// riflesso nello spazio schermo: cammina lungo r e restituisce il colore del gioco dove colpisce
// la scena; altrove l'ambiente. a = 1 se ha colpito la scena.
// c'e' interfaccia (HUD, menu) sopra questo punto dello schermo? Non va riflessa ne' rifratta
float hudAt(vec2 uv)
{
    vec4 ui = uiLayer(uv);
    return max(1.0 - smoothstep(0.9, 0.99, ui.a), smoothstep(0.01, 0.05, luma(ui.rgb)));
}

vec4 reflection(vec3 p, vec3 r)
{
    // passi fissi (niente rumore per pixel, che senza accumulo temporale dava un effetto retinato)
    // e raffinamento binario dell'impatto, per riflessi netti
    const int STEPS = 40;
    float len = 400.0 + p.z * 0.3;
    vec3 start = p + r * (4.0 + p.z * 0.004);
    vec3 prev = start;
    for (int i = 1; i <= STEPS; i++)
    {
        float t = float(i) / float(STEPS);
        vec3 s = start + r * len * t * t;
        if (s.z <= 1.0) break;
        vec2 uv = project(s);
        if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) break;
        float d = depthAt(uv);
        if (hasGeometry(d))
        {
            float diff = s.z - viewZ(d);
            if (diff > 0.0 && diff < 40.0 + s.z * 0.02)
            {
                vec3 a = prev, b = s;
                for (int k = 0; k < 6; k++)
                {
                    vec3 m = (a + b) * 0.5;
                    float md = depthAt(project(m));
                    if (hasGeometry(md) && m.z > viewZ(md)) b = m; else a = m;
                }
                uv = project(b);
                vec2 edge = min(uv, 1.0 - uv);
                float fade = smoothstep(0.0, 0.1, min(edge.x, edge.y)) * (1.0 - smoothstep(0.6, 1.0, t));
                fade *= 1.0 - hudAt(uv);
                vec3 hit = toLinear(sceneUnderUi(texture(Original, uv).rgb, uiLayer(uv)));
                return vec4(mix(environment(r), min(hit, vec3(1.0)), fade), fade);
            }
        }
        prev = s;
    }
    // nessun impatto: il cielo del gioco in quella direzione se visibile, sfumato verso i bordi
    vec3 env = environment(r);
    vec3 far = p + r * 20000.0;
    if (far.z > 1.0)
    {
        vec2 uv = project(far);
        vec2 edge = min(uv, 1.0 - uv);
        float inside = smoothstep(0.0, 0.15, min(edge.x, edge.y)) * (1.0 - hudAt(clamp(uv, vec2(0.0), vec2(1.0))));
        if (inside > 0.0 && !hasGeometry(depthAt(clamp(uv, vec2(0.0), vec2(1.0)))))
            env = mix(env, min(toLinear(texture(Original, uv).rgb), vec3(0.6)), inside * 0.7);
    }
    return vec4(env, 0.0);
}

// quanto un pixel sembra metallo: argento (chiaro e poco saturo) o oro (giallo saturo e chiaro).
// Il gioco non dice di che materiale e' una superficie: oltre al tag "metallo" di RecompOne si
// stima dal colore della texture, e solo su superfici piccole e vicine (armi, scudi, armature).
float metalness(vec3 albedo, vec3 shade, int material, float z)
{
    if (material == MATERIAL_METAL) return 1.0;
    // texture marcate con un altro materiale (pietra, legno, ...): mai metallo
    if (material != 0 && material != MATERIAL_TRANSLUCENT) return 0.0;
    // stima dal colore solo sulle texture senza marcature, e solo se accesa
    if (global.GM_METAL_GUESS < 0.5) return 0.0;
    // il gioco non illumina personaggi e oggetti in mano (colore dei vertici neutro): il metallo
    // si cerca solo li', non sul paesaggio
    // personaggi e oggetti: luce dei vertici grigia (il terreno illuminato da fiaccole e luna e' colorato)
    float shi = max(shade.r, max(shade.g, shade.b)), slo = min(shade.r, min(shade.g, shade.b));
    float entity = (1.0 - smoothstep(0.04, 0.12, (shi - slo) / max(shi, 1e-3))) * smoothstep(0.2, 0.35, shi);
    float hi = max(albedo.r, max(albedo.g, albedo.b)), lo = min(albedo.r, min(albedo.g, albedo.b));
    float sat = hi > 0.0 ? (hi - lo) / hi : 0.0;
    // stretto: solo argento quasi bianco e oro vivo (lama, bordo dello scudo), non vesti e corpo
    float silver = smoothstep(0.62, 0.8, hi) * (1.0 - smoothstep(0.06, 0.14, sat));
    float gold = smoothstep(0.7, 0.88, hi) * smoothstep(0.55, 0.8, sat)
                 * smoothstep(0.1, 0.3, albedo.g - albedo.b) * (1.0 - smoothstep(0.25, 0.45, albedo.r - albedo.g));
    return max(silver, gold) * entity * (1.0 - smoothstep(500.0, 1100.0, z));
}

// ---------------------------------------------------------------- acqua
// wavedx/getwaves adattate da "Very fast procedural ocean" di afl_ext (vedi THIRD_PARTY.txt)
vec2 wavedx(vec2 position, vec2 direction, float frequency, float timeshift)
{
    float x = dot(direction, position) * frequency + timeshift;
    float wave = exp(sin(x) - 1.0);
    return vec2(wave, -wave * cos(x));
}

float getwaves(vec2 position)
{
    float phase = length(position) * 0.1;
    float iter = 0.0, frequency = 1.0, timeMul = 2.0, weight = 1.0, sum = 0.0, weights = 0.0;
    for (int i = 0; i < 10; i++)
    {
        vec2 d = vec2(sin(iter), cos(iter));
        vec2 res = wavedx(position, d, frequency, seconds() * timeMul + phase);
        position += d * res.y * weight * 0.38;
        sum += res.x * weight;
        weights += weight;
        weight = mix(weight, 0.0, 0.2);
        frequency *= 1.18;
        timeMul *= 1.07;
        iter += 1232.399963;
    }
    return sum / weights;
}

// normale delle onde nel mondo (y verso il basso)
// rumore di Perlin (gradiente) e fbm: increspature fini dell'acqua come normal/bump map procedurale
vec2 grad2(vec2 p)
{
    float a = hash12(p) * 6.2831853;
    return vec2(cos(a), sin(a));
}

float perlin(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = dot(grad2(i), f), b = dot(grad2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
    float c = dot(grad2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)), d = dot(grad2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float rippleHeight(vec2 xz)
{
    float t = seconds();
    vec2 p = xz / 90.0;
    float h = perlin(p + vec2(t * 0.35, t * 0.12)) * 0.5;
    h += perlin(p * 2.1 - vec2(t * 0.22, -t * 0.4)) * 0.25;
    h += perlin(p * 4.3 + vec2(-t * 0.5, t * 0.3)) * 0.125;
    return h;
}

// normale delle increspature nel mondo (y verso il basso), da differenze finite dell'altezza
vec3 rippleNormal(vec2 xz, float strength)
{
    const float e = 4.0;
    float h = rippleHeight(xz);
    float hx = rippleHeight(xz + vec2(e, 0.0)) - h;
    float hz = rippleHeight(xz + vec2(0.0, e)) - h;
    return normalize(vec3(-hx * strength, -e * 0.25, -hz * strength));
}

vec3 waveNormalAt(vec2 xz, float scale, float height)
{
    vec2 pos = xz * scale;
    float e = 0.05, h = height * global.GM_WATER_WAVES;
    vec3 a = vec3(pos.x, getwaves(pos) * h, pos.y);
    vec3 n = normalize(cross(a - vec3(pos.x - e, getwaves(pos - vec2(e, 0.0)) * h, pos.y),
                             a - vec3(pos.x, getwaves(pos + vec2(0.0, e)) * h, pos.y + e)));
    return vec3(n.x, -abs(n.y), n.z);
}

vec3 waveNormal(vec2 xz)
{
    return waveNormalAt(xz, 0.018, 0.55);
}

// onde grandi e lente: per il riflesso, che con le onde fini si sfilacciava ("spaghetti")
vec3 waveNormalLow(vec2 xz)
{
    return waveNormalAt(xz, 0.004, 0.35);
}


float caustics(vec2 xz)
{
    float t = seconds() * 0.7, c = 0.0;
    vec2 p = xz * 0.012;
    for (int i = 0; i < 3; i++)
    {
        vec2 q = p * (1.0 + float(i) * 0.6) + vec2(t * (0.3 + float(i) * 0.12), -t * 0.21);
        vec2 cell = abs(sin(q + sin(q.yx * 1.7 + t)));
        c += pow(1.0 - min(cell.x, cell.y), 8.0);
    }
    return c / 3.0;
}

// distanza (z di vista) della superficie dell'acqua in questo pixel; 0 se non c'e'
float waterSurfaceZ(vec2 uv)
{
    vec3 ray = vec3((uv - global.Projection.zw) * global.Projection.xy, 1.0);
    if (global.SceneWaterLevel.y > 0.5 && global.CameraAvailable > 0.5)
    {
        float eye = global.CameraTranslation.y;
        float level = global.SceneWaterLevel.x;
        vec3 wr = toWorldDirection(ray);
        if (eye < level && wr.y > 1e-5) return (level - eye) / wr.y;
        return 0.0;
    }
    float facing = dot(global.SceneWaterPlane.xyz, ray);
    if (dot(global.SceneWaterPlane.xyz, global.SceneWaterPlane.xyz) > 0.5 && abs(facing) > 1e-5)
    {
        float z = global.SceneWaterPlane.w / facing;
        return z > 1.0 ? z : 0.0;
    }
    return 0.0;
}

// posizione 3D di una cella di luce degli effetti. Sopra l'acqua la profondita' e' quella del fondo:
// l'effetto (fuoco, magie) sta invece sopra la superficie, quindi lo si mette li', un po' piu' in alto
vec3 emitterPos(vec3 at)
{
    float z = at.z;
    float wz = waterSurfaceZ(at.xy);
    vec3 ep = vec3((at.xy - global.Projection.zw) * global.Projection.xy * z, z) * 0.97;
    if (wz > 1.0 && wz < z)
    {
        ep = vec3((at.xy - global.Projection.zw) * global.Projection.xy * wz, wz);
        if (global.CameraAvailable > 0.5) ep += toView(vec3(0.0, -120.0, 0.0)) - toView(vec3(0.0));
    }
    return ep;
}

vec3 shadeWater(vec3 gameColor, vec3 surface, vec3 bottomP, vec3 fogColor)
{
    vec3 v = -normalize(surface);
    vec3 world = toWorld(surface);
    // onde (afl_ext) + increspature di Perlin, sfumate con la distanza per non sfarfallare
    float near = 1.0 - smoothstep(1500.0, 5000.0, surface.z);
    vec3 nw = normalize(waveNormal(world.xz) + (rippleNormal(world.xz, 3.0 * global.GM_WATER_WAVES) - vec3(0.0, -1.0, 0.0)) * 0.6 * near);
    vec3 n = global.CameraAvailable > 0.5 ? normalize(toView(nw)) : vec3(0.0, -1.0, 0.0);
    if (dot(n, v) < 0.0) n = -n;
    float thickness = max(length(bottomP) - length(surface), 0.0);

    // fondo rifratto
    vec2 shift = (n.xy - dot(n, v) * v.xy) * 0.035 * clamp(thickness / 120.0, 0.0, 1.0) / (1.0 + surface.z * 0.0004);
    vec2 ruv = vTexCoord + shift;
    vec3 bottom = gameColor;
    if (all(greaterThan(ruv, vec2(0.0))) && all(lessThan(ruv, vec2(1.0))))
    {
        float rd = depthAt(ruv);
        if (hasGeometry(rd) && viewZ(rd) > surface.z && hudAt(ruv) < 0.5) bottom = toLinear(sceneUnderUi(texture(Original, ruv).rgb, uiLayer(ruv)));
    }
    vec3 floorWorld = toWorld(bottomP);
    bottom += bottom * MOON_COLOR * caustics(floorWorld.xz) * exp(-thickness * 0.012) * global.GM_CAUSTICS * 2.0;

    vec3 transmit = exp(-thickness * vec3(1.0, 0.42, 0.3) / 100.0 * global.GM_WATER_DENSITY);
    vec3 scatter = vec3(0.007, 0.024, 0.03) * (0.6 + MOON_COLOR * global.GM_MOON);
    vec3 volume = bottom * transmit + scatter * (1.0 - transmit);

    float facing = max(dot(n, v), 0.0);
    float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
    // il riflesso usa una superficie piu' calma delle onde, cosi' le forme riflesse restano leggibili
    vec3 up = global.CameraAvailable > 0.5 ? normalize(toView(vec3(0.0, -1.0, 0.0))) : vec3(0.0, 1.0, 0.0);
    vec3 lowW = normalize(waveNormalLow(world.xz) + (rippleNormal(world.xz, 1.2 * global.GM_WATER_WAVES) - vec3(0.0, -1.0, 0.0)) * 0.35 * near);
    vec3 low = global.CameraAvailable > 0.5 ? normalize(toView(lowW)) : up;
    if (dot(low, v) < 0.0) low = -low;
    vec3 rn = normalize(mix(up, low, 0.6));
    vec3 r = reflect(-v, rn);
    vec4 refl = reflection(surface, r);
    float amount = mix(0.12, 1.0, fresnel) + 0.35 * refl.a;
    vec3 col = mix(volume, min(refl.rgb, vec3(0.5)) * 0.9, clamp(amount, 0.0, 0.9) * global.GM_WATER);
    // riva: acqua bassa trasparente e un filo di schiuma dove tocca la terra
    float shore = 1.0 - smoothstep(0.0, 30.0, thickness);
    float foam = smoothstep(0.55, 0.8, perlin(world.xz / 40.0 + seconds() * 0.15) * 0.5 + 0.5) * shore;
    col = mix(col, gameColor, shore * 0.6);
    col += vec3(0.5, 0.6, 0.6) * (0.03 + 0.1 * MOON_COLOR.b * global.GM_MOON) * foam;
    // luci (fiaccole, fuoco, fonti di vita) riflesse sull'acqua: riflesso stretto lungo le onde
    vec3 lightsOn = vec3(0.0);
    int lc = min(int(global.SceneLightCount + 0.5), 32);
    for (int i = 0; i < lc; i++)
    {
        vec4 pl = texelFetch(SceneLights, ivec2(i * 2, 0), 0);
        vec3 lcol = toLinear(texelFetch(SceneLights, ivec2(i * 2 + 1, 0), 0).rgb);
        vec3 ld = normalize(pl.xyz - surface);
        float reach = attenuation(length(pl.xyz - surface), max(pl.w * global.GM_LAMP_RANGE, global.GM_LAMP_MIN) * 2.0);
        // solo il riflesso stretto lungo le onde, non una macchia su tutta l'acqua
        lightsOn += lcol / max(luma(lcol), 0.2) * 0.25 * global.GM_LAMPS * pow(max(dot(r, ld), 0.0), 250.0) * (0.3 + 0.7 * reach);
    }
    for (int cy = 0; cy < 9; cy++)
    for (int cx = 0; cx < 16; cx++)
    {
        vec3 ec = texelFetch(Emitters, ivec2(cx * 2, cy), 0).rgb;
        if (luma(ec) < 0.0005) continue;
        vec3 at = texelFetch(Emitters, ivec2(cx * 2 + 1, cy), 0).xyz;
        vec3 ep = emitterPos(at);
        vec3 ld = normalize(ep - surface);
        float reach = attenuation(length(ep - surface), global.GM_GLOW_RANGE * 2.0);
        // effetti bianchi (spruzzi, schiuma) non contano: solo luci colorate (fuoco, fonti di vita)
        float hi = max(ec.r, max(ec.g, ec.b)), lo = min(ec.r, min(ec.g, ec.b));
        float colored = smoothstep(0.25, 0.55, (hi - lo) / max(hi, 1e-4));
        lightsOn += toLinear(min(ec * 3.0, vec3(1.0))) * colored * global.GM_GLOW * 0.4 * pow(max(dot(r, ld), 0.0), 120.0) * reach;
    }
    col += lightsOn * global.GM_WATER;
    float glint = max(dot(r, moonDir()), 0.0);
    col += MOON_COLOR * global.GM_MOON * (pow(glint, 24.0) * 0.06 + pow(glint, 600.0) * 1.2) * global.GM_WATER * (1.0 - shore);
    return col;
}

// normale smussata: media delle normali vicine sulla stessa superficie (profondita' continua e
// angolo sotto ~50 gradi), come lo smooth shading. Senza, la luce nuova mostrava i poligoni.
vec3 smoothNormal(vec2 uv, vec3 p, vec3 n)
{
    if (global.GM_SMOOTH <= 0.0) return n;
    vec2 px = global.ShadingSize.zw;
    float radius = clamp(3000.0 / p.z, 3.0, 24.0);
    vec3 sum = n;
    float total = 1.0;
    for (int i = 0; i < 16; i++)
    {
        float a = float(i) * 2.399963;
        float r = radius * sqrt((float(i) + 0.5) / 16.0);
        vec2 suv = uv + vec2(cos(a), sin(a)) * r * px;
        float sd = depthAt(suv);
        if (!hasGeometry(sd)) continue;
        vec3 sn = texture(Surface, suv).xyz;
        float similar = smoothstep(0.6, 0.85, dot(sn, n));
        float near = 1.0 - smoothstep(0.02, 0.06, abs(viewZ(sd) - p.z) / p.z);
        float w = similar * near;
        sum += sn * w;
        total += w;
    }
    return normalize(mix(n, sum / total, global.GM_SMOOTH));
}

vec3 hashColor(float id)
{
    vec3 h = fract(sin(vec3(id * 12.9898, id * 78.233, id * 37.719)) * 43758.5453);
    return 0.25 + 0.75 * h;
}

void main()
{
    vec3 original = texture(Original, vTexCoord).rgb;
    vec4 albedo = texture(Albedo, vTexCoord);
    float d = depthAt(vTexCoord);
    int view = int(global.GM_VIEW + 0.5);

    vec4 atmosSky = texture(Atmos, ATMOS_SKY);
    vec4 atmosScene = texture(Atmos, ATMOS_SCENE);
    float openness = clamp((atmosSky.a - 0.3) / 0.7, 0.0, 1.0);
    float outdoor = mix(1.0, openness, global.GM_INDOOR);
    // colore della nebbia: il cielo del livello, spinto verso la tinta "maledetta", piu' scuro al chiuso
    // la tinta della maledizione cambia solo la tonalita' della nebbia, non la scurisce
    vec3 skyHue = mix(atmosSky.rgb, CURSE_FOG * (luma(atmosSky.rgb) / luma(CURSE_FOG)), global.GM_CURSE);
    vec3 fogColor = max(skyHue, vec3(0.02, 0.025, 0.03)) * global.GM_FOG_BRIGHT * mix(0.5, 1.0, outdoor);
    vec3 viewDir = normalize(vec3((vTexCoord - global.Projection.zw) * global.Projection.xy, 1.0));
    float towardMoon = max(dot(viewDir, moonDir()), 0.0);
    vec3 moonHaze = MOON_COLOR * global.GM_MOON * global.GM_MOON_HAZE * outdoor * (0.01 + 0.05 * pow(towardMoon, 4.0) + 0.2 * pow(towardMoon, 32.0));
    fogColor += moonHaze;
    float down = global.CameraAvailable > 0.5 ? toWorldDirection(viewDir).y : -viewDir.y;

    // lago (livello dell'acqua del fork, SceneWaterLevel): il gioco non disegna la superficie, solo
    // qualche scintilla sul nero. Dove il raggio di vista incontra il livello prima della geometria
    // (o senza geometria sotto) si disegna l'acqua, con il fondo se c'e' e acqua profonda se no
    if (global.GM_WATER > 0.0 && global.SceneWaterLevel.y > 0.5 && gbuffer() && global.DepthAvailable > 0.5 &&
        atmosScene.z >= 0.01 && view == 0)
    {
        float lakeZ = waterSurfaceZ(vTexCoord);
        bool geo = hasGeometry(d);
        if (lakeZ > 1.0 && (!geo || lakeZ < viewZ(d)))
        {
            vec3 ray = vec3((vTexCoord - global.Projection.zw) * global.Projection.xy, 1.0);
            vec3 surface = ray * lakeZ;
            vec3 bottomP = geo ? viewPos(vTexCoord, d) : ray * (lakeZ + 600.0);
            vec3 under = geo ? toLinear(sceneUnderUi(original, uiLayer(vTexCoord))) : vec3(0.0);
            vec3 col = shadeWater(under, surface, bottomP, fogColor);
            float ld = length(surface);
            float lf = clamp((ld - global.GM_FOG_START) / max(global.GM_FOG_END - global.GM_FOG_START, 1.0), 0.0, 1.0) * global.GM_FOG;
            float lh = (1.0 - exp(-max(ld - 150.0, 0.0) / 2500.0)) * global.GM_HAZE;
            float limit = atmosScene.x;
            float fade = limit > 500.0 ? smoothstep(limit * 0.75, limit * 0.97, surface.z) * global.GM_EDGE : 0.0;
            FragColor = vec4(mix(mix(col, fogColor, max(lf, lh)), vec3(0.0), fade), 1.0);
            return;
        }
    }

    if (!gbuffer() || !hasGeometry(d))
    {
        // schermate 2D e menu (niente scena 3D): immagine del gioco
        if (!gbuffer() || atmosScene.z < 0.01 || global.DepthAvailable < 0.5 || view != 0)
        {
            FragColor = vec4(view == 0 ? toLinear(original) : vec3(0.0), view == 0 ? 0.0 : 1.0);
            return;
        }
        // cielo e fondale (montagne, pareti dipinte): foschia del colore del cielo, piu' fitta
        // all'orizzonte e anche appena sotto (le montagne sfumano come in lontananza)
        vec4 sui = uiLayer(vTexCoord);
        vec3 sky = toLinear(sceneUnderUi(original, sui));
        float band = exp(-abs(down) / 0.12);
        vec3 skyHaze = max(skyHue, vec3(0.02, 0.025, 0.03)) * mix(0.5, 1.0, outdoor) + moonHaze;
        sky = mix(sky, skyHaze, global.GM_FOG_SKY * mix(0.2, 1.0, band));
        // vuoto oltre i bordi della mappa al nero: sotto l'orizzonte, dove il raggio incontrerebbe il
        // terreno (quota stimata in atmos) entro il limite di disegno, cioe' dove il terreno dovrebbe
        // esserci e non c'e'. Oltre il limite e' fondale lontano (montagne) e resta con la foschia.
        // Solo dove il fondale e' scuro: nelle caverne il fondale 2D sono le pareti e si tiene
        float voidLike = 1.0 - smoothstep(0.1, 0.22, luma(original));
        vec4 atmosFloor = texture(Atmos, ATMOS_FLOOR);
        float voidAmount = smoothstep(0.04, 0.16, down);
        if (atmosFloor.y > 0.5 && global.CameraAvailable > 0.5 && down > 0.0)
        {
            float hit = max(atmosFloor.x - global.CameraTranslation.y, 0.0) / down;
            float reach = max(atmosScene.x, 3000.0);
            voidAmount = (1.0 - smoothstep(reach, reach * 1.6, hit)) * smoothstep(0.0, 0.01, down);
        }
        sky = mix(sky, vec3(0.0), voidAmount * global.GM_EDGE * voidLike);
        FragColor = vec4(sky, 1.0);
        return;
    }

    vec4 ui = uiLayer(vTexCoord);
    vec3 scene = sceneUnderUi(original, ui);
    vec3 p = viewPos(vTexCoord, d);
    // nebbia: lineare tra Fog start e Fog end, piu' una foschia esponenziale che si vede gia' da vicino;
    // dove il gioco ha portato il colore al nero (bordi, buchi) non schiarisce
    float dist = length(p);
    float linearFog = clamp((dist - global.GM_FOG_START) / max(global.GM_FOG_END - global.GM_FOG_START, 1.0), 0.0, 1.0);
    float haze = (1.0 - exp(-max(dist - 150.0, 0.0) / 2500.0)) * global.GM_HAZE;
    float keepDark = smoothstep(0.002, 0.03, luma(scene));
    float fogAmount = clamp(max(linearFog * global.GM_FOG, haze), 0.0, 1.0) * keepDark;
    // limite di disegno: la geometria vicina al limite sfuma al nero, come nell'originale
    float limit = atmosScene.x;
    float edgeFade = limit > 500.0 ? smoothstep(limit * 0.75, limit * 0.97, p.z) * global.GM_EDGE * smoothstep(0.005, 0.03, atmosScene.y + 0.01) : 0.0;
    // foschia a terra: nelle zone piu' basse della telecamera, cresce con la distanza
    if (global.GM_MIST > 0.0 && global.CameraAvailable > 0.5)
    {
        float below = toWorld(p).y - global.CameraTranslation.y;   // y del mondo verso il basso
        float ground = smoothstep(0.0, global.GM_MIST_HEIGHT, below);
        float far = 1.0 - exp(-max(length(p) - 400.0, 0.0) / 6000.0);
        float n = 0.6 + 0.4 * valueNoise(toWorld(p).xz / 900.0 + vec2(seconds() * 0.05, 0.0));
        fogAmount = max(fogAmount, global.GM_MIST * outdoor * ground * far * n * keepDark);
    }

    // geometria solo trasparente (acqua, effetti): niente luce nuova, solo nebbia
    // acqua: superficie davanti alla geometria (livello del lago o piano di RecompOne, o materiale)
    float waterZ = waterSurfaceZ(vTexCoord);
    int waterMat = global.MaterialAvailable > 0.5 ? int(texture(Material, vTexCoord).r * 255.0 + 0.5) : 0;
    if (global.GM_WATER > 0.0 && waterMat == MATERIAL_WATER)
    {
        vec3 ray = vec3((vTexCoord - global.Projection.zw) * global.Projection.xy, 1.0);
        if (waterZ <= 1.0 || waterZ > p.z) waterZ = p.z;
        vec3 col = shadeWater(toLinear(scene), ray * waterZ, p, fogColor);
        float wf = clamp((length(ray * waterZ) - global.GM_FOG_START) / max(global.GM_FOG_END - global.GM_FOG_START, 1.0), 0.0, 1.0) * global.GM_FOG;
        FragColor = view == 0 ? vec4(mix(mix(col, fogColor, max(wf, haze)), vec3(0.0), edgeFade), 1.0) : vec4(0.0, 0.3, 0.6, 1.0);
        return;
    }

    if (albedo.a < 0.5)
    {
        FragColor = view == 0 ? vec4(mix(mix(toLinear(scene), fogColor, fogAmount), vec3(0.0), edgeFade), 1.0) : vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    vec3 shade = texture(Shading, vTexCoord).rgb;
    vec4 surface = texture(Surface, vTexCoord);
    vec3 n = smoothNormal(vTexCoord, viewPos(vTexCoord, d), surface.xyz);
    float ao = clamp(mix(1.0, surface.a, global.GM_AO), 0.0, 1.0);
    vec3 v = normalize(-p);

    // luce del gioco (moltiplicatore lineare della texture)
    vec3 game = toLinear(shade * 2.0);

    // luna
    vec3 l = moonDir();
    float moonNdl = max(dot(n, l), 0.0);
    float moonShadow = moonNdl > 0.0 ? screenShadow(p, l, global.GM_SHADOW_LENGTH) : 1.0;
    vec3 moon = MOON_COLOR * global.GM_MOON * moonNdl * ao * moonShadow * outdoor;
    // cielo notturno: luce diffusa da tutto il cielo, piu' da sopra, anche di spalle alla luna;
    // un po' di luce rimbalzata dal terreno sotto e un bordo di controluce
    vec3 worldN = global.CameraAvailable > 0.5 ? toWorldDirection(n) : vec3(n.x, -n.y, n.z);
    float upN = -worldN.y;
    vec3 skyFill = MOON_COLOR * (0.18 + 0.22 * max(upN, 0.0)) + vec3(0.06, 0.07, 0.05) * max(-upN, 0.0);
    float back = pow(1.0 - max(dot(n, v), 0.0), 3.0) * max(dot(-v, l), 0.0);
    moon += (skyFill * ao + MOON_COLOR * back * 0.5) * global.GM_MOON * global.GM_SKY_FILL * outdoor;
    vec3 h = normalize(l + v);
    vec3 spec = MOON_COLOR * global.GM_MOON * pow(max(dot(n, h), 0.0), 40.0) * moonNdl * moonShadow;

    // luci puntiformi (posizioni nello spazio di vista)
    vec3 lamps = vec3(0.0);
    float strongest = 0.0;
    vec3 strongestDir = vec3(0.0);
    float strongestDist = 0.0;
    vec3 strongestLight = vec3(0.0);
    int count = min(int(global.SceneLightCount + 0.5), MAX_LIGHTS);
    for (int i = 0; i < count; i++)
    {
        vec4 placement = texelFetch(SceneLights, ivec2(i * 2, 0), 0);
        vec3 color = toLinear(texelFetch(SceneLights, ivec2(i * 2 + 1, 0), 0).rgb);
        vec3 toLight = placement.xyz - p;
        float dist = length(toLight);
        float att = attenuation(dist, max(placement.w * global.GM_LAMP_RANGE, global.GM_LAMP_MIN));
        if (att <= 0.0) continue;
        vec3 ld = toLight / max(dist, 1e-3);
        float ndl = max(dot(n, ld), 0.0);
        vec3 lit = color * att * global.GM_LAMPS * flicker(placement.xyz, color);
        vec3 contribution = lit * (0.25 + 0.75 * ndl);
        lamps += contribution;
        spec += lit * pow(max(dot(n, normalize(ld + v)), 0.0), 40.0) * ndl;
        if (luma(contribution) > strongest)
        {
            strongest = luma(contribution);
            strongestDir = ld;
            strongestDist = dist;
            strongestLight = contribution;
        }
    }
    // luci degli effetti come punti 3D (fonti di vita, magie): illuminano da ogni lato
    if (global.GM_GLOW > 0.0)
    {
        for (int cy = 0; cy < 9; cy++)
        for (int cx = 0; cx < 16; cx++)
        {
            vec3 ec = texelFetch(Emitters, ivec2(cx * 2, cy), 0).rgb;
            if (luma(ec) < 0.0005) continue;
            vec3 at = texelFetch(Emitters, ivec2(cx * 2 + 1, cy), 0).xyz;
            // l'effetto sta davanti alla superficie su cui e' disegnato, un po' piu' in alto
            vec3 ep = emitterPos(at);
            if (global.CameraAvailable > 0.5) ep += toView(vec3(0.0, -80.0, 0.0)) - toView(vec3(0.0));
            vec3 toE = ep - p;
            float dist = length(toE);
            float att = attenuation(dist, global.GM_GLOW_RANGE);
            if (att <= 0.0) continue;
            vec3 ld = toE / max(dist, 1e-3);
            float ndl = clamp((dot(n, ld) + 0.35) / 1.35, 0.0, 1.0);
            float ehi = max(ec.r, max(ec.g, ec.b)), elo = min(ec.r, min(ec.g, ec.b));
            float ecol = mix(0.3, 1.0, smoothstep(0.25, 0.55, (ehi - elo) / max(ehi, 1e-4)));
            vec3 lit = toLinear(min(ec * 3.0, vec3(1.0))) * ecol * att * global.GM_GLOW;
            lamps += lit * ndl;
            spec += lit * pow(max(dot(n, normalize(ld + v)), 0.0), 40.0) * ndl;
        }
    }

    // ombra della luce che conta di piu' nel punto
    if (strongest > 0.01)
        lamps -= strongestLight * (1.0 - screenShadow(p, strongestDir, min(strongestDist, global.GM_SHADOW_LENGTH * 2.0)));

    // l'ombra (della luna, sulle superfici rivolte verso di lei) scurisce anche la luce del gioco,
    // che non ha ombre degli oggetti: senza, le ombre restavano un velo
    float castShadow = moonNdl > 0.0 ? (1.0 - moonShadow) / max(global.GM_SHADOWS, 1e-3) : 0.0;
    // solo sul terreno (superfici rivolte in alto): su Dan e sugli oggetti sottili l'ombra calcolata
    // sull'immagine si proietta su se stessa e li anneriva
    float gameShadow = 1.0 - clamp(castShadow, 0.0, 1.0) * global.GM_SHADOW_GAME * outdoor * smoothstep(0.5, 0.8, upN);
    vec3 light = game * ao * gameShadow * global.GM_GAME_LIGHT + moon + lamps;
    vec3 ratio = clamp(light / max(game, vec3(0.03)), 0.0, global.GM_MAX_BOOST);

    // quanto l'immagine coincide con la superficie sotto (1 = solo superficie)
    vec3 delta = abs(min(albedo.rgb * shade * 2.0, 1.0) - scene);
    float surfaceOnly = 1.0 - smoothstep(0.04, 0.2, max(delta.r, max(delta.g, delta.b)));
    int material = global.MaterialAvailable > 0.5 ? int(texture(Material, vTexCoord).r * 255.0 + 0.5) : 0;
    if (material == MATERIAL_TRANSLUCENT) surfaceOnly *= 0.5;
    ratio = mix(vec3(1.0), ratio, mix(global.GM_OVERLAY_LIGHT, 1.0, surfaceOnly));
    // pannello scuro sopra la scena (menu di pausa, inventario disegnati nella scena): l'immagine del
    // gioco e' molto piu' scura della superficie sotto. Li' niente luce nuova e pannello piu' coprente
    vec3 rebuiltLin = toLinear(min(albedo.rgb * shade * 2.0, 1.0));
    float panelDark = smoothstep(0.45, 0.2, luma(toLinear(scene)) / max(luma(rebuiltLin), 0.02)) * smoothstep(0.05, 0.15, luma(rebuiltLin));
    ratio = mix(ratio, vec3(1.0 - global.GM_MENU_OPACITY * 0.6), panelDark);
    // dissolvenze al nero del gioco (avvio, cambi di scena): la luce del gioco va a zero ovunque e
    // la luce aggiunta schiarirebbe la scena che sta sparendo. Li' l'immagine resta quella del gioco
    ratio = mix(vec3(1.0), ratio, smoothstep(0.505, 0.525, atmosScene.w));
    vec3 col = toLinear(scene) * ratio;
    // riflessi: solo dove il gioco ha luce (niente riflessi sul nero dei bordi)
    col += spec * global.GM_SPECULAR * smoothstep(0.0, 0.1, luma(game)) * luma(toLinear(albedo.rgb)) * surfaceOnly;

    // metallo: riflesso della scena (o dell'ambiente) tinto dal colore del metallo e riflessi forti
    float metal = global.GM_METAL > 0.0 ? metalness(albedo.rgb, shade, material, p.z) * surfaceOnly : 0.0;
    // vetro e superfici bagnate marcate: riflesso non tinto, piu' debole
    bool clearRefl = material == MATERIAL_GLASS || material == MATERIAL_WET;
    if (clearRefl) metal = (material == MATERIAL_GLASS ? 0.6 : 0.35) * surfaceOnly;
    if (metal > 0.01)
    {
        vec3 r = reflect(-v, n);
        vec3 tint = clearRefl ? vec3(0.7) : toLinear(albedo.rgb);
        float fresnel = 0.6 + 0.4 * pow(1.0 - max(dot(n, v), 0.0), 3.0);
        // riflesso: scena colpita, altrimenti l'immagine nella direzione del riflesso (ambiente vicino)
        vec4 hit = reflection(p, r);
        vec2 around = clamp(vTexCoord + r.xy * vec2(0.18, -0.18), vec2(0.0), vec2(1.0));
        vec3 near = mix(toLinear(sceneUnderUi(texture(Original, around).rgb, uiLayer(around))) * 1.5, vec3(0.0), hudAt(around)) + environment(r);
        // riflesso "da studio": cielo chiaro sopra, terreno scuro sotto, per dare forma al metallo
        float upR = global.CameraAvailable > 0.5 ? -toWorldDirection(r).y : r.y;
        vec3 studio = mix(vec3(0.03), MOON_COLOR * 0.6, smoothstep(-0.1, 0.5, upR));
        vec3 env = (mix(near, hit.rgb, hit.a) + studio) * mix(tint, vec3(luma(tint)), 0.3) * fresnel;
        float k = metal * min(global.GM_METAL, 1.0);
        col = mix(col, col * 0.5 + env * 1.6, k);
        // riflessi netti di luna e luci, piu' forti e stretti sul metallo
        col += spec * tint * 6.0 * metal * global.GM_METAL;
        col += MOON_COLOR * global.GM_MOON * pow(max(dot(r, moonDir()), 0.0), 120.0) * 2.0 * k;
    }
    col = mix(col, fogColor, fogAmount);
    col = mix(col, vec3(0.0), edgeFade);

    if (view == 0) FragColor = vec4(col, 1.0);
    else if (view == 1) FragColor = vec4(toLinear(albedo.rgb), 1.0);
    else if (view == 2) FragColor = vec4(toLinear(shade), 1.0);
    else if (view == 3) FragColor = vec4(toLinear(n * 0.5 + 0.5), 1.0);
    else if (view == 4) FragColor = vec4(toLinear(hashColor(triangleId(vTexCoord))), 1.0);
    else if (view == 5) FragColor = vec4(vec3(fract(log2(viewZ(d)) * 0.5)), 1.0);
    else if (view == 6)
    {
        int m = global.MaterialAvailable > 0.5 ? int(texture(Material, vTexCoord).r * 255.0 + 0.5) : 0;
        FragColor = vec4(m == 0 ? toLinear(scene) * 0.1 : toLinear(hashColor(float(m) * 7.0)), 1.0);
    }
    else if (view == 7) FragColor = vec4(vec3(ao), 1.0);
    else if (view == 8) FragColor = vec4(toLinear(clamp(ratio / global.GM_MAX_BOOST, 0.0, 1.0)), 1.0);
    else if (view == 9) FragColor = vec4(moon + lamps, 1.0);
    else if (view == 10) FragColor = vec4(mix(toLinear(scene) * 0.2, vec3(1.0, 0.6, 0.0), metal), 1.0);
    else FragColor = vec4(toLinear(scene) * 0.2, 1.0);
}
