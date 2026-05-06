// File:        time.jai
// Author:      Lukáš Bien
// Description: Tracks frame timing values used across the engine runtime.

#scope_file

#import "glfw";

#scope_export

time_get :: () -> float64 {
    return glfwGetTime();
}
