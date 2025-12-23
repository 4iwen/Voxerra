#scope_file

#import "Basic";

#scope_export

platform_init :: () -> bool {
    if (!glfwInit()) {
        log("Initializing glfw failed", flags = .ERROR);
        return false;
    }

    return true;
}

platform_shutdown :: () {
    glfwTerminate();
} 
