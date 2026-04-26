#version 330 core

in vec2 v_uv;

uniform sampler2D u_diffuse;
uniform int u_use_alpha_test;
uniform float u_alpha_cutoff;
uniform float u_material_alpha;
uniform int u_object_id;

layout(location = 0) out uint out_object_id;

void main() {
    if (u_use_alpha_test != 0) {
        float alpha = texture(u_diffuse, v_uv).a * u_material_alpha;
        if (alpha < u_alpha_cutoff) {
            discard;
        }
    }

    out_object_id = uint(u_object_id);
}
