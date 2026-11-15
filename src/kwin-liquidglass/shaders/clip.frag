#version 140

uniform sampler2D uTex;
uniform vec4 uRect;
uniform float uRadius;
uniform vec3 uShadow;
uniform float uStroke;
uniform float uScale;

in vec2 vUv;
in vec2 vPx;

out vec4 fragColor;

float sdRound(vec2 p, vec2 b, float r)
{
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void main()
{
    vec2 b = uRect.zw;
    float r = min(uRadius, min(b.x, b.y));
    vec2 p = vPx - uRect.xy;
    float d = sdRound(p, b, r);
    float cover = clamp(0.5 - d, 0.0, 1.0);

    float shadow = 0.0;
    if (uShadow.x > 0.0 && cover < 1.0) {
        float sigma = max(uShadow.z, 1.0);
        float s = sdRound(p - vec2(0.0, uShadow.y), b, r);
        float t = clamp((s + sigma * 0.6) / (sigma * 3.2), 0.0, 1.0);
        float soft = (1.0 - t) * (1.0 - t) * (1.0 - t);
        float contact = 1.0 - smoothstep(0.0, 4.0 * uScale, d);
        shadow = uShadow.x * (soft + 0.12 * contact);
    }

    if (cover <= 0.0 && shadow < 0.002) {
        discard;
    }

    vec4 win = texture(uTex, vUv) * cover;
    if (uStroke > 0.0) {
        float line = clamp(1.0 - abs(d + 0.5 * uScale) / (0.75 * uScale), 0.0, 1.0) * cover;
        win.rgb = mix(win.rgb, vec3(win.a), uStroke * line);
    }
    fragColor = win + vec4(0.0, 0.0, 0.0, shadow * (1.0 - win.a));
}
