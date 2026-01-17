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
    type: Light_Type;
    position: Vector3;
    direction: Vector3;
    color: Vector3;
    intensity: float;
    range: float; // for point, spot
    inner_cos: float; // for spot
    outer_cos: float; // for spot
}

MAX_SHADER_LIGHTS :: 32;

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
    array_reset(*system.lights);
}

light_add_directional :: (
    system: *Light_System,
    direction: Vector3,
    color: Vector3 = .{1, 1, 1},
    intensity: float = 1.0
) {
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
    shader_set_vec3(shader, "u_ambient_color", system.ambient_color);

    count := system.lights.count;
    if count > MAX_SHADER_LIGHTS {
        log_warning("Capping lights to % (got %)", MAX_SHADER_LIGHTS, count);
        count = MAX_SHADER_LIGHTS;
    }
    shader_set_int(shader, "u_light_count", cast(s32) count);

    for i: 0..count - 1 {
        l := system.lights[i];
        shader_set_int(shader, tprint("u_lights[%].type", i), cast(s32) l.type);
        shader_set_vec3(shader, tprint("u_lights[%].position", i), l.position);
        shader_set_vec3(shader, tprint("u_lights[%].direction", i), l.direction);
        shader_set_vec3(shader, tprint("u_lights[%].color", i), l.color);
        shader_set_float(shader, tprint("u_lights[%].intensity", i), l.intensity);
        shader_set_float(shader, tprint("u_lights[%].range", i), l.range);
        shader_set_float(shader, tprint("u_lights[%].inner_cos", i), l.inner_cos);
        shader_set_float(shader, tprint("u_lights[%].outer_cos", i), l.outer_cos);
    }
}
