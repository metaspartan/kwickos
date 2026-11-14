#define KWIN_LEGACY
#include "colormanagement.glsl"

uniform sampler2D sampler;
uniform int textureWidth;
uniform int textureHeight;

uniform float uProgress;
uniform float uClock;
uniform float uSeed;
uniform float uStyle;

varying vec2 texcoord0;

vec3 rotAxis(vec3 v, vec3 ax, float c, float s) {
    return v * c + cross(ax, v) * s + ax * dot(ax, v) * (1.0 - c);
}

void main() {
    vec2 hs = vec2(float(textureWidth), float(textureHeight)) * 0.5;
    vec2 pix = (texcoord0 - 0.5) * 2.0 * hs;

    float p = clamp(uProgress, 0.0, 1.0);
    float e = p * p * (3.0 - 2.0 * p);
    float big = max(hs.x, hs.y);
    float D = big * 3.4;

    vec3 ax = vec3(0.0, 1.0, 0.0);
    vec2 piv = vec2(0.0);
    float maxA = 1.36;
    float sgn = 1.0;
    float depth = 0.55;
    if (uStyle > 1.5) {
        ax = vec3(1.0, 0.0, 0.0);
        piv = vec2(0.0, -hs.y);
        maxA = 1.25;
        sgn = -1.0;
        depth = 0.25;
    } else if (uStyle > 0.5) {
        piv = vec2(-hs.x, 0.0);
        maxA = 1.15;
        sgn = -1.0;
        depth = 0.35;
    }
    float ang = sgn * maxA * e;
    float c = cos(ang);
    float s = sin(ang);
    float zt = -depth * big * e;

    vec3 n = rotAxis(vec3(0.0, 0.0, 1.0), ax, c, s);

    vec3 c0 = rotAxis(vec3(-hs.x - piv.x, -hs.y - piv.y, 0.0), ax, c, s) + vec3(piv, zt);
    vec3 c1 = rotAxis(vec3(hs.x - piv.x, -hs.y - piv.y, 0.0), ax, c, s) + vec3(piv, zt);
    vec3 c2 = rotAxis(vec3(-hs.x - piv.x, hs.y - piv.y, 0.0), ax, c, s) + vec3(piv, zt);
    vec3 c3 = rotAxis(vec3(hs.x - piv.x, hs.y - piv.y, 0.0), ax, c, s) + vec3(piv, zt);
    vec2 s0 = c0.xy * D / (D - c0.z);
    vec2 s1 = c1.xy * D / (D - c1.z);
    vec2 s2 = c2.xy * D / (D - c2.z);
    vec2 s3 = c3.xy * D / (D - c3.z);
    vec2 ext = max(max(abs(s0), abs(s1)), max(abs(s2), abs(s3)));
    float f = min(1.0, min(hs.x / max(ext.x, 1.0), hs.y / max(ext.y, 1.0)));

    vec2 sp = pix / f;
    vec3 dir = vec3(sp, -D);
    vec3 pp = vec3(piv, zt);
    float den = dot(dir, n);
    if (abs(den) < 0.0001) {
        gl_FragColor = vec4(0.0);
        return;
    }
    float t = dot(pp - vec3(0.0, 0.0, D), n) / den;
    vec3 q = vec3(0.0, 0.0, D) + t * dir;
    vec3 loc = rotAxis(q - pp, ax, c, -s);
    vec2 w = loc.xy + piv;

    float edge = min(min(w.x + hs.x, hs.x - w.x), min(w.y + hs.y, hs.y - w.y));
    float inside = clamp(edge / (1.5 / max(f, 0.2)), 0.0, 1.0);
    if (t <= 0.0 || inside <= 0.0) {
        gl_FragColor = vec4(0.0);
        return;
    }

    vec2 tuv = (w / hs) * 0.5 + 0.5;
    vec4 src = texture2D(sampler, tuv);

    vec3 L = normalize(vec3(-0.4, 0.5, 0.78));
    float lit = 0.5 + 0.5 * max(dot(n, L), 0.0);
    float lit0 = 0.5 + 0.5 * L.z;
    float shade = lit / lit0;
    vec3 refl = reflect(-L, n);
    float sweep = 0.5 + 0.5 * sin(w.x / hs.x * 2.2 + uClock * 5.0);
    float sheen = pow(max(refl.z, 0.0), 14.0) * (0.35 + 0.35 * sweep) * e;
    float depthFog = 1.0 - 0.35 * e;
    float side = smoothstep(0.0, 0.5, w.x / hs.x * 0.5 + 0.5);

    float rim = (1.0 - clamp(edge / 4.0, 0.0, 1.0)) * 0.28 * e;
    float fade = 1.0 - smoothstep(0.45, 1.0, p);
    float a = src.a * inside * fade;

    vec3 rgb = src.rgb * shade * depthFog * inside * fade;
    rgb += vec3(0.85, 0.92, 1.0) * (sheen * (0.6 + 0.4 * side) + rim) * src.a * inside * fade;

    vec4 outColor = vec4(min(rgb, vec3(a + 0.4)), a);
    gl_FragColor = outColor;
    fragColor = sourceEncodingToNitsInDestinationColorspace(fragColor);
    fragColor = nitsToDestinationEncoding(fragColor);
}
