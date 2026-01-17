#version 330 core

in vec2 v_uv;
in vec3 v_world_position;
in vec3 v_normal;
in mat3 v_tbn;

// material parameters
uniform vec3 u_albedo;
uniform float u_metallic;
uniform float u_roughness;
uniform float u_ambient_occlusion;

// textures
uniform sampler2D u_albedo_map;
uniform sampler2D u_normal_map;
uniform sampler2D u_metallic_roughness_map;
uniform sampler2D u_occlusion_map;
uniform sampler2D u_emissive_map;

// flags
uniform bool u_has_albedo_map;
uniform bool u_has_normal_map;
uniform bool u_has_metallic_roughness_map;
uniform bool u_has_occlusion_map;
uniform bool u_has_emissive_map;

uniform vec3 u_camera_position;
uniform vec4 u_mat_color;
uniform float u_mat_metallic;
uniform float u_mat_roughness;
uniform float u_alpha_cutoff;
uniform vec3 u_emissive_factor;
uniform float u_emissive_strength;

// lighting
uniform vec3 u_ambient_color;
uniform int  u_light_count;

struct Light {
    int type; // 0 = directional, 1 = point, 2 = spot
    vec3 position;
    vec3 direction;
    vec3 color;
    float intensity;
    float range;
    float inner_cos;
    float outer_cos;
};

// max number of lights supported
const int MAX_LIGHTS = 32;
uniform Light u_lights[MAX_LIGHTS];

out vec4 color;

const float PI = 3.14159265359;

float distribution_ggx(vec3 n, vec3 h, float roughness) {
    float r2 = roughness * roughness;
    float r4 = r2 * r2;
    float n_dot_h = max(dot(n, h), 0.0);
    float n_dot_h2 = n_dot_h * n_dot_h;

    float numerator = r4;
    float denominator = (n_dot_h2 * (r4 - 1.0) + 1.0);
    denominator = PI * denominator * denominator;

    return numerator / denominator;
}

float geometry_schlick_ggx(float n_dot_v, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;

    float numerator = n_dot_v;
    float denominator = n_dot_v * (1.0 - k) + k;

    return numerator / denominator;
}

float geometry_schlick(vec3 n, vec3 v, vec3 l, float roughness) {
    float n_dot_l = max(dot(n, l), 0.0);
    float n_dot_v = max(dot(n, v), 0.0);
    float ggx1 = geometry_schlick_ggx(n_dot_l, roughness);
    float ggx2 = geometry_schlick_ggx(n_dot_v, roughness);

    return ggx1 * ggx2;
}

vec3 fresnel_schlick(float cos_theta, vec3 f0) {
    return f0 + (1.0 - f0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

void main() {
    // albedo
    vec3 albedo = u_albedo;
    if (u_has_albedo_map) {
        vec4 tex_albedo = texture(u_albedo_map, v_uv);
        albedo *= pow(tex_albedo.rgb, vec3(2.2));
    }

    // metallic, roughness
    float metallic = u_metallic;
    float roughness = u_roughness;
    if (u_has_metallic_roughness_map) {
        vec4 mr = texture(u_metallic_roughness_map, v_uv);
        roughness *= mr.g; 
        metallic *= mr.b;
    }

    // normal
    vec3 n = normalize(v_normal);
    if (u_has_normal_map) {
        vec3 tangent_normal = texture(u_normal_map, v_uv).xyz * 2.0 - 1.0;
        n = normalize(v_tbn * tangent_normal);
    }
    
    // occlusion
    float ao = u_ambient_occlusion;
    if (u_has_occlusion_map) {
        ao *= texture(u_occlusion_map, v_uv).r;
    }
    
    // emissive
    vec3 emissive = u_emissive_factor;
    if (u_has_emissive_map) {
        vec3 tex_emissive = texture(u_emissive_map, v_uv).rgb;
        emissive *= pow(tex_emissive, vec3(2.2));
    }
    emissive *= u_emissive_strength;

    vec3 v = normalize(u_camera_position - v_world_position);

    // calculate reflectance at normal incidence:
    // if dia-electric (like plastic) use f0 of 0.04
    // if its a metal, use the albedo color as f0 (metallic workflow)
    vec3 f0 = vec3(0.04);
    f0 = mix(f0, albedo, metallic);

    // reflectance equation
    vec3 lo = vec3(0.0);
    for(int i = 0; i < min(u_light_count, MAX_LIGHTS); i++)
    {
        Light light = u_lights[i];

        float diff = 0.0;
        vec3 l = vec3(0.0);
        float attenuation = 1.0;

        if (light.type == 0) { // directional
            l = normalize(-light.direction);
            diff = max(dot(n, l), 0.0);
        } else if (light.type == 1) { // point
            vec3 light_vec = light.position - v_world_position;
            float dist = length(light_vec);
            l = light_vec / max(dist, 1e-4);
            diff = max(dot(n, l), 0.0);
            float range = max(light.range, 1e-4);
            float x = clamp(1.0 - dist / range, 0.0, 1.0);
            attenuation = x * x;
        } else if (light.type == 2) { // spot
            vec3 light_vec = light.position - v_world_position;
            float dist = length(light_vec);
            l = light_vec / max(dist, 1e-4);
            diff = max(dot(n, l), 0.0);
            float range = max(light.range, 1e-4);
            float x = clamp(1.0 - dist / range, 0.0, 1.0);
            attenuation = x * x;
            float cos_theta = dot(normalize(-light.direction), l);
            float spot = smoothstep(light.outer_cos, light.inner_cos, cos_theta);
            attenuation *= spot;
        }

        vec3 h = normalize(v + l);

        vec3 radiance = light.color * light.intensity * attenuation;

        // cook-torrance brdf
        float ndf = distribution_ggx(n, h, roughness);   
        float g = geometry_schlick(n, v, l, roughness);      
        vec3 f = fresnel_schlick(clamp(dot(h, v), 0.0, 1.0), f0);
           
        vec3 numerator = ndf * g * f; 
        // + 0.0001 to prevent divide by zero
        float denominator = 
            4.0 * max(dot(n, v), 0.0) * max(dot(n, l), 0.0) + 0.0001;
        vec3 specular = numerator / denominator;
        
        // ks is equal to fresnel
        vec3 ks = f;
        // for energy conservation, the diffuse and specular light cant
        // be above 1.0 (unless the surface emits light), to preserve this
        // relationship the diffuse component (kd) should equal 1.0 - ks
        vec3 kd = vec3(1.0) - ks;
        // multiply kd by the inverse metalness such that only non-metals 
        // have diffuse lighting, or a linear blend if partly metal (pure metals
        // have no diffuse light)
        kd *= 1.0 - metallic;	  

        // scale light by n_dot_l
        float n_dot_l = max(dot(n, l), 0.0);        

        // add to outgoing radiance lo
        // we already multiplied the brdf by the fresnel (ks)
        // so we wont multiply by ks again
        lo += (kd * albedo / PI + specular) * radiance * n_dot_l;
    }   

    // ambient lighting
    vec3 ambient = vec3(0.03) * albedo * ao;
    vec3 final_color = ambient + lo + emissive;

    // hdr tonemapping
    final_color = final_color / (final_color + vec3(1.0));
    // gamma correct
    final_color = pow(final_color, vec3(1.0 / 2.2)); 

    color = vec4(final_color, 1.0);
}
