#version 140
#include "colormanagement.glsl"

uniform sampler2D sampler;
uniform vec2 uHalf;
uniform vec3 uNormal;
uniform float uEased;
uniform float uProgress;
uniform float uOpacity;
uniform float uDistance;
uniform int uPass;
uniform mat4 uQuad;
uniform float uSigma;
uniform float uShadow;

in vec2 texcoord0;
in vec2 vLocal;
in vec2 vPos;
in vec3 vWorld;

out vec4 fragColor;

float erfApprox(float x)
{
    float s = sign(x);
    float a = abs(x);
    float k = 1.0 + (0.278393 + (0.230389 + 0.078108 * a * a) * a) * a;
    k *= k;
    return s - s / (k * k);
}

float quadDistance(vec2 p)
{
    float d = 1e20;
    float s = 1.0;
    for (int i = 0; i < 4; i++) {
        int j = (i + 3) - 4 * ((i + 3) / 4);
        vec2 vi = uQuad[i].xy;
        vec2 vj = uQuad[j].xy;
        vec2 e = vj - vi;
        vec2 w = p - vi;
        vec2 b = w - e * clamp(dot(w, e) / max(dot(e, e), 1e-6), 0.0, 1.0);
        d = min(d, dot(b, b));
        bvec3 c = bvec3(p.y >= vi.y, p.y < vj.y, e.x * w.y > e.y * w.x);
        if (all(c) || all(not(c))) {
            s = -s;
        }
    }
    return s * sqrt(d);
}

void main()
{
    float e = clamp(uEased, 0.0, 1.0);
    float fade = (1.0 - smoothstep(0.45, 1.0, clamp(uProgress, 0.0, 1.0))) * uOpacity;

    if (uPass == 1) {
        float d = quadDistance(vPos);
        float sigma = max(uSigma, 0.5);
        float tight = 0.5 - 0.5 * erfApprox(d / (sigma * 1.41421356));
        float wide = 0.5 - 0.5 * erfApprox(d / (sigma * 2.54558441));
        float a = clamp((tight * 0.72 + wide * 0.28) * uShadow, 0.0, 1.0);
        fragColor = vec4(0.0, 0.0, 0.0, a);
        fragColor = sourceEncodingToNitsInDestinationColorspace(fragColor);
        fragColor = nitsToDestinationEncoding(fragColor);
        return;
    }

    vec4 src = texture(sampler, texcoord0);

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
    float shade = min(mix(1.0, lit / lit0, e), 1.03);

    vec3 H = normalize(L + V);
    float nh = max(dot(n, H), 0.0);
    float spec = pow(nh, 70.0) * 0.8 + pow(nh, 14.0) * 0.12;
    vec3 H2 = normalize(L2 + V);
    float spec2 = pow(max(dot(n, H2), 0.0), 40.0) * 0.28;

    float fres = 0.04 + 0.96 * pow(1.0 - nv, 5.0);
    vec3 sky = mix(vec3(0.62, 0.76, 1.0), vec3(0.95, 0.97, 1.0), nv);

    float depth = clamp(-vWorld.z / (uDistance * 0.9), 0.0, 1.0);
    float fog = 1.0 - 0.3 * depth - 0.12 * e;

    vec2 inset = uHalf - abs(vLocal);
    vec2 fw = max(fwidth(vLocal), vec2(1e-4));
    float cover = clamp(min(inset.x / fw.x, inset.y / fw.y) + 0.5, 0.0, 1.0);
    float solid = smoothstep(0.88, 1.0, src.a);
    float edgeAA = mix(1.0, cover, solid);
    float halo = mix(1.0 - e, 1.0, cover);
    float body = cover * smoothstep(0.5, 1.0, src.a) * e;

    float edge = max(min(inset.x, inset.y), 0.0);
    float rim = (1.0 - clamp(edge / 3.0, 0.0, 1.0)) * (0.2 + 0.5 * (1.0 - nv)) * solid;

    float k = fade * edgeAA * halo;
    float a = src.a * k;
    vec3 rgb = src.rgb * shade * fog * (1.0 - 0.45 * fres * body) * k;
    vec3 gloss = vec3(spec + spec2) + sky * (fres * 0.45 + rim);
    rgb += gloss * body * fade * edgeAA;

    fragColor = vec4(min(rgb, vec3(a + 0.3 * body * fade)), a);
    fragColor = sourceEncodingToNitsInDestinationColorspace(fragColor);
    fragColor = nitsToDestinationEncoding(fragColor);
}
