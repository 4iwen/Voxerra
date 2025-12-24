#scope_file

#import "Basic";
#import "glfw";

#scope_export

time_get :: () -> float64 {
    return glfwGetTime();
}
