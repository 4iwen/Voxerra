#version 330 core

struct Material {
    sampler2D diffuse;
    sampler2D specular;
    vec3 diffuse_color;
    vec3 specular_color;
    vec3 tint;
    float shininess;
    float alpha;
    float alpha_cutoff;
    mat3 uv_transform;
    int blend_mode;
};

in vec2 v_uv;
in vec3 v_world_position;

uniform Material u_material;
uniform vec3 u_view_position;
uniform int u_fog_enabled;
uniform vec4 u_fog_color;
uniform float u_fog_near;
uniform float u_fog_far;
uniform int u_render_mode;

#define RENDER_MODE_LIT 0
#define RENDER_MODE_UNLIT 1
#define RENDER_MODE_LIGHTING_ONLY 2
#define RENDER_MODE_ALBEDO 3

out vec4 color;

void main() {
    vec4 sample_color = texture(u_material.diffuse, v_uv);
    float alpha = sample_color.a * u_material.alpha;
    if (alpha < u_material.alpha_cutoff) {
        discard;
    }

    vec3 rgb = sample_color.rgb * u_material.diffuse_color * u_material.tint;
    if (u_render_mode == RENDER_MODE_ALBEDO) {
        rgb = sample_color.rgb;
    } else if (u_render_mode == RENDER_MODE_LIGHTING_ONLY) {
        rgb = vec3(1.0);
    }

    if (u_fog_enabled != 0) {
        float view_distance = distance(u_view_position, v_world_position);
        float fog_factor = clamp(
            (u_fog_far - view_distance) / max(u_fog_far - u_fog_near, 0.0001),
            0.0,
            1.0
        );
        rgb = mix(u_fog_color.rgb, rgb, fog_factor);
    }

    color = vec4(rgb, alpha);
}
