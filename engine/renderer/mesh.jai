#scope_file

#import "Basic";
#import "File";
#import "Hash_Table";
#import "GL";
#import "Math";
#import "String";
#import "jassimp";

#scope_export

Vertex :: struct {
    position: Vector3;
    normal: Vector3;
    tangent: Vector3;
    uv: Vector2;
}

Mesh :: struct {
    vao_id: u32;
    vbo_id: u32;
    ebo_id: u32;

    vertex_count: u32;
    index_count: u32;
    material_index: u32;
}

Mesh_Group :: struct {
    meshes: [..] *Mesh;
    materials: [..] *Material;
}

Mesh_Load_Options :: struct {
    flip_uvs: bool;
    calculate_tangents: bool;
    merge_meshes: bool;
}

DEFAULT_MESH_LOAD_OPTIONS :: Mesh_Load_Options.{
    flip_uvs = false,
    calculate_tangents = true,
    merge_meshes = false
};

// load a single mesh from file
mesh_create_from_file :: (
    path: string,
    options: Mesh_Load_Options = DEFAULT_MESH_LOAD_OPTIONS
) -> *Mesh {
    group := mesh_group_create_from_file(path, options);
    if !group || group.meshes.count == 0 {
        return null;
    }
    
    mesh := group.meshes[0];
    
    // clean up the group structure but keep the mesh
    array_reset(*group.meshes);
    mesh_group_destroy(group);
    
    return mesh;
}

// load multiple meshes from file
mesh_group_create_from_file :: (
    path: string,
    options: Mesh_Load_Options = DEFAULT_MESH_LOAD_OPTIONS
) -> *Mesh_Group {
    ok, meshes, materials := assimp_load_meshes(path, options);
    if !ok {
        log_error("Failed to load mesh file:\n%", path);
        return null;
    }
    
    group := New(Mesh_Group);
    group.meshes = meshes;
    group.materials = materials;
    
    return group;
}

mesh_reload_from_file :: (
    mesh: *Mesh,
    path: string,
    options: Mesh_Load_Options
) -> bool {
    // load new mesh data
    ok, meshes, materials := assimp_load_meshes(path, options);
    if !ok || meshes.count == 0 {
        // cleanup if we got partial data
        for meshes {
            mesh_destroy(it);
        }
        for materials {
            material_destroy(it);
        }
        return false;
    }
    
    // get the first mesh
    new_mesh := meshes[0];
    
    // swap gpu resources
    old_vao := mesh.vao_id;
    old_vbo := mesh.vbo_id;
    old_ebo := mesh.ebo_id;
    
    mesh.vao_id = new_mesh.vao_id;
    mesh.vbo_id = new_mesh.vbo_id;
    mesh.ebo_id = new_mesh.ebo_id;
    mesh.vertex_count = new_mesh.vertex_count;
    mesh.index_count = new_mesh.index_count;
    mesh.material_index = new_mesh.material_index;
    
    // delete old resources
    glDeleteVertexArrays(1, *old_vao);
    glDeleteBuffers(1, *old_vbo);
    glDeleteBuffers(1, *old_ebo);
    
    free(new_mesh);
    
    // clean up old stuff
    for i: 1..meshes.count - 1 {
        mesh_destroy(meshes[i]);
    }
    for materials {
        material_destroy(it);
    }
    
    return true;
}

mesh_create :: (vertices: [] Vertex, indices: [] u32) -> *Mesh {
    mesh := New(Mesh);
    mesh.vertex_count = cast(u32) vertices.count;
    mesh.index_count = cast(u32) indices.count;

    // generate buffers
    glGenVertexArrays(1, *mesh.vao_id);
    glGenBuffers(1, *mesh.vbo_id);
    glGenBuffers(1, *mesh.ebo_id);

    // load vertex data
    glBindVertexArray(mesh.vao_id);
    glBindBuffer(GL_ARRAY_BUFFER, mesh.vbo_id);
    glBufferData(
        GL_ARRAY_BUFFER,
        vertices.count * size_of(Vertex),
        vertices.data, 
        GL_STATIC_DRAW
    );

    // load index data
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, mesh.ebo_id);
    glBufferData(
        GL_ELEMENT_ARRAY_BUFFER,
        indices.count * size_of(u32),
        indices.data,
        GL_STATIC_DRAW
    );

    // setup vertex attributes
    stride := cast(GLsizei) size_of(Vertex);
    
    // position
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, cast(*void)0);
    glEnableVertexAttribArray(0);

    // normal
    glVertexAttribPointer(
        1,
        3,
        GL_FLOAT,
        GL_FALSE,
        stride,
        cast(*void)(size_of(Vector3))
    );
    glEnableVertexAttribArray(1);

    // tangent
    glVertexAttribPointer(
        2,
        3,
        GL_FLOAT,
        GL_FALSE,
        stride,
        cast(*void)(size_of(Vector3) * 2)
    );
    glEnableVertexAttribArray(2);

    // uv
    glVertexAttribPointer(
        3,
        2,
        GL_FLOAT,
        GL_FALSE,
        stride,
        cast(*void)(size_of(Vector3) * 3)
    );
    glEnableVertexAttribArray(3);

    // unbind
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);

    return mesh;
}

#scope_file

assimp_load_meshes :: (
    path: string,
    options: Mesh_Load_Options
) -> bool, [..] *Mesh, [..] *Material {
    meshes: [..] *Mesh;
    materials: [..] *Material;

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
            log_error("Assimp failed to load file:\n%\nError: %", path, error);
        } else {
            log_error("Assimp failed to load file:\n%", path);
        }
        return false, meshes, materials;
    }
    defer aiReleaseImport(scene);

    if scene.mFlags & AI_SCENE_FLAGS_INCOMPLETE {
        error := aiGetErrorString();
        if error {
            log_error("Assimp scene incomplete:\n%\nError: %", path, error);
        } else {
            log_error("Assimp scene incomplete:\n%", path);
        }
        return false, meshes, materials;
    }

    if scene.mNumMeshes == 0 {
        log_error("No meshes found in file:\n%", path);
        return false, meshes, materials;
    }

    // @Todo: load materials
    // ---

    // process all meshes
    for mesh_idx: 0..scene.mNumMeshes - 1 {
        ai_mesh := scene.mMeshes[mesh_idx];
        
        if !ai_mesh.mVertices {
            log_warning("Mesh % has no vertices, skipping", mesh_idx);
            continue;
        }

        vertices: [..] Vertex;
        indices: [..] u32;
        
        // load vertices with all attributes
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

        // build index buffer
        for i: 0..ai_mesh.mNumFaces - 1 {
            face := ai_mesh.mFaces[i];
            for j: 0..face.mNumIndices - 1 {
                array_add(*indices, face.mIndices[j]);
            }
        }
        
        mesh := mesh_create(vertices, indices);
        mesh.material_index = ai_mesh.mMaterialIndex;
        
        array_add(*meshes, mesh);
        
        array_reset(*vertices);
        array_reset(*indices);
    }

    return true, meshes, materials;
}

#scope_export

mesh_destroy :: (mesh: *Mesh) {
    glDeleteVertexArrays(1, *mesh.vao_id);
    glDeleteBuffers(1, *mesh.vbo_id);
    glDeleteBuffers(1, *mesh.ebo_id);
    free(mesh);
}

mesh_group_destroy :: (group: *Mesh_Group) {
    for group.meshes {
        mesh_destroy(it);
    }
    for group.materials {
        material_destroy(it);
    }
    array_reset(*group.meshes);
    array_reset(*group.materials);
    free(group);
}

mesh_draw :: (mesh: *Mesh) {
    glBindVertexArray(mesh.vao_id);
    glDrawElements(GL_TRIANGLES, mesh.index_count, GL_UNSIGNED_INT, null);
    glBindVertexArray(0);
}

mesh_group_draw :: (group: *Mesh_Group) {
    for group.meshes {
        mesh_draw(it);
    }
}

mesh_create_quad :: () -> *Mesh {
    vertices: [4] Vertex;
    
    // bottom left
    vertices[0].position = .{-1.0, -1.0, 0.0};
    vertices[0].normal = .{0.0, 0.0, 1.0};
    vertices[0].tangent = .{1.0, 0.0, 0.0};
    vertices[0].uv = .{0.0, 0.0};
    
    // bottom right
    vertices[1].position = .{1.0, -1.0, 0.0};
    vertices[1].normal = .{0.0, 0.0, 1.0};
    vertices[1].tangent = .{1.0, 0.0, 0.0};
    vertices[1].uv = .{1.0, 0.0};
    
    // top right
    vertices[2].position = .{1.0, 1.0, 0.0};
    vertices[2].normal = .{0.0, 0.0, 1.0};
    vertices[2].tangent = .{1.0, 0.0, 0.0};
    vertices[2].uv = .{1.0, 1.0};
    
    // top left
    vertices[3].position = .{-1.0, 1.0, 0.0};
    vertices[3].normal = .{0.0, 0.0, 1.0};
    vertices[3].tangent = .{1.0, 0.0, 0.0};
    vertices[3].uv = .{0.0, 1.0};
    
    indices: [6] u32 = .[
        0, 1, 2,
        2, 3, 0
    ];
    
    return mesh_create(vertices, indices);
}
