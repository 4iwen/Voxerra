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
    int transparency;
};

struct DirectionalLight {
    vec3 direction;
    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
};

struct PointLight {
    vec3 position;
    float constant;
    float linear;
    float quadratic;
    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
};

struct SpotLight {
    vec3 position;
    vec3 direction;
    float cutoff;
    float outer_cutoff;
    float constant;
    float linear;
    float quadratic;
    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
};

in vec3 v_position;
in vec3 v_normal;
in vec2 v_uv;
in float v_view_depth;

uniform vec3 u_view_position;
uniform int u_fog_enabled;
uniform vec4 u_fog_color;
uniform float u_fog_near;
uniform float u_fog_far;

uniform vec3 u_global_ambient;
uniform int u_has_directional_light;
uniform int u_point_light_count;
uniform int u_spot_light_count;
uniform int u_render_mode;

#define MAX_POINT_LIGHTS 32
#define MAX_SPOT_LIGHTS 16

#define RENDER_MODE_LIT 0
#define RENDER_MODE_UNLIT 1
#define RENDER_MODE_LIGHTING_ONLY 2
#define RENDER_MODE_ALBEDO 3

#define TRANSPARENCY_ALPHA_SCISSOR 1

uniform DirectionalLight u_directional_light;
uniform PointLight u_point_lights[MAX_POINT_LIGHTS];
uniform SpotLight u_spot_lights[MAX_SPOT_LIGHTS];
uniform Material u_material;

out vec4 color;

vec3 directional_light(
    DirectionalLight light,
    vec3 normal,
    vec3 view_direction,
    vec3 albedo_map,
    vec3 specular_map
) {
    vec3 light_direction = normalize(-light.direction);
    
    // diffuse shading
    float diffuse = max(dot(normal, light_direction), 0.0);
    vec3 reflect_direction = reflect(-light_direction, normal);
    
    // specular shading
    float specular = pow(max(dot(view_direction, reflect_direction), 0.0), u_material.shininess);
    
    // combine results
    vec3 ambient_final = light.ambient * albedo_map;
    vec3 diffuse_final = light.diffuse * diffuse * albedo_map;
    vec3 specular_final = light.specular * specular * specular_map;
    
    return (ambient_final + diffuse_final + specular_final);
}

vec3 point_light(
    PointLight light,
    vec3 normal,
    vec3 position,
    vec3 view_direction,
    vec3 albedo_map,
    vec3 specular_map
) {
    vec3 light_direction = normalize(light.position - position);

    // diffuse shading
    float diffuse = max(dot(normal, light_direction), 0.0);

    // specular shading
    vec3 reflect_direction = reflect(-light_direction, normal);
    float specular = pow(max(dot(view_direction, reflect_direction), 0.0), u_material.shininess);
    
    // attenuation
    float distance = length(light.position - position);
    float attenuation = 1.0 / (light.constant + light.linear * distance + light.quadratic * (distance * distance));    
    
    // combine results
    vec3 ambient_final = light.ambient * albedo_map;
    vec3 diffuse_final = light.diffuse * diffuse * albedo_map;
    vec3 specular_final = light.specular * specular * specular_map;
    ambient_final *= attenuation;
    diffuse_final *= attenuation;
    specular_final *= attenuation;
    
    return (ambient_final + diffuse_final + specular_final);
}

vec3 spot_light(
    SpotLight light,
    vec3 normal,
    vec3 position,
    vec3 view_direction,
    vec3 albedo_map,
    vec3 specular_map
) {
    vec3 light_direction = normalize(light.position - position);
    
    // diffuse shading
    float diffuse = max(dot(normal, light_direction), 0.0);
    
    // specular shading
    vec3 reflect_direction = reflect(-light_direction, normal);
    float specular = pow(max(dot(view_direction, reflect_direction), 0.0), u_material.shininess);
    
    // attenuation
    float distance = length(light.position - position);
    float attenuation = 1.0 / (light.constant + light.linear * distance + light.quadratic * (distance * distance));    
    
    // spotlight intensity
    float theta = dot(light_direction, normalize(-light.direction)); 
    float epsilon = light.cutoff - light.outer_cutoff;
    float intensity = clamp((theta - light.outer_cutoff) / epsilon, 0.0, 1.0);
    
    // combine results
    vec3 ambient_final = light.ambient * albedo_map;
    vec3 diffuse_final = light.diffuse * diffuse * albedo_map;
    vec3 specular_final = light.specular * specular * specular_map;
    ambient_final *= attenuation;
    diffuse_final *= attenuation * intensity;
    specular_final *= attenuation * intensity;
    
    return (ambient_final + diffuse_final + specular_final);
}

void main() {
    // properties
    vec3 normal = normalize(v_normal);
    vec3 view_direction = normalize(u_view_position - v_position);
    
    // sample textures
    vec2 uv = (u_material.uv_transform * vec3(v_uv, 1.0)).xy;
    vec4 diffuse_sample = texture(u_material.diffuse, uv);
    vec3 albedo_map = diffuse_sample.rgb * u_material.diffuse_color * u_material.tint;
    vec3 specular_map = vec3(texture(u_material.specular, uv)) * u_material.specular_color;
    float alpha = diffuse_sample.a * u_material.alpha;

    if (u_material.transparency == TRANSPARENCY_ALPHA_SCISSOR &&
        alpha < u_material.alpha_cutoff) {
        discard;
    }

    if (u_render_mode == RENDER_MODE_ALBEDO) {
        color = vec4(diffuse_sample.rgb, alpha);
        return;
    }

    if (u_render_mode == RENDER_MODE_UNLIT) {
        color = vec4(albedo_map, alpha);
        return;
    }

    // global ambient
    vec3 result = u_global_ambient * albedo_map;
    vec3 lighting_only = u_global_ambient;
    
    // directional lighting
    if (u_has_directional_light != 0) {
        result += directional_light(u_directional_light, normal, view_direction, albedo_map, specular_map);
        lighting_only += directional_light(
            u_directional_light,
            normal,
            view_direction,
            vec3(1.0),
            vec3(1.0)
        );
    }
    
    // point lights
    for (int i = 0; i < u_point_light_count; i++) {
        result += point_light(u_point_lights[i], normal, v_position, view_direction, albedo_map, specular_map);    
        lighting_only += point_light(
            u_point_lights[i],
            normal,
            v_position,
            view_direction,
            vec3(1.0),
            vec3(1.0)
        );
    }

    // spot light
    for (int i = 0; i < u_spot_light_count; i++) {
        result += spot_light(u_spot_lights[i], normal, v_position, view_direction, albedo_map, specular_map);    
        lighting_only += spot_light(
            u_spot_lights[i],
            normal,
            v_position,
            view_direction,
            vec3(1.0),
            vec3(1.0)
        );
    }

    if (u_render_mode == RENDER_MODE_LIGHTING_ONLY) {
        color = vec4(lighting_only, alpha);
        return;
    }

    if (u_fog_enabled != 0) {
        float fog_factor = clamp(
            (u_fog_far - v_view_depth) / max(u_fog_far - u_fog_near, 0.0001),
            0.0,
            1.0
        );
        result = mix(u_fog_color.rgb, result, fog_factor);
    }

    // final
    color = vec4(result, alpha);
}
