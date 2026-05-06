// File:        model.jai
// Author:      Lukáš Bien
// Description: Imports models through Assimp and builds engine mesh and material resources.

#scope_file

#import "Basic";
#import "Math";
#import "jassimp";
#import "stb_image";

#scope_export

Model :: struct {
    name: string;
    submeshes: [..] *Sub_Mesh;
    materials: [..] *Material;
    owned_textures: [..] *Texture;
}

Sub_Mesh :: struct {
    mesh: *Mesh;
    material: *Material;
    material_index: s32 = -1;
}

Model_Load_Options :: struct {
    flip_uvs: bool;
    calculate_tangents: bool;
}

DEFAULT_MODEL_LOAD_OPTIONS :: Model_Load_Options.{
    flip_uvs = false,
    calculate_tangents = true
};

model_create_from_file :: (
    path: string,
    options: Model_Load_Options = DEFAULT_MODEL_LOAD_OPTIONS
) -> *Model {
    ok, meshes, materials, material_indices, owned_textures := assimp_load_meshes(path, options);
    if !ok {
        log_error("Failed to load mesh file: %", path);
        return null;
    }

    model := New(Model);
    model.name = copy_string(path);
    model.materials = materials;
    model.owned_textures = owned_textures;

    for mesh, index: meshes {
        submesh := New(Sub_Mesh);
        submesh.mesh = mesh;

        material_index := material_indices[index];
        submesh.material_index = cast(s32) material_index;
        if material_index < materials.count {
            submesh.material = materials[material_index];
        }

        array_add(*model.submeshes, submesh);
    }

    array_free(meshes);
    array_free(material_indices);

    return model;
}

model_destroy :: (model: *Model) {
    assert(model != null, "model_destroy: model is null");

    if model.name then free(model.name);

    for model.submeshes {
        mesh_destroy(it.mesh);
        free(it);
    }
    array_free(model.submeshes);

    for model.materials {
        material_destroy(it);
    }
    array_free(model.materials);

    for model.owned_textures {
        texture_destroy(it);
    }
    array_free(model.owned_textures);

    free(model);
}

model_reload_from_file :: (
    model: *Model,
    path: string,
    options: Model_Load_Options
) -> bool {
    ok, meshes, materials, material_indices, owned_textures := assimp_load_meshes(path, options);
    if !ok || meshes.count == 0 {
        for meshes {
            mesh_destroy(it);
        }
        for materials {
            material_destroy(it);
        }
        for owned_textures {
            texture_destroy(it);
        }
        return false;
    }

    // clear old submeshes
    for model.submeshes {
        mesh_destroy(it.mesh);
        free(it);
    }
    array_reset(*model.submeshes);

    // clear old materials
    for model.materials {
        material_destroy(it);
    }
    array_reset(*model.materials);

    for model.owned_textures {
        texture_destroy(it);
    }
    array_reset(*model.owned_textures);

    // rebuild submeshes
    model.materials = materials;
    model.owned_textures = owned_textures;
    for mesh, index: meshes {
        submesh := New(Sub_Mesh);
        submesh.mesh = mesh;
        material_index := material_indices[index];
        submesh.material_index = cast(s32) material_index;
        if material_index < materials.count {
            submesh.material = materials[material_index];
        }
        array_add(*model.submeshes, submesh);
    }

    array_free(meshes);
    array_free(material_indices);

    return true;
}

#scope_file

// assimp helpers
try_load_float :: (material: *aiMaterial, key: string) -> bool, float {
    value: float;
    value_count: u32 = 1;

    key_c_str := to_c_string(key);
    defer free(key_c_str);

    if aiGetMaterialFloatArray(material, key_c_str, 0, 0, *value, *value_count) == .SUCCESS {
        return true, value;
    }
    return false, 0.0;
}

try_load_int :: (material: *aiMaterial, key: string) -> bool, s32 {
    value: s32;
    value_count: u32 = 1;

    key_c_str := to_c_string(key);
    defer free(key_c_str);

    if aiGetMaterialIntegerArray(material, key_c_str, 0, 0, *value, *value_count) == .SUCCESS {
        return true, value;
    }
    return false, 0;
}

try_load_color :: (material: *aiMaterial, key: string) -> bool, Vector3 {
    color: aiColor4D;

    key_c_str := to_c_string(key);
    defer free(key_c_str);

    if aiGetMaterialColor(material, key_c_str, 0, 0, *color) == .SUCCESS {
        return true, .{color.r, color.g, color.b};
    }
    return false, .{0, 0, 0};
}

try_load_string :: (material: *aiMaterial, key: string) -> bool, string {
    ai_string: aiString;
    key_c_str := to_c_string(key);
    defer free(key_c_str);

    if aiGetMaterialString(material, key_c_str, 0, 0, *ai_string) == .SUCCESS {
        length := cast(s64) ai_string.length;
        if length > 0 {
            source: string;
            source.data  = ai_string.data.data;
            source.count = length;
            return true, copy_string(source);
        }
    }
    return false, "";
}

// load materials and meshes
assimp_load_meshes :: (
    path: string,
    options: Model_Load_Options
) -> bool, [..] *Mesh, [..] *Material, [..] u32, [..] *Texture {
    meshes: [..] *Mesh;
    materials: [..] *Material;
    material_indices: [..] u32;
    owned_textures: [..] *Texture;

    path_c_str := to_c_string(path);
    defer free(path_c_str);

    // import with assimp
    flags := aiPostProcessSteps.Triangulate |
             aiPostProcessSteps.JoinIdenticalVertices |
             aiPostProcessSteps.GenUVCoords;

    if options.calculate_tangents then flags |= aiPostProcessSteps.CalcTangentSpace;
    if options.flip_uvs           then flags |= aiPostProcessSteps.FlipUVs;

    scene := aiImportFile(path_c_str, cast(u32) flags);
    if !scene {
        error := aiGetErrorString();
        if error {
            log_error("Assimp failed to load file: %, Error: %", path, to_string(error));
        } else {
            log_error("Assimp failed to load file: %", path);
        }
        return false, meshes, materials, material_indices, owned_textures;
    }
    defer aiReleaseImport(scene);

    if scene.mFlags & AI_SCENE_FLAGS_INCOMPLETE {
        error := aiGetErrorString();
        if error {
            log_error("Assimp scene incomplete: %, Error: %", path, to_string(error));
        } else {
            log_error("Assimp scene incomplete: %", path);
        }
        return false, meshes, materials, material_indices, owned_textures;
    }

    if scene.mNumMeshes == 0 {
        log_error("No meshes found in file: %", path);
        return false, meshes, materials, material_indices, owned_textures;
    }

    // materials
    for material_index: 0..scene.mNumMaterials - 1 {
        ai_material := scene.mMaterials[material_index];
        material := material_create();

        // diffuse
        {
            ok, color := try_load_color(ai_material, "$clr.diffuse");
            if ok then material.diffuse_color = color;
        }

        // specular
        {
            ok, color := try_load_color(ai_material, "$clr.specular");
            if ok then material.specular_color = color;
        }

        // shininess
        {
            ok, value := try_load_float(ai_material, "$mat.shininess");
            if ok && value > 0 then material.shininess = value;
        }

        // two sided?
        {
            ok, value := try_load_int(ai_material, "$mat.twosided");
            if ok {
                material.double_sided = value != 0;
            }
        }

        // alpha
        {
            ok_mode, mode_str := try_load_string(ai_material, "$mat.gltf.alphaMode");
            if ok_mode {
                if mode_str == "BLEND" {
                    material.transparency = .ALPHA_BLEND;
                    material.alpha_cutoff = 0.0;
                } else if mode_str == "MASK" {
                    material.transparency = .ALPHA_SCISSOR;
                    ok_cutoff, cutoff := try_load_float(ai_material, "$mat.gltf.alphaCutoff");
                    if ok_cutoff {
                        material.alpha_cutoff = cutoff;
                    } else {
                        material.alpha_cutoff = 0.5; // gltf default
                    }
                }
                if mode_str.count > 0 then free(mode_str);
            }
        }

        {
            ok_opacity, opacity := try_load_float(ai_material, "$mat.opacity");
            if ok_opacity {
                material.alpha = clamp(opacity, 0.0, 1.0);
                if material.alpha < 0.999 && material.transparency == .DISABLED {
                    material.transparency = .ALPHA_BLEND;
                }
            }
        }

        // diffuse map
        {
            types := aiTextureType.[.BASE_COLOR, .DIFFUSE];
            texture := load_texture_from_material(scene, ai_material, types, path, true, *owned_textures);
            if texture {
                material.diffuse_map = texture;

                if material.transparency == .DISABLED && texture.has_transparency {
                    material.transparency = .ALPHA_SCISSOR;
                    material.alpha_cutoff = 0.5;
                }
            }
        }

        // specular map
        {
            types := aiTextureType.[.SPECULAR];
            texture := load_texture_from_material(scene, ai_material, types, path, false, *owned_textures);
            if texture then material.specular_map = texture;
        }

        array_add(*materials, material);
    }

    // meshes
    process_node(
        scene.mRootNode,
        scene,
        Matrix4_Identity,
        *meshes,
        *material_indices
    );

    return true, meshes, materials, material_indices, owned_textures;
}

// load textures
load_texture_from_material :: (
    scene: *aiScene,
    ai_material: *aiMaterial,
    types: [] aiTextureType,
    model_path: string,
    srgb: bool,
    owned_textures: *[..] *Texture
) -> *Texture {
    for type: types {
        if aiGetMaterialTextureCount(ai_material, type) <= 0 then continue;

        ai_path: aiString;
        if aiGetMaterialTexture(
            ai_material, type, 0, *ai_path,
            null, null, null, null, null, null
        ) != .SUCCESS {
            continue;
        }

        texture_length := cast(s64) ai_path.length;
        if texture_length <= 0 then continue;

        if ai_path.data[0] == #char "*" {
            // parse "*<index>"
            texture_index: s32 = 0;
            for i: 1..texture_length - 1 {
                digit_char := ai_path.data[i];
                if digit_char < #char "0" || digit_char > #char "9" then break;
                texture_index = texture_index * 10 + cast(s32) (digit_char - #char "0");
            }
            if texture_index < 0 || texture_index >= cast(s32) scene.mNumTextures then continue;

            ai_texture := scene.mTextures[texture_index];
            is_compressed := ai_texture.mHeight == 0;

            width, height, channels: s32;
            data: *u8;

            if is_compressed {
                desired_channels: s32 = 4;
                data = stbi_load_from_memory(
                    cast(*u8) ai_texture.pcData,
                    cast(s32) ai_texture.mWidth,
                    *width, *height, *channels, desired_channels
                );
            } else {
                width  = cast(s32) ai_texture.mWidth;
                height = cast(s32) ai_texture.mHeight;

                data = alloc(width * height * 4);
                source := cast(*aiTexel) ai_texture.pcData;

                for i: 0..(width * height) - 1 {
                    data[i * 4 + 0] = source[i].r;
                    data[i * 4 + 1] = source[i].g;
                    data[i * 4 + 2] = source[i].b;
                    data[i * 4 + 3] = source[i].a;
                }
            }

            if data {
                spec := DEFAULT_TEXTURE_SPEC;
                spec.min_filter = .NEAREST;
                spec.mag_filter = .NEAREST;
                spec.generate_mipmaps = false;
                spec.srgb = srgb;
                texture := texture_create_from_data(width, height, data, spec);
                if texture && owned_textures {
                    array_add(owned_textures, texture);
                }

                ifx is_compressed then stbi_image_free(data) else free(data);

                return texture;
            }
        } else {
            // load relative texture
            model_abs, success := get_absolute_path(model_path);
            assert(success, "Failed to get absolute path for texture: %", model_path);

            folder := model_abs;
            last_slash := -1;
            for i: 0..folder.count - 1 {
                if folder[i] == #char "/" || folder[i] == #char "\\" {
                    last_slash = i;
                }
            }
            if last_slash >= 0 then folder.count = last_slash + 1;

            texture_path_buffer := cast(*u8) alloc(texture_length);
            memcpy(texture_path_buffer, *ai_path.data, texture_length);
            defer free(texture_path_buffer);

            // replace backslashes with forward slashes for cross platform compatibility
            for i: 0..texture_length - 1 {
                if texture_path_buffer[i] == #char "\\" {
                    texture_path_buffer[i] = #char "/";
                }
            }

            texture_relative_path: string;
            texture_relative_path.data  = texture_path_buffer;
            texture_relative_path.count = texture_length;

            full_path_str := tprint("%%", folder, texture_relative_path);

            spec := DEFAULT_TEXTURE_SPEC;
            spec.min_filter = .NEAREST;
            spec.mag_filter = .NEAREST;
            spec.generate_mipmaps = false;
            spec.srgb = srgb;

            return asset_manager_load_texture(full_path_str, spec, false);
        }
    }

    return null;
}

// walk nodes
// accumulate Assimp node transforms while traversing so imported meshes land
// in the same baked space the scene expects.
process_node :: (
    node: *aiNode,
    scene: *aiScene,
    parent_transform: Matrix4,
    meshes_out: *[..] *Mesh,
    material_indices_out: *[..] u32
) {
    if !node then return;

    local_transform  := matrix4_from_assimp(node.mTransformation);
    global_transform := parent_transform * local_transform;

    // submit node meshes
    if node.mMeshes {
        for i: 0..node.mNumMeshes - 1 {
            mesh_index := node.mMeshes[i];

            if mesh_index >= scene.mNumMeshes {
                log_error("Mesh index % out of bounds", mesh_index);
                continue;
            }

            ai_mesh := scene.mMeshes[mesh_index];
            if !ai_mesh {
                log_error("Mesh pointer at index % is null", mesh_index);
                continue;
            }

            mesh := build_mesh_from_ai_mesh(ai_mesh, global_transform);
            if mesh {
                array_add(meshes_out, mesh);
                array_add(material_indices_out, ai_mesh.mMaterialIndex);
            }
        }
    }

    // walk children
    if node.mChildren {
        for i: 0..node.mNumChildren - 1 {
            process_node(
                node.mChildren[i],
                scene,
                global_transform,
                meshes_out,
                material_indices_out
            );
        }
    }
}

// normals need the inverse-transpose path because the imported node transform
// may include non-uniform scaling.
build_mesh_from_ai_mesh :: (
    ai_mesh: *aiMesh,
    transform: Matrix4
) -> *Mesh {
    vertices: [..] Vertex;
    indices:  [..] u32;

    success, inverse_transform := inverse(transform);
    assert(success, "Failed to compute inverse");
    // fix normal transform
    normal_matrix := transpose(inverse_transform);

    for i: 0..ai_mesh.mNumVertices - 1 {
        vertex: Vertex;

        pos := ai_mesh.mVertices[i];
        world_pos := transform * Vector4.{pos.x, pos.y, pos.z, 1.0};
        vertex.position = world_pos.xyz;

        if ai_mesh.mNormals {
            normal := ai_mesh.mNormals[i];
            world_normal := normal_matrix * Vector4.{normal.x, normal.y, normal.z, 0.0};
            vertex.normal = normalize(world_normal.xyz);
        } else {
            vertex.normal = .{0, 1, 0};
        }

        if ai_mesh.mTangents {
            tangent := ai_mesh.mTangents[i];
            world_tangent := transform * Vector4.{tangent.x, tangent.y, tangent.z, 0.0};
            vertex.tangent = normalize(world_tangent.xyz);
        } else {
            vertex.tangent = .{1, 0, 0};
        }

        if ai_mesh.mTextureCoords[0] {
            uv := ai_mesh.mTextureCoords[0][i];
            vertex.uv = .{uv.x, uv.y};
        } else {
            vertex.uv = .{0, 0};
        }

        array_add(*vertices, vertex);
    }

    for i: 0..ai_mesh.mNumFaces - 1 {
        face := ai_mesh.mFaces[i];
        for index: 0..face.mNumIndices - 1 {
            array_add(*indices, face.mIndices[index]);
        }
    }

    mesh := mesh_create(vertices, indices);

    array_free(vertices);
    array_free(indices);

    return mesh;
}

matrix4_from_assimp :: (m: aiMatrix4x4) -> Matrix4 {
    result: Matrix4;
    result._11 = m.a1; result._12 = m.a2; result._13 = m.a3; result._14 = m.a4;
    result._21 = m.b1; result._22 = m.b2; result._23 = m.b3; result._24 = m.b4;
    result._31 = m.c1; result._32 = m.c2; result._33 = m.c3; result._34 = m.c4;
    result._41 = m.d1; result._42 = m.d2; result._43 = m.d3; result._44 = m.d4;
    return result;
}
