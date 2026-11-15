#version 140

uniform sampler2D uTex;
uniform vec2 uHalf;
uniform float uOffset;

in vec2 vUv;

out vec4 fragColor;

void main()
{
    vec2 o = uHalf * uOffset;
    vec4 sum = texture(uTex, vUv + vec2(-o.x * 2.0, 0.0));
    sum += texture(uTex, vUv + vec2(-o.x, o.y)) * 2.0;
    sum += texture(uTex, vUv + vec2(0.0, o.y * 2.0));
    sum += texture(uTex, vUv + vec2(o.x, o.y)) * 2.0;
    sum += texture(uTex, vUv + vec2(o.x * 2.0, 0.0));
    sum += texture(uTex, vUv + vec2(o.x, -o.y)) * 2.0;
    sum += texture(uTex, vUv + vec2(0.0, -o.y * 2.0));
    sum += texture(uTex, vUv + vec2(-o.x, -o.y)) * 2.0;
    fragColor = sum / 12.0;
}
