#scope_file

#import "Basic";
#import "Math";

#scope_export

Material :: struct {
    color: Vector4 = .{1.0, 1.0, 1.0, 1.0};
    metallic: float = 0.0;
    roughness: float = 0.5;
    diffuse_texture: *Texture;
}

material_create :: () -> *Material {
    material := New(Material);
    return material;
}

material_destroy :: (material: *Material) {
    free(material);
}
