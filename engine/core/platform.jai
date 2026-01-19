#scope_file

#import "Basic";

#scope_export

platform_init :: () -> bool {
    glfwSetErrorCallback(glfw_error_callback);

    if (!glfwInit()) {
        
        log_error("Initializing glfw failed");
        return false;
    }

    log("Initialized glfw");
    return true;
}

platform_shutdown :: () {
    glfwTerminate();
    log("Shutdown glfw");
} 

#scope_file

glfw_error_callback :: (error: s32, description: *u8) #c_call {
    push_context {
        log_install();
        log_error("Glfw error %: %", error, to_string(description));
    }
}
