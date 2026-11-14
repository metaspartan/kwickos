#version 140
#include "colormanagement.glsl"

uniform sampler2D sampler;
uniform int textureWidth;
uniform int textureHeight;

uniform float uProgress;
uniform float uClock;
uniform float uSeed;

in vec2 texcoord0;
out vec4 fragColor;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + vec2(13.1, 7.7);
        a *= 0.5;
    }
    return v;
}

vec3 ember(float h) {
    vec3 c = mix(vec3(1.0, 0.95, 0.7), vec3(1.0, 0.62, 0.15), smoothstep(0.0, 0.35, h));
    c = mix(c, vec3(0.9, 0.25, 0.05), smoothstep(0.3, 0.7, h));
    return mix(c, vec3(0.25, 0.06, 0.03), smoothstep(0.7, 1.0, h));
}

float particles(vec2 pos, float scale, float speed, float seed, float t, float zone) {
    vec2 g = vec2(pos.x, -pos.y) / scale;
    g.y += t * speed / scale;
    vec2 id = floor(g);
    vec2 f = fract(g) - 0.5;
    float h = hash(id + seed);
    float h2 = hash(id * 1.7 + seed + 3.1);
    f.x += sin(t * (2.0 + h * 3.0) + h * 6.28) * 0.32;
    float d = length(f - (vec2(h, h2) - 0.5) * 0.45);
    float life = fract(h2 * 5.0 + t * 0.3);
    return smoothstep(0.24, 0.0, d) * step(0.72, h) * (1.0 - life) * zone;
}

void main() {
    vec2 size = vec2(float(textureWidth), float(textureHeight));
    vec2 mg = vec2(clamp(0.25 * size.x, 80.0, 280.0), clamp(0.6 * size.y, 160.0, 460.0));
    vec2 S = 1.0 + 2.0 * mg / size;
    vec2 tc = (texcoord0 - 0.5) * S + 0.5;
    vec2 pxp = (tc - 0.5) * size;
    vec2 inWin = step(vec2(0.0), tc) * step(tc, vec2(1.0));
    float inside = inWin.x * inWin.y;

    float p = clamp(uProgress, 0.0, 1.0);
    float t = uClock;

    vec2 np = vec2(tc.x * size.x, (1.0 - tc.y) * size.y) / 170.0 + vec2(uSeed, uSeed * 0.61);
    float n = fbm(np);
    float n2 = fbm(np * 2.3 + 7.0);
    float field = n * 0.62 + (1.0 - tc.y) * 0.28 + 0.1;
    float thr = mix(-0.1, 1.05, p);
    float k = thr - field;

    float gone = smoothstep(0.0, 0.16, k);
    vec2 wind = vec2(0.35, 0.9) + (vec2(fbm(np * 1.6 + 3.0), fbm(np * 1.6 + 9.0)) - 0.5) * 1.2;
    vec2 off = wind * gone * gone * (0.16 + 0.03 * sin(t * 5.0 + n * 8.0));
    vec4 src = texture(sampler, clamp(tc - off, 0.001, 0.999)) * inside;
    float a0 = src.a;

    float front = exp(-pow((k - 0.02) / 0.03, 2.0));
    float halo = exp(-pow((k - 0.05) / 0.16, 2.0));
    float flick = 0.7 + 0.5 * n2 + 0.2 * sin(t * 14.0 + n * 20.0);
    vec3 edgeCol = ember(clamp(0.1 + 0.5 * (1.0 - n2) + max(k, 0.0) * 1.5, 0.0, 1.0));

    float visible = 1.0 - gone;
    vec3 rgb = src.rgb * visible;
    float a = a0 * visible;
    rgb += edgeCol * front * flick * 0.75 * a0;
    rgb += edgeCol * halo * 0.14 * a0 * visible;
    a = max(a, front * 0.45 * a0);

    float zone = smoothstep(-0.05, 0.12, k) * (1.0 - smoothstep(0.35, 0.9, k)) * smoothstep(0.02, 0.1, p) * (1.0 - smoothstep(0.88, 1.0, p));
    vec2 beyond = max(max(-tc, tc - 1.0), 0.0) * size / mg;
    zone *= (1.0 - smoothstep(0.3 + 0.3 * n2, 0.95, beyond.x)) * (1.0 - smoothstep(0.3 + 0.3 * n2, 0.95, beyond.y));
    float sp = particles(pxp, 6.0, 90.0, uSeed, t * 2.0, zone);
    sp += particles(pxp, 10.0, 140.0, uSeed + 5.0, t * 2.4, zone) * 0.9;
    sp += particles(pxp, 16.0, 210.0, uSeed + 11.0, t * 1.9, zone) * 0.8;
    vec3 spCol = ember(0.05 + 0.4 * hash(floor(pxp / 4.0)));
    rgb += spCol * sp * 1.3;
    a = max(a, clamp(sp, 0.0, 1.0));

    float haze = zone * smoothstep(0.45, 0.75, fbm(np * 1.2 + vec2(0.0, -t * 1.2))) * 0.18;
    rgb += vec3(0.22, 0.12, 0.08) * haze;
    a = max(a, haze);

    vec4 outColor = vec4(min(rgb, vec3(a + 0.6)), clamp(a, 0.0, 1.0));
    fragColor = outColor;
    fragColor = sourceEncodingToNitsInDestinationColorspace(fragColor);
    fragColor = nitsToDestinationEncoding(fragColor);
}
