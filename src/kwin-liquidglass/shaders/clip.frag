#version 140

uniform sampler2D uTex;
uniform vec4 uRect;
uniform float uRadius;

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
    float d = sdRound(vPx - uRect.xy, b, min(uRadius, min(b.x, b.y)));
    float cover = clamp(0.5 - d, 0.0, 1.0);
    if (cover <= 0.0) {
        discard;
    }
    fragColor = texture(uTex, vUv) * cover;
}
