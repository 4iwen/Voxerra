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
    shininess: float = 32.0;

    // texture maps
    diffuse_map: *Texture; // if null, uses diffuse color
    specular_map: *Texture; // if null, uses specular color

    // alpha
    alpha: float = 1.0;
    alpha_cutoff: float = 0.5;

    // rendering
    shader: *Shader;
    blend_mode: Blend_Mode = .OPAQUE;
}

material_create :: (name: string = "") -> *Material {
    material := New(Material);
    material.name = copy_string(name);

    return material;
}

material_destroy :: (material: *Material) {
    assert(material != null, "material_destroy: material is null");

    free(material.name);
    free(material);
}

material_use :: (material: *Material) {
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
    shader_set_float(material.shader, "u_material.shininess", material.shininess);
}
