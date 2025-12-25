#scope_file

#import "Basic";

#scope_export

platform_init :: () -> bool {
    if (!glfwInit()) {
        log_error("Initializing glfw failed");
        return false;
    }

    return true;
}

platform_shutdown :: () {
    glfwTerminate();
} 
