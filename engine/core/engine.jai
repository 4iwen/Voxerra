#scope_file

#import "Basic";

#scope_export

Engine_State :: struct {
    platform_initialized: bool;
    asset_manager_initialized: bool;
    renderer_initialized: bool;
    text_initialized: bool;
    window: *Window;
    last_time: float64;
    delta_time: float64;
}

#scope_module

engine_state: Engine_State;

#scope_export

engine_init :: () -> bool {
    log_install();

    if engine_state.platform_initialized {
        return true;
    }

    if !platform_init() {
        return false;
    }
    engine_state.platform_initialized = true;

    asset_manager_init();
    engine_state.asset_manager_initialized = true;

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
    engine_state.renderer_initialized = true;

    renderer_set_viewport_size(
        window.framebuffer_width,
        window.framebuffer_height
    );

    text_init();
    engine_state.text_initialized = true;

    engine_state.last_time = time_get();
    engine_state.delta_time = 0;

    log("Initialized window");

    return window;
}

engine_get_delta_time :: () -> float64 {
    return engine_state.delta_time;
}

engine_update :: () -> float64 {
    // delta time
    current_time := time_get();
    delta_time := current_time - engine_state.last_time;
    engine_state.last_time = current_time;
    engine_state.delta_time = delta_time;

    // engine work
    asset_manager_update();
    input_poll();
    window_poll_events();

    return delta_time;
}

engine_shutdown :: () {
    if engine_state.asset_manager_initialized {
        asset_manager_shutdown();
        engine_state.asset_manager_initialized = false;
    }

    if engine_state.text_initialized {
        text_shutdown();
        engine_state.text_initialized = false;
    }

    if engine_state.renderer_initialized {
        renderer_shutdown();
        engine_state.renderer_initialized = false;
    }

    if engine_state.window {
        window_destroy(engine_state.window);
        engine_state.window = null;
    }

    if engine_state.platform_initialized {
        platform_shutdown();
        engine_state.platform_initialized = false;
    }
}
