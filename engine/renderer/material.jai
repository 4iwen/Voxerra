// File:        material.jai
// Author:      Lukáš Bien
// Description: Defines material data and material override state used during rendering.

#scope_file

#import "Basic";
#import "Math";

#scope_export

Transparency_Mode :: enum {
    DISABLED;
    ALPHA_SCISSOR;
    ALPHA_BLEND;
}

Material :: struct {
    name: string;

    // properties
    diffuse_color: Vector3 = .{1, 1, 1}; @Color
    specular_color: Vector3 = .{1, 1, 1}; @Color
    tint_color: Vector3 = .{1, 1, 1}; @Color
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
    transparency: Transparency_Mode = .DISABLED;
    double_sided: bool; @"Tooltip(\"Render both sides by disabling back-face culling for this material\")"
}

Resolved_Material :: struct {
    source: *Material;

    diffuse_color: Vector3 = .{1, 1, 1}; @Color
    specular_color: Vector3 = .{1, 1, 1}; @Color
    tint_color: Vector3 = .{1, 1, 1}; @Color
    shininess: float = 32.0;

    diffuse_map: *Texture;
    specular_map: *Texture;

    alpha: float = 1.0;
    alpha_cutoff: float = 0.5;
    uv_transform: Matrix3;

    shader: *Shader;
    transparency: Transparency_Mode = .DISABLED;
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
        resolved.transparency = material.transparency;
        resolved.double_sided = material.double_sided;
    }

    if override && override.enabled {
        resolved.diffuse_color = override.diffuse_color;
        resolved.specular_color = override.specular_color;
        resolved.tint_color = override.tint_color;
        if override.diffuse_map {
            resolved.diffuse_map = override.diffuse_map;
        }
        if override.specular_map {
            resolved.specular_map = override.specular_map;
        }
        resolved.shininess = override.shininess;
        resolved.alpha = override.alpha;
        resolved.alpha_cutoff = override.alpha_cutoff;
        resolved.uv_transform = override.uv_transform;
        resolved.transparency = override.transparency;
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
    shader_set_int(material.shader, "u_material.transparency", cast(s32) material.transparency);
}

material_is_alpha_blend :: (material: Resolved_Material) -> bool {
    if material.transparency != .ALPHA_BLEND then return false;
    if material.alpha < 0.999 then return true;
    return material.diffuse_map && material.diffuse_map.has_transparency;
}

material_uses_alpha_test :: (material: Resolved_Material) -> bool {
    return material.transparency == .ALPHA_SCISSOR ||
        material.transparency == .ALPHA_BLEND;
}

material_pick_alpha_cutoff :: (material: Resolved_Material) -> float {
    if material.transparency == .ALPHA_BLEND then return 0.01;
    return material.alpha_cutoff;
}

material_pick_alpha :: (material: Resolved_Material) -> float {
    if material.transparency == .ALPHA_BLEND then return 1.0;
    return material.alpha;
}

sprite_is_alpha_blend :: (sprite: *Sprite_Component) -> bool {
    if !sprite || sprite.transparency != .ALPHA_BLEND then return false;
    if sprite.alpha < 0.999 then return true;
    if sprite.texture && sprite.texture.has_transparency then return true;
    return false;
}

sprite_uses_alpha_test :: (sprite: *Sprite_Component) -> bool {
    return sprite && sprite.transparency != .DISABLED;
}

sprite_pick_alpha_cutoff :: (sprite: *Sprite_Component) -> float {
    if sprite && sprite.transparency == .ALPHA_BLEND then return 0.01;
    if sprite then return sprite.alpha_cutoff;
    return 1.0;
}

sprite_pick_alpha :: (sprite: *Sprite_Component) -> float {
    if sprite && sprite.transparency == .ALPHA_BLEND then return 1.0;
    if sprite then return sprite.alpha;
    return 1.0;
}
