// File:        skybox.frag
// Author:      Lukáš Bien
// Description: Draws either a cubemap skybox or procedural sky with fog mix.

#version 330 core

in vec3 v_tex_coords;

out vec4 color;

uniform int u_use_cubemap = 0;
uniform samplerCube u_skybox;
uniform vec3 u_top_color = vec3(0.1, 0.35, 0.8);
uniform vec3 u_bottom_color = vec3(0.6, 0.7, 0.9);
uniform vec3 u_ground_color = vec3(0.1, 0.1, 0.12);
uniform vec3 u_sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 u_sun_color = vec3(1.0, 0.95, 0.9);
uniform float u_sun_disk_size = 1;
uniform float u_sun_glow_power = 300.0;
uniform float u_sun_glow_strength = 0.5;
uniform int u_fog_enabled;
uniform vec4 u_fog_color;

const float SKYBOX_FOG_AMOUNT = 0.35;

// keep skybox fog capped so fogged skies still preserve highlights like the
// sun disk and bright cubemap features.
void main() {
    vec3 dir = normalize(v_tex_coords);
    vec3 final_color;

    if (u_use_cubemap != 0) {
        final_color = texture(u_skybox, dir).rgb;
    } else {
        float up_factor = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
        vec3 sky_base = mix(u_ground_color, u_bottom_color, min(up_factor * 2.0, 1.0));
        sky_base = mix(sky_base, u_top_color, max(dir.y, 0.0));
        float sun_dot = dot(dir, normalize(u_sun_direction));
        float sun_disk = smoothstep(u_sun_disk_size - 0.002, u_sun_disk_size, sun_dot);
        float sun_glow = pow(max(sun_dot, 0.0), u_sun_glow_power) * u_sun_glow_strength;

        final_color = sky_base + (u_sun_color * sun_disk) + (u_sun_color * sun_glow);
    }

    if (u_fog_enabled != 0) {
        float fog_amount = SKYBOX_FOG_AMOUNT * clamp(u_fog_color.a, 0.0, 1.0);
        final_color = mix(final_color, u_fog_color.rgb, fog_amount);
    }
    
    color = vec4(final_color, 1.0);
}
