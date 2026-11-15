#version 140
#include "colormanagement.glsl"

uniform sampler2D sampler;
uniform vec2 uHalf;
uniform vec3 uNormal;
uniform float uEased;
uniform float uProgress;
uniform float uClock;
uniform float uOpacity;
uniform float uDistance;
uniform int uPass;

in vec2 texcoord0;
in vec2 vLocal;
in vec3 vWorld;

out vec4 fragColor;

vec4 blurred(vec2 uv, float radius)
{
    vec2 px = radius / vec2(textureSize(sampler, 0));
    vec4 c = texture(sampler, uv) * 0.25;
    c += texture(sampler, uv + vec2(px.x, 0.0)) * 0.125;
    c += texture(sampler, uv - vec2(px.x, 0.0)) * 0.125;
    c += texture(sampler, uv + vec2(0.0, px.y)) * 0.125;
    c += texture(sampler, uv - vec2(0.0, px.y)) * 0.125;
    c += texture(sampler, uv + px) * 0.0625;
    c += texture(sampler, uv - px) * 0.0625;
    c += texture(sampler, uv + vec2(px.x, -px.y)) * 0.0625;
    c += texture(sampler, uv + vec2(-px.x, px.y)) * 0.0625;
    return c;
}

void main()
{
    float e = clamp(uEased, 0.0, 1.0);
    float fade = (1.0 - smoothstep(0.45, 1.0, clamp(uProgress, 0.0, 1.0))) * uOpacity;

    if (uPass == 1) {
        float a = 0.0;
        float r = 3.0 + 14.0 * e;
        a += blurred(texcoord0, r).a * 0.5;
        a += blurred(texcoord0, r * 2.2).a * 0.5;
        a *= 0.42 * e * fade;
        fragColor = vec4(0.0, 0.0, 0.02 * a, a);
        fragColor = sourceEncodingToNitsInDestinationColorspace(fragColor);
        fragColor = nitsToDestinationEncoding(fragColor);
        return;
    }

    vec4 src = texture(sampler, texcoord0);
    float soft = e * e * 1.6;
    if (soft > 0.02) {
        src = mix(src, blurred(texcoord0, soft), clamp(e * 1.4, 0.0, 1.0));
    }

    vec3 n = normalize(uNormal);
    vec3 V = normalize(vec3(0.0, 0.0, uDistance) - vWorld);
    if (dot(n, V) < 0.0) {
        n = -n;
    }
    float nv = clamp(dot(n, V), 0.0, 1.0);

    vec3 L = normalize(vec3(-0.38, 0.62, 0.69));
    vec3 L2 = normalize(vec3(0.72, -0.25, 0.64));
    float diff = max((dot(n, L) + 0.25) / 1.25, 0.0);
    float diff2 = max(dot(n, L2), 0.0);
    float lit = 0.5 + 0.42 * diff + 0.12 * diff2;
    float lit0 = 0.5 + 0.42 * max((L.z + 0.25) / 1.25, 0.0) + 0.12 * L2.z;
    float shade = mix(1.0, lit / lit0, e);

    vec3 H = normalize(L + V);
    float nh = max(dot(n, H), 0.0);
    float spec = pow(nh, 70.0) * 0.8 + pow(nh, 14.0) * 0.12;
    vec3 H2 = normalize(L2 + V);
    float spec2 = pow(max(dot(n, H2), 0.0), 40.0) * 0.28;

    float fres = 0.03 + 0.97 * pow(1.0 - nv, 4.0);
    vec3 sky = mix(vec3(0.62, 0.76, 1.0), vec3(0.95, 0.97, 1.0), nv);

    float depth = clamp(-vWorld.z / (uDistance * 0.9), 0.0, 1.0);
    float fog = 1.0 - 0.3 * depth - 0.12 * e;

    vec2 inset = uHalf - abs(vLocal);
    vec2 fw = max(fwidth(vLocal), vec2(1e-4));
    float cover = clamp(min(inset.x / fw.x, inset.y / fw.y) + 0.5, 0.0, 1.0);
    float solid = smoothstep(0.88, 1.0, src.a);
    float edgeAA = mix(1.0, cover, solid);

    float edge = max(min(inset.x, inset.y), 0.0);
    float rim = (1.0 - clamp(edge / 3.0, 0.0, 1.0)) * (0.2 + 0.5 * (1.0 - nv)) * e * solid;

    float a = src.a * fade * edgeAA;

    vec3 rgb = src.rgb * shade * fog * fade * edgeAA;
    rgb += vec3(1.0) * (spec + spec2) * e * src.a * fade * edgeAA;
    rgb += sky * fres * e * 0.55 * src.a * fade * edgeAA;
    rgb += sky * rim * src.a * fade * edgeAA;

    fragColor = vec4(min(rgb, vec3(a + 0.45)), a);
    fragColor = sourceEncodingToNitsInDestinationColorspace(fragColor);
    fragColor = nitsToDestinationEncoding(fragColor);
}
