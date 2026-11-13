#version 140
#include "colormanagement.glsl"

uniform sampler2D sampler;
uniform int textureWidth;
uniform int textureHeight;

uniform float uProgress;
uniform float uOpening;
uniform float uSeed;
uniform float uDuration;

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
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + vec2(17.1, 9.7);
        a *= 0.5;
    }
    return v;
}

vec3 flameColor(float h) {
    vec3 white = vec3(1.0, 0.9, 0.6);
    vec3 yellow = vec3(1.0, 0.62, 0.12);
    vec3 orange = vec3(0.95, 0.26, 0.04);
    vec3 red = vec3(0.52, 0.06, 0.02);
    vec3 ash = vec3(0.16, 0.03, 0.02);
    vec3 c = mix(white, yellow, smoothstep(0.0, 0.1, h));
    c = mix(c, orange, smoothstep(0.08, 0.34, h));
    c = mix(c, red, smoothstep(0.3, 0.7, h));
    c = mix(c, ash, smoothstep(0.65, 1.0, h));
    return c;
}

void main() {
    vec2 uv = vec2(texcoord0.x, 1.0 - texcoord0.y);
    vec2 size = vec2(float(textureWidth), float(textureHeight));
    vec4 src = texture(sampler, texcoord0);
    float a0 = src.a;
    vec3 base = a0 > 0.0 ? src.rgb / a0 : vec3(0.0);

    float p = mix(uProgress, 1.0 - uProgress, uOpening);
    p = p * p * (3.0 - 2.0 * p);

    float t = uProgress * max(uDuration, 0.2);
    vec2 np = uv * size / 140.0 + vec2(uSeed, uSeed * 0.37);
    float n = fbm(np + vec2(0.0, t * 1.6));
    float n2 = fbm(np * 2.3 - vec2(t * 0.9, t * 2.4));

    float band = 0.28;
    float height = 1.0 - uv.y;
    float field = height * 0.66 + n * 0.34 + (n2 - 0.5) * 0.06;
    float front = p * (1.0 + band) - band * 0.1;
    float k = front - field;

    float heat = clamp(k / band, 0.0, 1.0);
    float ragged = heat + (n2 - 0.5) * 0.55;
    float alive = 1.0 - smoothstep(0.3, 1.0, ragged);

    float flicker = 0.62 + 0.55 * n2;
    vec3 fire = flameColor(clamp(heat + (n2 - 0.5) * 0.3, 0.0, 1.0)) * flicker;

    float charred = smoothstep(-0.12, 0.0, k);
    vec3 lit = mix(base, base * vec3(0.3, 0.16, 0.12), charred);

    float body = smoothstep(0.0, 0.05, k);
    vec3 col = mix(lit, fire, body);
    float alpha = a0 * alive;

    float rim = smoothstep(-0.1, 0.0, k) * (1.0 - smoothstep(0.0, 0.1, k));
    float glowMask = smoothstep(-0.14, 0.0, k) * (1.0 - smoothstep(band * 0.5, band * 1.0, k));
    vec3 rgb = col * alpha + flameColor(0.18 + 0.4 * (1.0 - n2)) * glowMask * (0.25 + 0.5 * n2) * a0 + vec3(1.0, 0.5, 0.12) * rim * 0.35 * a0;
    float outA = clamp(alpha + glowMask * 0.12 * a0, 0.0, 1.0);

    float embers = step(0.992, hash(floor(uv * size / 4.0) + uSeed)) * glowMask * a0;
    rgb += vec3(1.0, 0.55, 0.15) * embers;
    outA = max(outA, embers);

    vec4 outColor = vec4(rgb, outA);
    outColor.rgb = min(outColor.rgb, vec3(outA));
    fragColor = outColor;
    fragColor = sourceEncodingToNitsInDestinationColorspace(fragColor);
    fragColor = nitsToDestinationEncoding(fragColor);
}
