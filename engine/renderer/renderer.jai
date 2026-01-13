#scope_file

#import "Basic";
#import "Math";
#import "GL";

#scope_export

renderer_init :: () {
    gl_load(*gl, glfwGetProcAddress.(*void));
    
    // enable features
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);

    texture_init();

    log("Initialized renderer");
}

renderer_shutdown :: () {
    texture_shutdown();
    log("Shutdown renderer");
}

renderer_begin_frame :: (color: Vector4 = .{1, 1, 1, 1}) {
    glClearColor(color.x, color.y, color.z, color.w);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

renderer_end_frame :: () {

}

renderer_set_viewport_size :: (width: s32, height: s32) {
    glViewport(0, 0, cast(u32) width, cast(u32) height);
}

renderer_begin_far_depth_pass :: () {
    glDepthFunc(GL_LEQUAL);
}

renderer_end_far_depth_pass :: () {
    glDepthFunc(GL_LESS);
}

renderer_set_culling :: (enabled: bool) {
    if enabled {
        glEnable(GL_CULL_FACE);
    } else {
        glDisable(GL_CULL_FACE);
    }
}
