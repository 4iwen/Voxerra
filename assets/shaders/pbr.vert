#version 330 core

layout (location = 0) in vec3 a_position;
layout (location = 1) in vec3 a_normal;
layout (location = 2) in vec3 a_tangent;
layout (location = 3) in vec2 a_uv;

uniform mat4 u_projection;
uniform mat4 u_view;
uniform mat4 u_model;
uniform mat3 u_normal_matrix;

out vec2 v_uv;
out vec3 v_world_position;
out vec3 v_normal;
out mat3 v_tbn;

void main() {
    v_uv = a_uv;
    v_world_position = vec3(u_model * vec4(a_position, 1.0));
    v_normal = u_normal_matrix * a_normal;

    // calculate tbn
    vec3 t = normalize(u_normal_matrix * a_tangent);
    vec3 n = normalize(v_normal);
    // gram schmidt
    t = normalize(t - dot(t, n) * n);
    vec3 b = cross(n, t);
    v_tbn = mat3(t, b, n);

    gl_Position = u_projection * u_view * vec4(v_world_position, 1.0);
}
