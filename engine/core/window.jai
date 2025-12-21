#scope_file

#import "Basic";
#import "GL";

#import,file "../../modules/glfw/module.jai";

#scope_export

Window :: struct {
    handle: *GLFWwindow;
};

create :: (width: s32, height: s32, title: *u8) -> Window {
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    handle := glfwCreateWindow(width, height, title, null, null);
    if (!handle) {
        log("Failed to create glfw window");
        glfwTerminate();
    }

    glfwMakeContextCurrent(handle);

    return Window.{ handle = handle };
}

destroy :: (window: Window) {
    glfwDestroyWindow(window.handle);
}

should_close :: (window: Window) -> bool {
    return cast(bool) glfwWindowShouldClose(window.handle);
}

poll_events :: () {
    glfwPollEvents();
}

swap_buffers :: (window: Window) {
    glfwSwapBuffers(window.handle);    
}

