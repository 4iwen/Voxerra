#import "Basic";
#import "GL";

Platform :: #import,file "../engine/core/platform.jai";
Window :: #import,file "../engine/core/window.jai";
Renderer :: #import,file "../engine/renderer/gl.jai";

main :: () {
    Platform.init();
    defer Platform.shutdown();

    window := Window.create(960, 600, "Voxerra");
    defer Window.destroy(window);

    Renderer.init();
    defer Renderer.shutdown();

    while !Window.should_close(window) {
        Window.poll_events();
        
        Renderer.clear(.{ 0.0, 0.0, 0.2, 1.0 });
        
        Window.swap_buffers(window);
    }
}
