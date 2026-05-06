// File:        blinn_phong.vert
// Author:      Lukáš Bien
// Description: Transforms lit mesh vertices and forwards view-space depth.

#version 330 core

layout (location = 0) in vec3 a_position;
layout (location = 1) in vec3 a_normal;
layout (location = 2) in vec3 a_tangent;
layout (location = 3) in vec2 a_uv;

uniform mat4 u_model;
uniform mat4 u_view;
uniform mat4 u_projection;

out vec3 v_position;
out vec3 v_normal;
out vec2 v_uv;
out float v_view_depth;

void main() {
    v_position = vec3(u_model * vec4(a_position, 1.0));
    v_normal = mat3(transpose(inverse(u_model))) * a_normal;
    v_uv = a_uv;

    vec4 view_position = u_view * vec4(v_position, 1.0);
    v_view_depth = max(-view_position.z, 0.0);
    gl_Position = u_projection * view_position;
}
