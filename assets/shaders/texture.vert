#version 330 core

layout (location = 0) in vec3 pos;
layout (location = 1) in vec2 uv;

out vec2 v_uv;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

void main() {
    gl_Position = projection * view * model * vec4(pos, 1.0);
    v_uv = uv;
}
