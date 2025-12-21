#scope_file

#import "Basic";
#import "GL";
#import,file "../../modules/glfw/module.jai";

#scope_export

Color :: struct {
    r: float;
    g: float;
    b: float;
    a: float;
};

init :: () {
    gl_load(*gl, glfwGetProcAddress.(*void));
}

shutdown :: () {

}

clear :: (color: Color) {
    glClear(GL_COLOR_BUFFER_BIT);
    glClearColor(color.r, color.g, color.b, color.a);
}
