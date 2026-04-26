#version 330 core

struct Material {
    sampler2D diffuse;
    sampler2D specular;
    float shininess;
    float alpha;
    float alpha_cutoff;
    int blend_mode;
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

uniform vec3 u_view_position;

uniform vec3 u_global_ambient;
uniform int u_has_directional_light;
uniform int u_point_light_count;
uniform int u_spot_light_count;

#define MAX_POINT_LIGHTS 32
#define MAX_SPOT_LIGHTS 16

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
    vec4 diffuse_sample = texture(u_material.diffuse, v_uv);
    vec3 albedo_map = diffuse_sample.rgb;
    vec3 specular_map = vec3(texture(u_material.specular, v_uv));
    float alpha = diffuse_sample.a * u_material.alpha;

    if (u_material.blend_mode == 1 && alpha < u_material.alpha_cutoff) {
        discard;
    }

    // global ambient
    vec3 result = u_global_ambient * albedo_map;
    
    // directional lighting
    if (u_has_directional_light != 0) {
        result += directional_light(u_directional_light, normal, view_direction, albedo_map, specular_map);
    }
    
    // point lights
    for (int i = 0; i < u_point_light_count; i++) {
        result += point_light(u_point_lights[i], normal, v_position, view_direction, albedo_map, specular_map);    
    }

    // spot light
    for (int i = 0; i < u_spot_light_count; i++) {
        result += spot_light(u_spot_lights[i], normal, v_position, view_direction, albedo_map, specular_map);    
    }
    
    // final
    color = vec4(result, alpha);
}
