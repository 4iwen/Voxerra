#scope_file

#import "Basic";
#import "glfw";

#scope_export

platform_init :: () -> bool {
    if (!glfwInit()) {
        log("Initializing glfw failed");
        return false;
    }

    return true;
}

platform_shutdown :: () {
    glfwTerminate();
} 
