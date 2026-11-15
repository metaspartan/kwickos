#version 140

uniform sampler2D uTex;
uniform vec4 uRect;
uniform float uRadius;
uniform vec3 uShadow;
uniform vec2 uStroke;
uniform float uScale;

in vec2 vUv;
in vec2 vPx;

out vec4 fragColor;

float sdRound(vec2 p, vec2 b, float r)
{
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

float band(float d, float lo, float hi)
{
    return clamp(min(d - lo + 0.5, hi - d + 0.5), 0.0, 1.0);
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
        float t = clamp((s + sigma * 0.5) / (sigma * 3.0), 0.0, 1.0);
        float soft = (1.0 - t) * (1.0 - t) * (1.0 - t);
        float ambient = exp(-max(d, 0.0) / (5.0 * uScale));
        shadow = uShadow.x * soft + uShadow.x * 0.45 * ambient;
        shadow += uStroke.y * band(d, 0.0, uScale);
        shadow = min(shadow, 0.95);
    }

    if (cover <= 0.0 && shadow < 0.002) {
        discard;
    }

    vec4 win = texture(uTex, vUv) * cover;
    if (uStroke.x > 0.0) {
        float line = band(d, -uScale, 0.0) * cover;
        win.rgb = mix(win.rgb, vec3(win.a), uStroke.x * line);
    }
    fragColor = win + vec4(0.0, 0.0, 0.0, shadow * (1.0 - win.a));
}
