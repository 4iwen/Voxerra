#scope_file

#import "glfw";

#scope_export

time_get :: () -> float64 {
    return glfwGetTime();
}
