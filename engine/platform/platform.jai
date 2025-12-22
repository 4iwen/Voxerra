#scope_module

// @Refactor: there should be an option to configure which windowing backend to use
#if OS == .WINDOWS || OS == .LINUX || OS == .MACOS {
    #load "glfw/glfw_platform.jai";
}
