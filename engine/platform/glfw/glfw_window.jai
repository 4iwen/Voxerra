#scope_file

#import "glfw";
#load "glfw_input.jai";

#scope_export

window_create :: (width: s32, height: s32, title: *u8) -> *GLFWwindow {
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    handle := glfwCreateWindow(width, height, title, null, null);
    if (!handle) {
        log("Failed to create glfw window", flags = .ERROR);
        glfwTerminate();
    }

    glfwMakeContextCurrent(handle);

    // input callbacks
    input_install_callbacks(handle);

    // window resize callback
    glfwSetWindowSizeCallback(handle, window_size_callback);

    return handle;
}

window_destroy :: (handle: *GLFWwindow) {
    glfwDestroyWindow(handle);
}

window_should_close :: (handle: *GLFWwindow) -> bool {
    return cast(bool) glfwWindowShouldClose(handle);
}

window_poll_events :: () {
    glfwPollEvents();
}

window_swap_buffers :: (handle: *GLFWwindow) {
    glfwSwapBuffers(handle);
}

#scope_file

window_size_callback :: (window: *GLFWwindow, width: s32, height: s32) #c_call {
    glfwGetFramebufferSize(window, *width, *height);

    push_context {
        renderer_set_viewport_size(width, height);
    }
}
