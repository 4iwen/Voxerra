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

vertices: [9] float = .[
    -0.5, -0.5, 0.0,
    0.5, -0.5, 0.0,
    0.0, 0.5, 0.0
];  

indices: [3] u32 = .[
    0, 1, 2
];

triangle_mesh: Mesh;

renderer_init :: () {
    gl_load(*gl, glfwGetProcAddress.(*void));
    
    shader = shader_create(VERTEX_SRC, FRAGMENT_SRC);

    triangle_mesh = mesh_create(vertices, indices);
}

renderer_shutdown :: () {
    mesh_destroy(triangle_mesh);
    shader_destroy(shader);
}

renderer_begin_frame :: (color: Color) {
    glClearColor(color.r, color.g, color.b, color.a);
    glClear(GL_COLOR_BUFFER_BIT);

    shader_use(shader);
    
    mesh_draw(triangle_mesh);
}

renderer_end_frame :: () {

}

renderer_set_viewport_size :: (width: s32, height: s32) {
    glViewport(0, 0, cast(u32) width, cast(u32) height);
}
