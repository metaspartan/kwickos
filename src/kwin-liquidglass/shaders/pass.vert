#version 140

uniform mat4 uMvp;

in vec4 position;
in vec4 texcoord;

out vec2 vUv;

void main()
{
    vUv = texcoord.xy;
    gl_Position = uMvp * vec4(position.xy, 0.0, 1.0);
}
