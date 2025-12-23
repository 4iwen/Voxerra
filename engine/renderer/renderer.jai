#scope_file

#import "Basic";
#import "GL";

#scope_export

Color :: struct {
    r: float;
    g: float;
    b: float;
    a: float;
}

VERTEX_SRC :: #string DONE
#version 330 core

layout (location = 0) in vec3 pos;

void main() {
    gl_Position = vec4(pos.x, pos.y, pos.z, 1.0);
}
DONE

FRAGMENT_SRC :: #string DONE
#version 330 core

out vec4 color;

void main() {
    color = vec4(1.0f, 0.5f, 0.2f, 1.0f);
}
DONE

shader: Shader;

vertex_buffer_object_id: u32;
vertex_array_object_id: u32;
element_buffer_object_id: u32;

vertices: [9] float = .[
    -0.5, -0.5, 0.0,
    0.5, -0.5, 0.0,
    0.0, 0.5, 0.0
];  

indices: [3] u32 = .[
    0, 1, 2
];

renderer_init :: () {
    gl_load(*gl, glfwGetProcAddress.(*void));

    LOG_BUFFER_SIZE :: 512;
    success: GLint;
    
    shader = shader_create(VERTEX_SRC, FRAGMENT_SRC);

    // triangle opengl data stuff
    glGenVertexArrays(1, *vertex_array_object_id);
    glGenBuffers(1, *vertex_buffer_object_id);
    glGenBuffers(1, *element_buffer_object_id);

    glBindVertexArray(vertex_array_object_id);

    glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer_object_id);
    glBufferData(GL_ARRAY_BUFFER, size_of(type_of(vertices)), vertices.data, GL_STATIC_DRAW);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, element_buffer_object_id);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, size_of(type_of(indices)), indices.data, GL_STATIC_DRAW);

    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * size_of(float), null);
    glEnableVertexAttribArray(0);

    glBindBuffer(GL_ARRAY_BUFFER, 0); 

    glBindVertexArray(0); 
}

renderer_shutdown :: () {
    glDeleteVertexArrays(1, *vertex_array_object_id);
    glDeleteBuffers(1, *vertex_buffer_object_id);
    glDeleteBuffers(1, *element_buffer_object_id);

    shader_destroy(shader);
}

renderer_begin_frame :: (color: Color) {
    glClearColor(color.r, color.g, color.b, color.a);
    glClear(GL_COLOR_BUFFER_BIT);

    shader_use(shader);
    
    // draw triangle
    glBindVertexArray(vertex_array_object_id);
    glDrawElements(GL_TRIANGLES, 3, GL_UNSIGNED_INT, cast(*void) 0);
}

renderer_end_frame :: () {

}

renderer_set_viewport_size :: (width: s32, height: s32) {
    glViewport(0, 0, cast(u32) width, cast(u32) height);
}
