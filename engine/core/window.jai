#scope_file

#import "glfw";

#scope_export

Window :: struct {
    width: s32;
    height: s32;
    handle: *GLFWwindow;
}

window_create :: (width: s32, height: s32, title: *u8) -> *Window {
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    handle := glfwCreateWindow(width, height, title, null, null);
    if (!handle) {
        log("Failed to create glfw window", flags = .ERROR);
        glfwTerminate();
        return null;
    }

    glfwMakeContextCurrent(handle);

    window := New(Window);
    window.width = width;
    window.height = height;
    window.handle = handle;

    glfwSetWindowUserPointer(handle, window);

    // input callbacks
    input_install_callbacks(handle);

    // window resize callback
    glfwSetWindowSizeCallback(handle, window_size_callback);

    return window;
}

window_destroy :: (window: *Window) {
    glfwDestroyWindow(window.handle);
    free(window);
}

window_should_close :: (window: *Window) -> bool {
    return cast(bool) glfwWindowShouldClose(window.handle);
}

window_poll_events :: () {
    glfwPollEvents();
}

window_swap_buffers :: (window: *Window) {
    glfwSwapBuffers(window.handle);
}

window_set_vsync :: (vsync: bool) {
    glfwSwapInterval(cast(s32) ifx vsync then 1 else 0); 
}

#scope_file

window_size_callback :: (window: *GLFWwindow, width: s32, height: s32) #c_call {
    push_context {
        window_pointer := cast(*Window) glfwGetWindowUserPointer(window);
        if !window_pointer {
            log("Failed to get window user pointer on size callback");
            return;
        }

        window_pointer.width = width;
        window_pointer.height = height;
        
        framebuffer_width, framebuffer_height: s32;
        glfwGetFramebufferSize(window, *framebuffer_width, *framebuffer_height);
        renderer_set_viewport_size(framebuffer_width, framebuffer_height);
    }
}
