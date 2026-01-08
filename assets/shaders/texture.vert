#version 330 core

layout (location = 0) in vec3 pos;
layout (location = 1) in vec3 normal;
layout (location = 2) in vec3 tangent;
layout (location = 3) in vec2 uv;

uniform mat4 u_projection;
uniform mat4 u_view;
uniform mat4 u_model;

out vec2 v_uv;

void main() {
    gl_Position = u_projection * u_view * u_model * vec4(pos, 1.0);
    v_uv = uv;
}
