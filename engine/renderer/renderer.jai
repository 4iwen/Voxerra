#scope_file

#import "Basic";
#import "GL";

#scope_export

// @Cleanup: move this elsewhere 
Color :: struct {
    r: float;
    g: float;
    b: float;
    a: float;
}

renderer_init :: () {
    gl_load(*gl, glfwGetProcAddress.(*void));
    
    // enable features
    glEnable(GL_DEPTH_TEST);

    texture_init();

    log("Initialized renderer");
}

renderer_shutdown :: () {
    texture_shutdown();
    log("Shutdown renderer");
}

renderer_begin_frame :: (color: Color) {
    glClearColor(color.r, color.g, color.b, color.a);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

renderer_end_frame :: () {

}

renderer_set_viewport_size :: (width: s32, height: s32) {
    glViewport(0, 0, cast(u32) width, cast(u32) height);
}
