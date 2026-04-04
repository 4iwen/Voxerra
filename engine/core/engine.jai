#scope_file

#import "Basic";

#scope_module

Engine_State :: struct {
    window: *Window;
    main_framebuffer: *Framebuffer;
    current_scene: *Scene;
    last_time: float64;
    delta_time: float64;
}

engine_state: Engine_State;

#scope_export

engine_init :: () -> bool {
    log_install();

    if !platform_init() {
        return false;
    }

    return true;
}

window_init :: (
    width: s32,
    height: s32,
    title: *u8
) -> *Window {
    window := window_create(width, height, title);
    if !window {
        return null;
    }
    engine_state.window = window;

    renderer_init();

    renderer_set_viewport_size(
        window.framebuffer_width,
        window.framebuffer_height
    );

    asset_manager_init();

    ui_init(window);

    engine_state.last_time = time_get();
    engine_state.delta_time = 0;

    log("Initialized window");

    return window;
}

engine_get_delta_time :: () -> float64 {
    return engine_state.delta_time;
}

engine_begin_frame :: (clear_color: Vector4 = .{0, 0, 0, 1}) -> float64 {
    // delta time
    current_time := time_get();
    delta_time := current_time - engine_state.last_time;
    engine_state.last_time = current_time;
    engine_state.delta_time = delta_time;

    // engine systems
    asset_manager_update();
    input_poll();
    window_poll_events();

    // ui
    ui_begin_frame();
    ui_draw();

    // render
    renderer_begin_frame(clear_color);

    return delta_time;
}

engine_end_frame :: () {
    ui_end_frame();
    renderer_end_frame();
    window_swap_buffers(engine_state.window);
}

engine_shutdown :: () {
    ui_shutdown();
    asset_manager_shutdown();
    renderer_shutdown();
    window_destroy(engine_state.window);
    input_shutdown();
    platform_shutdown();
}
