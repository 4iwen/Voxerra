#scope_file

#import "Basic";
#import "GL";

#scope_export

Mesh :: struct {
    vao_id: u32;
    vbo_id: u32;
    ebo_id: u32;

    vertex_count: u32;
    index_count: u32;
}

mesh_create :: (vertices: [] float, indices: [] u32) -> Mesh {
    mesh: Mesh;

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
        vertices.count * size_of(float),
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

    // set vertex attributes
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * size_of(float), null);
    glEnableVertexAttribArray(0);

    // unbind
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);

    return mesh;
}

mesh_destroy :: (mesh: Mesh) {
    glDeleteVertexArrays(1, *mesh.vao_id);
    glDeleteBuffers(1, *mesh.vbo_id);
    glDeleteBuffers(1, *mesh.ebo_id);
}

mesh_draw :: (mesh: Mesh) {
    glBindVertexArray(mesh.vao_id);
    glDrawElements(GL_TRIANGLES, mesh.index_count, GL_UNSIGNED_INT, null);
    glBindVertexArray(0);
}
