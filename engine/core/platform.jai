#scope_file

#import "Basic";
#import,file "../../modules/glfw/module.jai";

#scope_export

init :: () -> bool {
    if (!glfwInit()) {
        log("Initializing glfw failed");
        return false;
    }

    return true;
}

shutdown :: () {
    glfwTerminate();
} 
