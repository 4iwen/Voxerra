#version 330 core

layout (location = 0) in vec3 a_position;
layout (location = 3) in vec2 a_uv;

uniform mat4 u_model;
uniform mat4 u_view;
uniform mat4 u_projection;
uniform mat3 u_uv_transform;

out vec2 v_uv;
out float v_view_depth;

void main() {
    v_uv = (u_uv_transform * vec3(a_uv, 1.0)).xy;
    vec4 world_position = u_model * vec4(a_position, 1.0);
    vec4 view_position = u_view * world_position;
    v_view_depth = max(-view_position.z, 0.0);
    gl_Position = u_projection * view_position;
}
