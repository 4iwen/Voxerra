// File:        light.jai
// Author:      Lukáš Bien
// Description: Defines light data structures shared by scenes and shaders.

#scope_file

#import "Basic";
#import "Math";
#import "GL";

#scope_export

Light_Type :: enum u32 {
    Directional;
    Point;
    Spot;
}

Light :: struct {
    type: Light_Type; @"Tooltip(\"The type of light, it defines how the light is projected\")"
    position: Vector3; @Hidden
    direction: Vector3; @Hidden
    color: Vector3 = .{1, 1, 1}; @Color @"Tooltip(\"The color of the light\")"
    intensity: float; @"Speed(0.1)" @"Range(0.0, 100.0)" @"Tooltip(\"The brightness of the light\")"
    range: float; @"Speed(0.5)" @"Range(0.0, 1000.0)" @"Tooltip(\"The maximum distance the light reaches\")"
    inner_cos: float; @"Speed(0.01)" @"Range(0.0, 1.0)" @"Tooltip(\"The cosine of the inner cone angle, light is at full intensity inside this region\")"
    outer_cos: float; @"Speed(0.01)" @"Range(0.0, 1.0)" @"Tooltip(\"The cosine of the outer cone angle, light fades smoothly to zero between the inner and outer cones\")"
}

MAX_POINT_LIGHTS :: 32;
MAX_SPOT_LIGHTS :: 16;
MAX_DIRECTIONAL_LIGHTS :: 1;

Light_System :: struct {
    ambient_color: Vector3;
    lights: [..] Light;
}

light_system_create :: (ambient: Vector3 = .{0, 0, 0}) -> Light_System {
    system: Light_System;
    system.ambient_color = ambient;
    return system;
}

light_system_destroy :: (system: *Light_System) {
    assert(system != null, "light_system_destroy: system is null");

    array_free(system.lights);
}

light_add_directional :: (
    system: *Light_System,
    direction: Vector3,
    color: Vector3 = .{1, 1, 1},
    intensity: float = 1.0
) {
    assert(system != null, "light_add_directional: system is null");

    l: Light;
    l.type = .Directional;
    l.direction = normalize(direction);
    l.color = color;
    l.intensity = intensity;
    array_add(*system.lights, l);
}

light_add_point :: (
    system: *Light_System,
    position: Vector3,
    color: Vector3 = .{1, 1, 1},
    intensity: float = 1.0,
    range: float = 10.0
) {
    assert(system != null, "light_add_point: system is null");

    l: Light;
    l.type = .Point;
    l.position = position;
    l.color = color;
    l.intensity = intensity;
    l.range = range;
    array_add(*system.lights, l);
}

light_add_spot :: (
    system: *Light_System,
    position: Vector3,
    direction: Vector3,
    color: Vector3 = .{1,1,1},
    intensity: float = 1.0,
    range: float = 20.0,
    inner_deg: float = 20.0,
    outer_deg: float = 30.0
) {
    assert(system != null, "light_add_spot: system is null");

    l: Light;
    l.type = .Spot;
    l.position = position;
    l.direction = normalize(direction);
    l.color = color;
    l.intensity = intensity;
    l.range = range;
    l.inner_cos = cast(float) cos(degrees_to_radians(inner_deg));
    l.outer_cos = cast(float) cos(degrees_to_radians(outer_deg));
    array_add(*system.lights, l);
}

// upload lights to shader
light_upload_to_shader :: (shader: *Shader, system: *Light_System) {
    assert(shader != null, "light_upload_to_shader: shader is null");
    assert(system != null, "light_upload_to_shader: system is null");
    
    // set global ambient
    shader_set_vec3(shader, "u_global_ambient", system.ambient_color);

    directional_set := false;
    point_count := 0;
    spot_count := 0;

    for l: system.lights {
        light_intensity := max(l.intensity, 0.0);
        diffuse_color := l.color * light_intensity;
        specular_color := l.color * (light_intensity * 0.5);

        if l.type == .Directional && !directional_set {
            shader_set_vec3(shader, "u_directional_light.direction", l.direction);
            shader_set_vec3(shader, "u_directional_light.diffuse", diffuse_color);
            shader_set_vec3(shader, "u_directional_light.specular", specular_color);
            directional_set = true;
        } else if l.type == .Point && point_count < MAX_POINT_LIGHTS {
            prefix := tprint("u_point_lights[%]", point_count);
            shader_set_vec3(shader, tprint("%.position", prefix), l.position);
            shader_set_float(shader, tprint("%.constant", prefix), 1.0);
            shader_set_float(shader, tprint("%.linear", prefix), 4.5 / max(l.range, 0.01));
            shader_set_float(shader, tprint("%.quadratic", prefix), 75.0 / max(l.range * l.range, 0.01));
            shader_set_vec3(shader, tprint("%.diffuse", prefix), diffuse_color);
            shader_set_vec3(shader, tprint("%.specular", prefix), specular_color);
            point_count += 1;
        } else if l.type == .Spot && spot_count < MAX_SPOT_LIGHTS {
            prefix := tprint("u_spot_lights[%]", spot_count);
            shader_set_vec3(shader, tprint("%.position", prefix), l.position);
            shader_set_vec3(shader, tprint("%.direction", prefix), l.direction);
            shader_set_float(shader, tprint("%.cutoff", prefix), l.inner_cos);
            shader_set_float(shader, tprint("%.outer_cutoff", prefix), l.outer_cos);
            shader_set_float(shader, tprint("%.constant", prefix), 1.0);
            shader_set_float(shader, tprint("%.linear", prefix), 4.5 / max(l.range, 0.01));
            shader_set_float(shader, tprint("%.quadratic", prefix), 75.0 / max(l.range * l.range, 0.01));
            shader_set_vec3(shader, tprint("%.diffuse", prefix), diffuse_color);
            shader_set_vec3(shader, tprint("%.specular", prefix), specular_color);
            spot_count += 1;
        }
    }
    
    shader_set_int(shader, "u_point_light_count", cast(s32) point_count);
    shader_set_int(shader, "u_spot_light_count", cast(s32) spot_count);
    shader_set_int(shader, "u_has_directional_light", cast(s32) directional_set);
}
