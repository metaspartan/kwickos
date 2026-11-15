#version 140
#include "colormanagement.glsl"

uniform sampler2D sampler;
uniform vec2 uHalf;
uniform vec3 uNormal;
uniform float uEased;
uniform float uProgress;
uniform float uClock;
uniform float uOpacity;

in vec2 texcoord0;
in vec2 vLocal;

out vec4 fragColor;

void main()
{
    vec4 src = texture(sampler, texcoord0);
    float e = clamp(uEased, 0.0, 1.0);
    vec3 n = normalize(uNormal);

    vec3 L = normalize(vec3(-0.4, 0.5, 0.78));
    float lit = 0.5 + 0.5 * max(dot(n, L), 0.0);
    float lit0 = 0.5 + 0.5 * L.z;
    float shade = lit / lit0;
    vec3 refl = reflect(-L, n);
    float u = vLocal.x / max(uHalf.x, 1.0);
    float sweep = 0.5 + 0.5 * sin(u * 2.2 + uClock * 5.0);
    float sheen = pow(max(refl.z, 0.0), 14.0) * (0.35 + 0.35 * sweep) * e;
    float depthFog = 1.0 - 0.35 * e;
    float side = smoothstep(0.0, 0.5, u * 0.5 + 0.5);

    vec2 inset = uHalf - abs(vLocal);
    float edge = min(inset.x, inset.y);
    float rim = edge >= 0.0 ? (1.0 - clamp(edge / 4.0, 0.0, 1.0)) * 0.28 * e : 0.0;
    float fade = (1.0 - smoothstep(0.45, 1.0, clamp(uProgress, 0.0, 1.0))) * uOpacity;
    float a = src.a * fade;

    vec3 rgb = src.rgb * shade * depthFog * fade;
    rgb += vec3(0.85, 0.92, 1.0) * (sheen * (0.6 + 0.4 * side) + rim) * src.a * fade;

    fragColor = vec4(min(rgb, vec3(a + 0.4)), a);
    fragColor = sourceEncodingToNitsInDestinationColorspace(fragColor);
    fragColor = nitsToDestinationEncoding(fragColor);
}
