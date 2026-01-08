#scope_file

#import "glfw";

#scope_export

Window :: struct {
    width: s32;
    height: s32;
    framebuffer_width: s32;
    framebuffer_height: s32;
    content_scale_x: float32;
    content_scale_y: float32;
    handle: *GLFWwindow;
}

Cursor_Mode :: enum {
    DISABLED :: GLFW_CURSOR_DISABLED;
    HIDDEN :: GLFW_CURSOR_HIDDEN;
    CAPTURED :: GLFW_CURSOR_CAPTURED;
    NORMAL :: GLFW_CURSOR_NORMAL;
}

window_create :: (width: s32, height: s32, title: *u8) -> *Window {
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    handle := glfwCreateWindow(width, height, title, null, null);
    if (!handle) {
        log_error("Failed to create glfw window");
        glfwTerminate();
        return null;
    }

    log("Created glfw window");

    glfwMakeContextCurrent(handle);

    window := New(Window);
    window.width = width;
    window.height = height;
    window.handle = handle;
    glfwGetWindowContentScale(
        handle,
        *window.content_scale_x,
        *window.content_scale_y
    );
    glfwGetFramebufferSize(
        handle,
        *window.framebuffer_width,
        *window.framebuffer_height
    );

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
    log("Destroyed glfw window");
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

window_set_cursor_mode :: (window: *Window, mode: Cursor_Mode) {
    glfwSetInputMode(window.handle, GLFW_CURSOR, cast(s32) mode);
    input_reset_mouse_position(window.handle);
}

#scope_file

window_size_callback :: (window: *GLFWwindow, width: s32, height: s32) #c_call {
    push_context {
        window_pointer := cast(*Window) glfwGetWindowUserPointer(window);
        if !window_pointer {
            log_warning("Failed to get window user pointer on size callback");
            return;
        }

        window_pointer.width = width;
        window_pointer.height = height;
        
        glfwGetWindowContentScale(
            window,
            *window_pointer.content_scale_x,
            *window_pointer.content_scale_y
        );

        framebuffer_width, framebuffer_height: s32;
        glfwGetFramebufferSize(window, *framebuffer_width, *framebuffer_height);
        window_pointer.framebuffer_width  = framebuffer_width;
        window_pointer.framebuffer_height = framebuffer_height;
        renderer_set_viewport_size(framebuffer_width, framebuffer_height);
    }
}
