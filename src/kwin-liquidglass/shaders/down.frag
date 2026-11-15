#version 140

uniform sampler2D uTex;
uniform vec2 uHalf;
uniform float uOffset;

in vec2 vUv;

out vec4 fragColor;

void main()
{
    vec2 o = uHalf * uOffset;
    vec4 sum = texture(uTex, vUv) * 4.0;
    sum += texture(uTex, vUv - o);
    sum += texture(uTex, vUv + o);
    sum += texture(uTex, vUv + vec2(o.x, -o.y));
    sum += texture(uTex, vUv - vec2(o.x, -o.y));
    fragColor = sum / 8.0;
}
