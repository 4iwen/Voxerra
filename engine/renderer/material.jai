#scope_file

#import "Basic";
#import "Math";

#scope_export

Blend_Mode :: enum {
    OPAQUE;
    ALPHA_CLIP;
    ALPHA_BLEND;
}

Material :: struct {
    name: string;

    // properties
    diffuse_color: Vector3 = .{1, 1, 1};
    specular_color: Vector3 = .{1, 1, 1};
    tint_color: Vector3 = .{1, 1, 1};
    shininess: float = 32.0;

    // texture maps
    diffuse_map: *Texture; // if null, uses diffuse color
    specular_map: *Texture; // if null, uses specular color

    // alpha
    alpha: float = 1.0;
    alpha_cutoff: float = 0.5;
    uv_transform: Matrix3;

    // rendering
    shader: *Shader;
    blend_mode: Blend_Mode = .OPAQUE;
    double_sided: bool; @"Tooltip(\"Render both sides by disabling back-face culling for this material\")"
}

Resolved_Material :: struct {
    source: *Material;

    diffuse_color: Vector3 = .{1, 1, 1};
    specular_color: Vector3 = .{1, 1, 1};
    tint_color: Vector3 = .{1, 1, 1};
    shininess: float = 32.0;

    diffuse_map: *Texture;
    specular_map: *Texture;

    alpha: float = 1.0;
    alpha_cutoff: float = 0.5;
    uv_transform: Matrix3;

    shader: *Shader;
    blend_mode: Blend_Mode = .OPAQUE;
    double_sided: bool;
}

material_create :: (name: string = "") -> *Material {
    material := New(Material);
    material.name = copy_string(name);
    material.uv_transform = Matrix3_Identity;

    return material;
}

material_destroy :: (material: *Material) {
    assert(material != null, "material_destroy: material is null");

    free(material.name);
    free(material);
}

material_resolve :: (
    material: *Material,
    override: *Model_Material_Override = null
) -> Resolved_Material {
    resolved: Resolved_Material;
    resolved.uv_transform = Matrix3_Identity;

    if material {
        resolved.source = material;
        resolved.diffuse_color = material.diffuse_color;
        resolved.specular_color = material.specular_color;
        resolved.tint_color = material.tint_color;
        resolved.shininess = material.shininess;
        resolved.diffuse_map = material.diffuse_map;
        resolved.specular_map = material.specular_map;
        resolved.alpha = material.alpha;
        resolved.alpha_cutoff = material.alpha_cutoff;
        resolved.uv_transform = material.uv_transform;
        resolved.shader = material.shader;
        resolved.blend_mode = material.blend_mode;
        resolved.double_sided = material.double_sided;
    }

    if override && override.enabled {
        resolved.diffuse_color = override.diffuse_color;
        resolved.specular_color = override.specular_color;
        resolved.tint_color = override.tint_color;
        resolved.shininess = override.shininess;
        resolved.alpha = override.alpha;
        resolved.alpha_cutoff = override.alpha_cutoff;
        resolved.uv_transform = override.uv_transform;
        resolved.blend_mode = override.blend_mode;
        resolved.double_sided = override.double_sided;
    }

    return resolved;
}

material_use :: (material: *Material) {
    assert(material != null, "material_use: material is null");
    assert(material.shader != null, "material_use: material.shader is null");

    resolved := material_resolve(material);
    material_use_resolved(resolved);
}

material_use_resolved :: (material: Resolved_Material) {
    assert(material.shader != null, "material_use_resolved: material.shader is null");

    // diffuse
    if material.diffuse_map {
        texture_bind(material.diffuse_map, 0);
    } else {
        texture_bind(asset_manager_get_default_texture(), 0);
    }
    shader_set_int(material.shader, "u_material.diffuse", 0);

    // specular
    if material.specular_map {
        texture_bind(material.specular_map, 1);
    } else {
        texture_bind(asset_manager_get_default_texture(), 1);
    }
    shader_set_int(material.shader, "u_material.specular", 1);

    shader_set_vec3(material.shader, "u_material.diffuse_color", material.diffuse_color);
    shader_set_vec3(material.shader, "u_material.specular_color", material.specular_color);
    shader_set_vec3(material.shader, "u_material.tint", material.tint_color);
    shader_set_float(material.shader, "u_material.shininess", material.shininess);
    shader_set_float(material.shader, "u_material.alpha", material.alpha);
    shader_set_float(material.shader, "u_material.alpha_cutoff", material.alpha_cutoff);
    shader_set_mat3(material.shader, "u_material.uv_transform", material.uv_transform);
    shader_set_mat3(material.shader, "u_uv_transform", material.uv_transform);
    shader_set_int(material.shader, "u_material.blend_mode", cast(s32) material.blend_mode);
}

material_is_alpha_blend :: (material: Resolved_Material) -> bool {
    return material.blend_mode == .ALPHA_BLEND;
}
