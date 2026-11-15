#version 140

uniform mat4 uMvp;
uniform mat4 uWorld;
uniform vec2 uHalf;

in vec4 position;
in vec4 texcoord;

out vec2 texcoord0;
out vec2 vLocal;
out vec3 vWorld;

void main()
{
    texcoord0 = texcoord.xy;
    vLocal = vec2(position.x - uHalf.x, uHalf.y - position.y);
    vWorld = (uWorld * vec4(position.xy, 0.0, 1.0)).xyz;
    gl_Position = uMvp * vec4(position.xy, 0.0, 1.0);
}
