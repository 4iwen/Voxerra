#version 330 core

in vec3 v_tex_coords;

out vec4 color;

uniform vec3 u_top_color = vec3(0.1, 0.35, 0.8);
uniform vec3 u_bottom_color = vec3(0.6, 0.7, 0.9);
uniform vec3 u_sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 u_sun_color = vec3(1.0, 0.95, 0.9);

void main() {
    vec3 dir = normalize(v_tex_coords);
    
    // gradient
    float t = 0.5 * (dir.y + 1.0);
    
    vec3 sky_base = mix(u_bottom_color, u_top_color, max(dir.y, 0.0));
    float sun_dot = dot(dir, normalize(u_sun_direction));
    float sun_disk = smoothstep(0.997, 0.999, sun_dot);
    float sun_glow = pow(max(sun_dot, 0.0), 300.0) * 0.5;
    
    vec3 final_color = sky_base + (u_sun_color * sun_disk) + (u_sun_color * sun_glow);
    
    color = vec4(final_color, 1.0);
}
