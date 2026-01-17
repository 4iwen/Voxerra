#scope_file

#import "Basic";
#import "File";
#import "Hash_Table";
#import "GL";
#import "Math";
#import "String";

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

    bounds_min: Vector3;
    bounds_max: Vector3;
}

mesh_create :: (vertices: [] Vertex, indices: [] u32) -> *Mesh {
    mesh := New(Mesh);
    mesh.vertex_count = cast(u32) vertices.count;
    mesh.index_count = cast(u32) indices.count;

    // calculate bounds
    if vertices.count > 0 {
        min := vertices[0].position;
        max := vertices[0].position;

        for v: vertices {
            if v.position.x < min.x then min.x = v.position.x;
            if v.position.y < min.y then min.y = v.position.y;
            if v.position.z < min.z then min.z = v.position.z;

            if v.position.x > max.x then max.x = v.position.x;
            if v.position.y > max.y then max.y = v.position.y;
            if v.position.z > max.z then max.z = v.position.z;
        }

        mesh.bounds_min = min;
        mesh.bounds_max = max;
    }

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

mesh_destroy :: (mesh: *Mesh) {
    glDeleteVertexArrays(1, *mesh.vao_id);
    glDeleteBuffers(1, *mesh.vbo_id);
    glDeleteBuffers(1, *mesh.ebo_id);
    free(mesh);
}

mesh_draw :: (mesh: *Mesh) {
    glBindVertexArray(mesh.vao_id);
    glDrawElements(GL_TRIANGLES, mesh.index_count, GL_UNSIGNED_INT, null);
    glBindVertexArray(0);
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
        0, 2, 3
    ];
    
    return mesh_create(vertices, indices);
}

mesh_create_cube :: () -> *Mesh {
    vertices: [8] Vertex;
    vertices[0].position = .{-1.0, -1.0, 1.0};
    vertices[1].position = .{1.0, -1.0, 1.0};
    vertices[2].position = .{1.0, 1.0, 1.0};
    vertices[3].position = .{-1.0, 1.0, 1.0};
    vertices[4].position = .{-1.0, -1.0, -1.0};
    vertices[5].position = .{1.0, -1.0, -1.0};
    vertices[6].position = .{1.0, 1.0, -1.0};
    vertices[7].position = .{-1.0, 1.0, -1.0};

    indices: [36] u32 = .[
        // front
        0, 1, 2, 2, 3, 0,
        // back
        5, 4, 7, 7, 6, 5,
        // left
        4, 0, 3, 3, 7, 4,
        // right
        1, 5, 6, 6, 2, 1,
        // top
        3, 2, 6, 6, 7, 3,
        // bottom
        4, 5, 1, 1, 0, 4
    ];

    return mesh_create(vertices, indices);
}
