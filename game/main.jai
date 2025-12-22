#import "Basic";

#import "engine";

main :: () {
    platform_init();
    defer platform_shutdown();

    window := window_create(960, 600, "Voxerra");
    defer window_destroy(window);

    renderer_init();
    defer renderer_shutdown();

    while !window_should_close(window) {
        input_begin_frame();

        window_poll_events();

        renderer_begin_frame(.{ 0.0, 0.0, 0.2, 1.0 });
        
        renderer_end_frame();

        window_swap_buffers(window);
    }
}
