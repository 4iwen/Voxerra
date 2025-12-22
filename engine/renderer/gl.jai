#scope_file

#import "Basic";
#import "GL";
#import "glfw";

#scope_export

Color :: struct {
    r: float;
    g: float;
    b: float;
    a: float;
};

renderer_init :: () {
    gl_load(*gl, glfwGetProcAddress.(*void));
}

renderer_shutdown :: () {

}

renderer_begin_frame :: (color: Color) {
    glClear(GL_COLOR_BUFFER_BIT);
    glClearColor(color.r, color.g, color.b, color.a);
}

renderer_end_frame :: () {

}
