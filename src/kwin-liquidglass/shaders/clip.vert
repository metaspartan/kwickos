#version 140

uniform mat4 uMvp;

in vec4 position;
in vec4 texcoord;

out vec2 vUv;
out vec2 vPx;

void main()
{
    vUv = texcoord.xy;
    vPx = position.xy;
    gl_Position = uMvp * vec4(position.xy, 0.0, 1.0);
}
