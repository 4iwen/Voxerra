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

material_create :: (name: string = "") -> *Material {
    material := New(Material);
    material.name = copy_string(name);
    material.uv_transform = material_uv_identity();

    return material;
}

material_destroy :: (material: *Material) {
    assert(material != null, "material_destroy: material is null");

    free(material.name);
    free(material);
}

material_use :: (material: *Material) {
    assert(material != null, "material_use: material is null");
    assert(material.shader != null, "material_use: material.shader is null");

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

    // shininess
    shader_set_vec3(material.shader, "u_material.tint", material.tint_color);
    shader_set_float(material.shader, "u_material.shininess", material.shininess);
    shader_set_float(material.shader, "u_material.alpha", material.alpha);
    shader_set_float(material.shader, "u_material.alpha_cutoff", material.alpha_cutoff);
    shader_set_mat3(material.shader, "u_material.uv_transform", material.uv_transform);
    shader_set_mat3(material.shader, "u_uv_transform", material.uv_transform);
    shader_set_int(material.shader, "u_material.blend_mode", cast(s32) material.blend_mode);
}

#scope_file

material_uv_identity :: () -> Matrix3 {
    matrix: Matrix3 = .{};
    matrix.coef[0][0] = 1.0;
    matrix.coef[1][1] = 1.0;
    matrix.coef[2][2] = 1.0;
    return matrix;
}
