#define KWIN_LEGACY
#include "colormanagement.glsl"

uniform sampler2D sampler;
uniform int textureWidth;
uniform int textureHeight;

uniform float uProgress;
uniform float uClock;
uniform float uSeed;

varying vec2 texcoord0;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + vec2(13.1, 7.7);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 size = vec2(float(textureWidth), float(textureHeight));
    vec2 tc = texcoord0;
    float p = clamp(uProgress, 0.0, 1.0);

    vec2 np = tc * size / 120.0 + vec2(uSeed, uSeed * 0.61);
    float n = fbm(np);
    float sweep = tc.y * 0.35 + (1.0 - tc.x) * 0.15;
    float field = n * 0.65 + sweep;
    float thr = mix(-0.08, 1.12, p);
    float k = clamp((thr - field) * 5.0, 0.0, 1.0);

    vec2 grain = floor(tc * size / 3.0);
    float g = hash(grain + uSeed);
    float gone = step(g, k * 1.15 - 0.08);

    vec2 wind = vec2(0.5, 0.9) + (vec2(fbm(np * 1.7 + 3.0), fbm(np * 1.7 + 9.0)) - 0.5) * 1.4;
    vec2 off = wind * k * k * (0.22 + 0.04 * sin(uClock * 6.0 + n * 9.0));
    vec4 src = texture2D(sampler, clamp(tc - off, 0.001, 0.999));
    float a0 = src.a;

    float edge = smoothstep(0.0, 0.06, k) * (1.0 - smoothstep(0.06, 0.32, k));
    vec3 glowA = vec3(1.0, 0.78, 0.35);
    vec3 glowB = vec3(0.95, 0.3, 0.12);
    vec3 glow = mix(glowA, glowB, smoothstep(0.1, 0.8, k) + (n - 0.5) * 0.4);

    float visible = (1.0 - gone) * (1.0 - smoothstep(0.55, 1.0, k));
    float dust = gone * (1.0 - smoothstep(0.4, 1.0, k)) * (1.0 - smoothstep(0.7, 1.0, p));
    float dustPix = dust * smoothstep(0.55, 0.8, hash(grain * 1.37 + 5.0)) * a0;

    vec3 rgb = src.rgb * visible;
    float a = a0 * visible;
    rgb += glow * edge * 0.75 * a0 * (1.0 - gone * 0.6);
    a = max(a, edge * 0.5 * a0);
    vec3 dustCol = mix(src.rgb / max(a0, 0.001), glow * vec3(1.0, 0.7, 0.5), 0.45);
    rgb += dustCol * dustPix * 0.75;
    a = max(a, dustPix * 0.85);

    vec4 outColor = vec4(min(rgb, vec3(a + 0.5)), clamp(a, 0.0, 1.0));
    gl_FragColor = outColor;
    fragColor = sourceEncodingToNitsInDestinationColorspace(fragColor);
    fragColor = nitsToDestinationEncoding(fragColor);
}
