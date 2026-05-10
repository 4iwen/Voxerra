// File:        platform.jai
// Author:      Lukáš Bien
// Description: Wraps platform startup, shutdown, and low-level OS integration helpers.

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
        logging_install_logger();
        log_error("Glfw error %: %", error, to_string(description));
    }
}
