#scope_module

// @Refactor: there should be an option to configure which renderer to use
#if OS == .WINDOWS || OS == .LINUX || OS == .MACOS {
    #load "opengl/opengl_renderer.jai";
}
