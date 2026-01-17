#scope_file

#import "Basic";
#import "Math";

#scope_export

Material :: struct {
    name: string;
    color: Vector4 = .{1.0, 1.0, 1.0, 1.0};
    metallic: float = 0.0;
    roughness: float = 0.5;
    alpha_cutoff: float = 0.01;
    is_transparent: bool = false;

    albedo_texture: *Texture = null;
    normal_texture: *Texture = null;
    metallic_roughness_texture: *Texture = null;
    occlusion_texture: *Texture = null;
    emissive_texture: *Texture = null;

    emissive_color: Vector3 = .{0, 0, 0};
    emissive_strength: float = 1.0;
}

material_create :: () -> *Material {
    material := New(Material);
    return material;
}

material_destroy :: (material: *Material) {
    free(material);
}
