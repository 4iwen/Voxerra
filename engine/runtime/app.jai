#scope_file

#import "Basic";

#scope_module

Build_Mode :: enum u8 {
    EDITOR;
    GAME;
    EXPORT;
}

Runtime_State :: struct {
    game_module: Game_Module;
    fixed_delta_time: float64 = 1.0 / 60.0;
    fixed_accumulator: float64;
    render_queue: *Render_Queue;
    skybox: *Skybox;
    scene_framebuffer: *Framebuffer;
    missing_camera_warning_emitted: bool;
}

runtime_state: Runtime_State;

#scope_export

app_init :: (game_module: Game_Module) -> bool {
    runtime_state = .{};
    runtime_state.game_module = game_module;

    if !engine_init() {
        return false;
    }

    window := window_init(1512, 982, "Engine");
    if !window {
        engine_shutdown();
        return false;
    }

    window_set_vsync(window, true);

    runtime_state.render_queue = render_queue_create();
    runtime_state.skybox = skybox_init();
    postfx_init();

    runtime_state.scene_framebuffer = framebuffer_create(
        window.framebuffer_width,
        window.framebuffer_height
    );

    #if BUILD_MODE == .EDITOR {
        editor_picking_init();
        ui_init(window);
        engine_state.main_framebuffer = framebuffer_create(
            window.framebuffer_width,
            window.framebuffer_height
        );
    }

    runtime_state.game_module.game_init();

    return true;
}

app_shutdown :: () {
    runtime_state.game_module.game_shutdown();
    if engine_state.current_scene {
        scene_destroy(engine_state.current_scene);
        engine_state.current_scene = null;
    }
    if runtime_state.scene_framebuffer {
        framebuffer_destroy(runtime_state.scene_framebuffer);
    }
    if engine_state.main_framebuffer {
        framebuffer_destroy(engine_state.main_framebuffer);
    }
    postfx_shutdown();
    skybox_shutdown(runtime_state.skybox);
    render_queue_destroy(runtime_state.render_queue);

    #if BUILD_MODE == .EDITOR {
        editor_picking_shutdown();
        ui_shutdown();
    }

    engine_shutdown();
}

app_run_frame :: () {
    delta_time := engine_begin_frame();
    #if MEMORY_DEBUGGER_ENABLED then memory_visualizer_per_frame_update();

    #if BUILD_MODE == .EDITOR {
        ui_begin_frame();
    }

    app_update_game(delta_time);

    app_render_scene();

    #if BUILD_MODE == .EDITOR {
        ui_draw();
        ui_end_frame();
    }

    engine_end_frame();
}

app_should_close :: () -> bool {
    return window_should_close(engine_state.window);
}

app_update_game :: (delta_time: float64) {
    delta := min(delta_time, 0.25);
    runtime_state.fixed_accumulator += delta;

    fixed_updates_remaining := 8;
    while runtime_state.fixed_accumulator >= runtime_state.fixed_delta_time &&
          fixed_updates_remaining > 0 {
        runtime_state.game_module.game_fixed_update(runtime_state.fixed_delta_time);
        runtime_state.fixed_accumulator -= runtime_state.fixed_delta_time;
        fixed_updates_remaining -= 1;
    }

    app_ensure_scene_camera(engine_state.current_scene);
    runtime_state.game_module.game_update();
}

app_render_scene :: () {
    scene := engine_state.current_scene;
    output_framebuffer: *Framebuffer;
    output_width := engine_state.window.framebuffer_width;
    output_height := engine_state.window.framebuffer_height;

    #if BUILD_MODE == .EDITOR {
        if engine_state.main_framebuffer {
            output_framebuffer = engine_state.main_framebuffer;
            output_width = output_framebuffer.pixel_width;
            output_height = output_framebuffer.pixel_height;
        }
    }

    if !scene {
        if output_framebuffer {
            framebuffer_bind(output_framebuffer);
            renderer_begin_frame(.{0.08, 0.08, 0.09, 1.0});
            framebuffer_unbind();
        } else {
            renderer_set_viewport_size(output_width, output_height);
            renderer_begin_frame(.{0.08, 0.08, 0.09, 1.0});
        }
        return;
    }

    camera := app_get_render_camera();
    if !camera {
        return;
    }

    render_framebuffer := output_framebuffer;
    if postfx_get_enabled() {
        render_framebuffer = runtime_state.scene_framebuffer;
        framebuffer_resize(render_framebuffer, output_width, output_height);
        postfx_resize(output_width, output_height);
    }

    if render_framebuffer {
        framebuffer_bind(render_framebuffer);
    } else {
        renderer_set_viewport_size(output_width, output_height);
    }

    renderer_begin_frame(.{0.08, 0.08, 0.09, 1.0});

    scene_update_transforms(scene);

    #if BUILD_MODE == .EDITOR {
        editor_picking_render(scene, camera, output_width, output_height);
        if render_framebuffer {
            framebuffer_bind(render_framebuffer);
        } else {
            renderer_set_viewport_size(output_width, output_height);
        }
    }

    render_queue_submit(runtime_state.render_queue, scene);
    render_queue_flush(runtime_state.render_queue, camera);

    if runtime_state.skybox {
        aspect := 1.0;
        if output_height > 0 {
            aspect = cast(float) output_width / cast(float) output_height;
        }

        skybox_draw(
            runtime_state.skybox,
            camera_get_view_matrix(camera.*),
            camera_get_projection_matrix(camera.*, aspect)
        );
    }

    if postfx_get_enabled() {
        postfx_apply(
            runtime_state.scene_framebuffer,
            output_framebuffer,
            camera,
            output_width,
            output_height
        );
    }

    #if BUILD_MODE == .EDITOR {
        if output_framebuffer {
            framebuffer_unbind();
        }
    } else {
        if output_framebuffer {
            framebuffer_unbind();
        }
    }
}

app_get_render_camera :: () -> *Camera {
    scene := engine_state.current_scene;
    if scene {
        app_ensure_scene_camera(scene);
        if scene.camera then return scene.camera;
    }

    if !runtime_state.missing_camera_warning_emitted {
        log_warning("No active scene camera found");
        runtime_state.missing_camera_warning_emitted = true;
    }

    return null;
}

app_ensure_scene_camera :: (scene: *Scene) {
    if !scene || scene.camera then return;

    component := scene_find_first_component(scene, Camera_Component);
    if component {
        scene_set_active_camera(scene, component);
    }
}
