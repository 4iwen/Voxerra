#scope_file

#import "jassimp";
#import "stb_image";

#scope_export

Model :: struct {
    submeshes: [..] *Sub_Mesh;
    materials: [..] *Material;
}

Sub_Mesh :: struct {
    mesh: *Mesh;
    material: *Material;
}

Model_Load_Options :: struct {
    flip_uvs: bool;
    calculate_tangents: bool;
    merge_meshes: bool;
}

DEFAULT_MODEL_LOAD_OPTIONS :: Model_Load_Options.{
    flip_uvs = false,
    calculate_tangents = true,
    merge_meshes = false
};

model_create_from_file :: (
    path: string,
    options: Model_Load_Options = DEFAULT_MODEL_LOAD_OPTIONS
) -> *Model {
    ok, meshes, materials, material_indices := assimp_load_meshes(path, options);
    if !ok {
        log_error("Failed to load mesh file: %", path);
        return null;
    }
    
    model := New(Model);
    model.materials = materials;
    
    for mesh, idx: meshes {
        submesh := New(Sub_Mesh);
        submesh.mesh = mesh;
        
        mat_idx := material_indices[idx];
        if mat_idx < materials.count {
            submesh.material = materials[mat_idx];
        }
        
        array_add(*model.submeshes, submesh);
    }
    
    return model;
}

model_destroy :: (model: *Model) {
    for model.submeshes {
        mesh_destroy(it.mesh);
        free(it);
    }
    array_reset(*model.submeshes);

    for model.materials {
        material_destroy(it);
    }
    array_reset(*model.materials);

    free(model);
}

model_reload_from_file :: (
    model: *Model,
    path: string,
    options: Model_Load_Options
) -> bool {
    ok, meshes, materials, material_indices := assimp_load_meshes(path, options);
    if !ok || meshes.count == 0 {
        for meshes { 
            mesh_destroy(it);
        }
        for materials {
            material_destroy(it);
        }
        return false;
    }

    // destroy previous submeshes
    for model.submeshes {
        mesh_destroy(it.mesh);
        free(it);
    }
    array_reset(*model.submeshes);

    // destroy previous materials
    for model.materials {
        material_destroy(it);
    }
    array_reset(*model.materials);

    // rebuild submeshes from freshly loaded data
    model.materials = materials;
    for mesh, idx: meshes {
        sm := New(Sub_Mesh);
        sm.mesh = mesh;
        mat_idx := material_indices[idx];
        if mat_idx < materials.count {
            sm.material = materials[mat_idx];
        }
        array_add(*model.submeshes, sm);
    }

    return true;
}

#scope_file

assimp_load_meshes :: (
    path: string,
    options: Model_Load_Options
) -> bool, [..] *Mesh, [..] *Material, [..] u32 {
    meshes: [..] *Mesh;
    materials: [..] *Material;
    material_indices: [..] u32;

    path_c := to_c_string(path);
    defer free(path_c);

    // import file with assimp
    flags := aiPostProcessSteps.Triangulate | 
             aiPostProcessSteps.JoinIdenticalVertices |
             aiPostProcessSteps.GenUVCoords;
    
    if options.calculate_tangents {
        flags |= aiPostProcessSteps.CalcTangentSpace;
    }
    if options.flip_uvs {
        flags |= aiPostProcessSteps.FlipUVs;
    }
    
    scene := aiImportFile(path_c, cast(u32) flags);
    if !scene {
        error := aiGetErrorString();
        if error {
            log_error("Assimp failed to load file: %, Error: %", path, error);
        } else {
            log_error("Assimp failed to load file: %", path);
        }
        return false, meshes, materials, material_indices;
    }
    defer aiReleaseImport(scene);

    if scene.mFlags & AI_SCENE_FLAGS_INCOMPLETE {
        error := aiGetErrorString();
        if error {
            log_error("Assimp scene incomplete: %, Error: %", path, error);
        } else {
            log_error("Assimp scene incomplete: %", path);
        }
        return false, meshes, materials, material_indices;
    }

    if scene.mNumMeshes == 0 {
        log_error("No meshes found in file: %", path);
        return false, meshes, materials, material_indices;
    }
    

    // materials
    for mat_idx: 0..scene.mNumMaterials - 1 {
        ai_mat := scene.mMaterials[mat_idx];
        material := material_create();
        
        // scalars
        try_load_float :: (mat: *aiMaterial, key: string) -> bool, float {
            v: float;
            n: u32 = 1;

            key_c := to_c_string(key);
            defer free(key_c);
        
            if aiGetMaterialFloatArray(mat, key_c, 0, 0, *v, *n) == .SUCCESS {
                return true, v;
            }

            return false, 0.0;
        }

        found_metallic  := false;
        found_roughness := false;

        // metallic
        if !found_metallic {
            ok, v := try_load_float(ai_mat, "$mat.metallicFactor");
            if ok { 
                material.metallic = v;
                found_metallic = true;
            }
        }
        if !found_metallic {
            ok, v := try_load_float(
                ai_mat,
                "$mat.gltf.pbrMetallicRoughness.metallicFactor"
            );
            if ok { 
                material.metallic = v;
                found_metallic = true;
            }
        }

        // roughness
        if !found_roughness {
            ok, v := try_load_float(ai_mat, "$mat.roughnessFactor");
            if ok { 
                material.roughness = v;
                found_roughness = true;
            }
        }
        if !found_roughness {
            ok, v := try_load_float(
                ai_mat,
                "$mat.gltf.pbrMetallicRoughness.roughnessFactor"
            );
            if ok { 
                material.roughness = v;
                found_roughness = true;
            }
        }

        // legacy fallback
        if !found_roughness {
            ok, shininess := try_load_float(ai_mat, "$mat.shininess");
            if ok {
                material.roughness = sqrt(2.0 / (shininess + 2.0));

                if !found_metallic {
                    material.metallic = 0.0;
                    found_metallic = true;
                }
                found_roughness = true;
            }
        }

        // textures
        // albedo
        {
            types := aiTextureType.[.BASE_COLOR, .DIFFUSE];
            tex := load_texture_from_material(scene, ai_mat, types, path, true);
            if tex {
                material.albedo_texture = tex;
            }
        }

        // normal 
        {
            types := aiTextureType.[.GLTF_METALLIC_ROUGHNESS, .UNKNOWN];
            tex := load_texture_from_material(scene, ai_mat, types, path, false);

            if tex {
                material.metallic_roughness_texture = tex;
            } else {
                types := aiTextureType.[.METALNESS];
                tex := load_texture_from_material(scene, ai_mat, types, path, false);
                if tex {
                    material.metallic_roughness_texture = tex;
                }
            }
        }

        // oclussion
        {
            types := aiTextureType.[.AMBIENT_OCCLUSION, .LIGHTMAP];
            tex := load_texture_from_material(scene, ai_mat, types, path, false);
            if tex {
                material.occlusion_texture = tex;
            }
        }

        // emissive
        {
            types := aiTextureType.[.EMISSIVE, .EMISSION_COLOR];
            tex := load_texture_from_material(scene, ai_mat, types, path, true);
            if tex material.emissive_texture = tex;
        }

        array_add(*materials, material);
    }

    // meshes
    for mesh_idx: 0..scene.mNumMeshes - 1 {
        ai_mesh := scene.mMeshes[mesh_idx];
        
        if !ai_mesh.mVertices {
            log_warning("Mesh % has no vertices, skipping", mesh_idx);
            continue;
        }

        vertices: [..] Vertex;
        indices: [..] u32;
        
        // vertices
        for i: 0..ai_mesh.mNumVertices - 1 {
            vertex: Vertex;
            
            // position
            pos := ai_mesh.mVertices[i];
            vertex.position = .{pos.x, pos.y, pos.z};
            
            // normal
            if ai_mesh.mNormals {
                normal := ai_mesh.mNormals[i];
                vertex.normal = .{normal.x, normal.y, normal.z};
            } else {
                vertex.normal = .{0.0, 1.0, 0.0};
            }
            
            // tangent
            if ai_mesh.mTangents {
                tangent := ai_mesh.mTangents[i];
                vertex.tangent = .{tangent.x, tangent.y, tangent.z};
            } else {
                vertex.tangent = .{1.0, 0.0, 0.0};
            }
            
            // uv
            if ai_mesh.mTextureCoords[0] {
                uv := ai_mesh.mTextureCoords[0][i];
                vertex.uv = .{uv.x, uv.y};
            } else {
                vertex.uv = .{0.0, 0.0};
            }
            
            array_add(*vertices, vertex);
        }

        // indices
        for i: 0..ai_mesh.mNumFaces - 1 {
            face := ai_mesh.mFaces[i];
            for j: 0..face.mNumIndices - 1 {
                array_add(*indices, face.mIndices[j]);
            }
        }
        
        mesh := mesh_create(vertices, indices);
        
        array_add(*meshes, mesh);
        array_add(*material_indices, ai_mesh.mMaterialIndex);
        
        array_reset(*vertices);
        array_reset(*indices);
    }

    return true, meshes, materials, material_indices;
}

load_texture_from_material :: (
    scene: *aiScene, 
    ai_mat: *aiMaterial, 
    types: [] aiTextureType, 
    model_path: string,
    srgb: bool
) -> *Texture {
    for type: types {
        if aiGetMaterialTextureCount(ai_mat, type) <= 0 {
            continue;
        }

        ai_path: aiString;
        if aiGetMaterialTexture(
            ai_mat, type, 0, *ai_path,
            null, null, null, null, null, null
        ) != .SUCCESS {
            continue;
        }

        tex_len := cast(s64) ai_path.length;
        if tex_len <= 0 {
            continue;
        }

        if ai_path.data[0] == #char "*" {
            // embedded texture
            tex_idx := ai_path.data[1] - #char "0";
            if tex_idx < 0 || tex_idx >= cast(u8) scene.mNumTextures {
                continue;
            }

            ai_tex := scene.mTextures[tex_idx];
            is_compressed := ai_tex.mHeight == 0;

            width, height, channels: s32;
            data: *u8;

            if is_compressed {
                desired_channels: s32 = 4;
                data = stbi_load_from_memory(
                    cast(*u8) ai_tex.pcData,
                    cast(s32) ai_tex.mWidth,
                    *width, *height, *channels, desired_channels
                );
            } else {
                width = cast(s32) ai_tex.mWidth;
                height = cast(s32) ai_tex.mHeight;

                data = alloc(width * height * 4);
                src := cast(*aiTexel) ai_tex.pcData;
                
                for i: 0..(width * height) - 1 {
                    data[i * 4 + 0] = src[i].r;
                    data[i * 4 + 1] = src[i].g;
                    data[i * 4 + 2] = src[i].b;
                    data[i * 4 + 3] = src[i].a;
                }
            }

            if data {
                spec := DEFAULT_TEXTURE_SPEC;
                spec.srgb = srgb;
                tex := texture_create_from_data(width, height, data, spec);

                ifx is_compressed then stbi_image_free(data) else free(data); 
                
                return tex;
            }
        } else {
            // external texture
            model_abs, success := get_absolute_path(model_path);
            assert(success, "Failed to get absolute path for texture: %", model_path);

            folder := model_abs;
            last_slash := -1;
            for i: 0..folder.count - 1 {
                if folder[i] == #char "/" || folder[i] == #char "\\" {
                    last_slash = i;
                }
            }
            if last_slash >= 0 {
                folder.count = last_slash + 1;
            }

            // convert path
            tex_path_buf := cast(*u8) alloc(tex_len);
            memcpy(tex_path_buf, *ai_path.data, tex_len);
            defer free(tex_path_buf);
            
            tex_rel: string;
            tex_rel.data = tex_path_buf;
            tex_rel.count = tex_len;

            full_path_str := tprint("%%", folder, tex_rel);
            
            spec := DEFAULT_TEXTURE_SPEC;
            spec.srgb = srgb;
            
            return asset_manager_load_texture(full_path_str, spec, false);
        }
    }
    
    return null; 
}
