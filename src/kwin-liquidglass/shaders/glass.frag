#version 140

uniform sampler2D uSharp;
uniform sampler2D uBlur;
uniform sampler2D uMean;
uniform vec2 uSize;
uniform vec4 uRect;
uniform vec4 uShape;
uniform float uRadius;
uniform float uBevel;
uniform float uRefract;
uniform float uFrost;
uniform float uDisperse;
uniform float uSpec;
uniform float uTint;
uniform float uStyle;
uniform float uOpacity;
uniform float uScale;
uniform vec2 uLight;
uniform vec3 uPointer;
uniform float uShadow;
uniform float uSat;
uniform vec2 uDark;
uniform float uMul;
uniform float uVeil;

in vec2 vUv;

out vec4 fragColor;

float sdRound(vec2 p, vec2 b, float r)
{
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

vec2 edgeNormal(vec2 p, vec2 b, float r)
{
    vec2 s = vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
    vec2 q = abs(p) - b + vec2(r);
    if (q.x > 0.0 && q.y > 0.0) {
        return normalize(q) * s;
    }
    return q.x > q.y ? vec2(s.x, 0.0) : vec2(0.0, s.y);
}

vec2 uvAt(vec2 px)
{
    px = clamp(px, vec2(0.5), uSize - vec2(0.5));
    return vec2(px.x / uSize.x, 1.0 - px.y / uSize.y);
}

float luma(vec3 c)
{
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main()
{
    vec2 px = vUv;
    vec2 p = px - uRect.xy;
    vec2 b = uRect.zw;
    float r = min(uRadius, min(b.x, b.y));
    float d = sdRound(p, b, r);
    float cover = clamp(0.5 - d, 0.0, 1.0);
    if (cover <= 0.0) {
        float ds = sdRound(p - vec2(0.0, 2.5 * uScale), b, r);
        float sh = uShadow * uOpacity * exp(-max(ds, 0.0) / (5.0 * uScale)) * clamp(d, 0.0, 1.0);
        if (sh < 0.004) {
            discard;
        }
        fragColor = vec4(0.0, 0.0, 0.0, sh);
        return;
    }

    float bevel = max(uBevel, 1.0);
    float rn = min(max(r, bevel * 1.05), min(b.x, b.y));
    float dn = sdRound(p, b, rn);
    float t = max(-dn, 0.0);
    float x = clamp(t / bevel, 0.0, 1.0);
    vec2 n2 = edgeNormal(p, b, rn);

    float u = 1.0 - x;
    float slope = min(u / sqrt(max(1.0 - u * u, 0.004)), 7.0);
    vec3 N = normalize(vec3(n2 * slope, 1.0));
    vec3 T = refract(vec3(0.0, 0.0, -1.0), N, 1.0 / 1.5);
    float thick = bevel * 1.9 * uRefract;
    vec2 off = T.xy / max(-T.z, 0.3) * thick;

    float spread = 0.2 * uDisperse;
    vec2 base = px + off;
    vec3 sharp;
    sharp.r = texture(uSharp, uvAt(px + off * (1.0 - spread))).r;
    sharp.g = texture(uSharp, uvAt(base)).g;
    sharp.b = texture(uSharp, uvAt(px + off * (1.0 + spread))).b;
    vec3 soft;
    soft.r = texture(uBlur, uvAt(px + off * (1.0 - spread))).r;
    soft.g = texture(uBlur, uvAt(base)).g;
    soft.b = texture(uBlur, uvAt(px + off * (1.0 + spread))).b;

    float frost = uFrost * mix(0.3, 1.0, smoothstep(0.0, 0.7, x));
    vec3 col = mix(sharp, soft, frost);
    col = max(mix(vec3(luma(col)), col, uSat), vec3(0.0));
    col = mix(col, vec3(1.0), uVeil);

    vec2 sc = uShape.xy;
    vec2 sh = uShape.zw;
    vec3 m3 = texture(uMean, uvAt(sc)).rgb * 0.4;
    m3 += texture(uMean, uvAt(sc + vec2(sh.x * 0.6, 0.0))).rgb * 0.3;
    m3 += texture(uMean, uvAt(sc - vec2(sh.x * 0.6, 0.0))).rgb * 0.3;
    float m = mix(luma(m3), luma(soft), 0.35);

    if (uStyle < 0.5) {
        float darken = uTint * mix(uDark.x, uDark.y, smoothstep(0.3, 0.92, m));
        float lift = uTint * (1.0 - smoothstep(0.03, 0.25, m)) * 0.08;
        float k = clamp(darken, 0.0, 0.9);
        col = mix(mix(col, vec3(0.05, 0.055, 0.07), k), col * (1.0 - k), uMul) + vec3(lift);
    } else if (uStyle < 1.5) {
        float milk = uTint * mix(0.32, 0.14, smoothstep(0.3, 0.9, m));
        col = mix(col, vec3(0.97, 0.975, 0.99), clamp(milk, 0.0, 0.9));
    }

    vec2 L = normalize(uLight);
    float facing = dot(n2, L);
    float lit = max(facing, 0.0);
    float back = max(-facing, 0.0);
    float thin = exp(-t / (0.9 * uScale));
    float band = exp(-t / (bevel * 0.3));
    float spec = thin * (0.16 + 1.15 * pow(lit, 1.2) + 0.45 * pow(back, 1.6));
    spec += band * (0.24 * pow(lit, 3.0) + 0.10 * pow(back, 3.0));
    float fres = pow(1.0 - N.z, 2.0);
    float glow = u * u * 0.05;

    vec2 dp = px - uPointer.xy;
    float reach = 80.0 * uScale;
    float near = uPointer.z * exp(-dot(dp, dp) / (2.0 * reach * reach));

    col += vec3(spec * uSpec + near * 0.07 + near * thin * 0.55 * uSpec);
    col = mix(col, vec3(1.0), clamp((fres * 0.14 + glow) * uSpec, 0.0, 1.0));
    col += vec3((hash(px) - 0.5) / 255.0);
    col = clamp(col, 0.0, 1.0);

    float a = cover * uOpacity;
    fragColor = vec4(col * a, a);
}
