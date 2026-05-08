// File:        fog_resolve.frag
// Author:      Lukáš Bien
// Description: Applies fullscreen distance fog to the rendered scene color.

#version 330 core

in vec2 v_uv;

uniform sampler2D u_scene_color;
uniform sampler2D u_scene_depth;

uniform int u_fog_enabled;

uniform vec4 u_fog_color;
uniform float u_fog_near;
uniform float u_fog_far;
uniform float u_camera_near;
uniform float u_camera_far;

out vec4 color;

const float SKYBOX_FOG_AMOUNT = 0.35;

// reconstruct linear view distance from the default depth buffer so fog can
// be evaluated in world-consistent distance units.
float linearize_depth(float depth_sample) {
    float z = depth_sample * 2.0 - 1.0;
    return (2.0 * u_camera_near * u_camera_far) /
           (u_camera_far + u_camera_near - z * (u_camera_far - u_camera_near));
}

// treat far-depth pixels as skybox/background and clamp them to a limited fog
// mix so bright sky details are still visible through haze.
void main() {
    vec4 scene_color = texture(u_scene_color, v_uv);
    if (u_fog_enabled == 0) {
        color = vec4(scene_color.rgb, 1.0);
        return;
    }

    float depth_sample = texture(u_scene_depth, v_uv).r;
    if (depth_sample >= 0.999999) {
        float fog_amount = SKYBOX_FOG_AMOUNT * clamp(u_fog_color.a, 0.0, 1.0);
        color = vec4(mix(scene_color.rgb, u_fog_color.rgb, fog_amount), 1.0);
        return;
    }

    float view_distance = linearize_depth(depth_sample);
    float fog_factor = clamp(
        (u_fog_far - view_distance) / max(u_fog_far - u_fog_near, 0.0001),
        0.0,
        1.0
    );

    vec3 fogged = mix(u_fog_color.rgb, scene_color.rgb, fog_factor);
    color = vec4(fogged, 1.0);
}
