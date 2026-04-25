#version 330 core

layout (location = 0) in vec3 pos;

out vec3 v_tex_coords;

uniform mat4 u_projection;
uniform mat4 u_view;

void main() {
    v_tex_coords = pos;
    vec4 clip_pos = u_projection * u_view * vec4(pos, 1.0);
    gl_Position = clip_pos.xyww;
}
