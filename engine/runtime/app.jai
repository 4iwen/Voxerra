// File:        app.jai
// Author:      Lukáš Bien
// Description: Coordinates runtime startup, editor play mode, scene
//              rendering, and per-frame app flow.

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
    editor_play_mode: Editor_Play_Mode;
    editor_edit_scene: *Scene;
    editor_play_scene: *Scene;
    fallback_camera: Camera;
}

runtime_state: Runtime_State;

#scope_export

Editor_Play_Mode :: enum u8 {
    STOPPED;
    PLAYING;
}

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
    fog_resolve_init();
    app_load_engine_default_assets();
    runtime_state.fallback_camera = camera_create(.{0.0, 3.0, 10.0});

    runtime_state.scene_framebuffer = framebuffer_create(
        window.framebuffer_width,
        window.framebuffer_height
    );

    #if BUILD_MODE == .EDITOR {
        editor_picking_init();
        editor_gizmo_init();
        engine_state.main_framebuffer = framebuffer_create(
            window.framebuffer_width,
            window.framebuffer_height
        );
    }

    #if BUILD_MODE == .EDITOR {
        descriptor, project_ok := project_load_descriptor();
        if !project_ok {
            return false;
        }
        editor_context_init(descriptor);
        ui_init(window);
        editor_open_scene_tab(descriptor.editor_startup_scene);
        project_descriptor_destroy(*descriptor);
    } else {
        app_load_project_startup_scene();
        runtime_state.game_module.game_init();
    }

    return true;
}

app_shutdown :: () {
    #if BUILD_MODE == .EDITOR {
        if editor_is_playing() {
            editor_stop();
        }
        editor_context_shutdown();
    } else {
        runtime_state.game_module.game_shutdown();
        if engine_state.current_scene {
            scene_destroy(engine_state.current_scene);
            engine_state.current_scene = null;
        }
    }
    if runtime_state.scene_framebuffer {
        framebuffer_destroy(runtime_state.scene_framebuffer);
    }
    if engine_state.main_framebuffer {
        framebuffer_destroy(engine_state.main_framebuffer);
    }
    fog_resolve_shutdown();
    skybox_shutdown(runtime_state.skybox);
    render_queue_destroy(runtime_state.render_queue);

    #if BUILD_MODE == .EDITOR {
        editor_picking_shutdown();
        editor_gizmo_shutdown();
        ui_shutdown();
    }

    engine_shutdown();
}

app_load_engine_default_assets :: () {
    shader := asset_manager_load_shader(
        "engine/assets/shaders/blinn_phong.vert",
        "engine/assets/shaders/blinn_phong.frag",
        true
    );
    if shader {
        asset_manager_set_default_shader(shader);
    } else {
        log_error("Failed to load engine default material shader");
    }
}

app_load_project_startup_scene :: () -> bool {
    descriptor, project_ok := project_load_descriptor();
    if !project_ok {
        return false;
    }
    defer project_descriptor_destroy(*descriptor);

    scene, scene_ok := scene_load_toml(descriptor.startup_scene);
    if !scene_ok {
        log_error("Failed to load startup scene: %", descriptor.startup_scene);
        return false;
    }

    if engine_state.current_scene {
        scene_destroy(engine_state.current_scene);
    }
    engine_state.current_scene = scene;
    app_ensure_scene_camera(scene);

    return true;
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
    app_ensure_scene_camera(engine_state.current_scene);

    should_run_game := true;
    #if BUILD_MODE == .EDITOR {
        editor_handle_global_shortcuts();
        should_run_game = editor_is_playing();
    }

    if should_run_game {
        #if BUILD_MODE == .EDITOR {
            editor_camera_cancel_fly();
        }

        delta := min(delta_time, 0.25);
        runtime_state.fixed_accumulator += delta;

        fixed_updates_remaining := 8;
        while runtime_state.fixed_accumulator >= runtime_state.fixed_delta_time &&
              fixed_updates_remaining > 0 {
            runtime_state.game_module.game_fixed_update(runtime_state.fixed_delta_time);
            runtime_state.fixed_accumulator -= runtime_state.fixed_delta_time;
            fixed_updates_remaining -= 1;
        }

        runtime_state.game_module.game_update();
    } else {
        runtime_state.fixed_accumulator = 0.0;
        #if BUILD_MODE == .EDITOR {
            editor_camera_update(engine_get_delta_time());
        }
    }

    #if BUILD_MODE == .EDITOR {
        editor_handle_viewport_selection();
    }
}

editor_is_playing :: () -> bool {
    #if BUILD_MODE == .EDITOR {
        return runtime_state.editor_play_mode == .PLAYING;
    } else {
        return true;
    }
}

editor_get_play_mode :: () -> Editor_Play_Mode {
    #if BUILD_MODE == .EDITOR {
        return runtime_state.editor_play_mode;
    } else {
        return .PLAYING;
    }
}

editor_play :: () {
    #if BUILD_MODE == .EDITOR {
        if runtime_state.editor_play_mode == .PLAYING then return;
        if !engine_state.current_scene then return;

        runtime_state.editor_edit_scene = engine_state.current_scene;
        runtime_state.editor_play_scene = scene_clone(runtime_state.editor_edit_scene);
        engine_state.current_scene = runtime_state.editor_play_scene;
        app_ensure_scene_camera(engine_state.current_scene);

        runtime_state.fixed_accumulator = 0.0;
        runtime_state.editor_play_mode = .PLAYING;
        runtime_state.game_module.game_init();
        selected_node = engine_state.current_scene.root;
    }
}

editor_stop :: () {
    #if BUILD_MODE == .EDITOR {
        if runtime_state.editor_play_mode == .STOPPED then return;

        play_scene := runtime_state.editor_play_scene;
        edit_scene := runtime_state.editor_edit_scene;

        runtime_state.game_module.game_shutdown();
        runtime_state.editor_play_mode = .STOPPED;
        runtime_state.fixed_accumulator = 0.0;

        if edit_scene {
            engine_state.current_scene = edit_scene;
            app_ensure_scene_camera(edit_scene);
            editor_select_node(edit_scene.root);
        }

        runtime_state.editor_edit_scene = null;
        runtime_state.editor_play_scene = null;

        if play_scene {
            scene_destroy(play_scene);
        }
    }
}

editor_save_scene :: () -> bool {
    #if BUILD_MODE == .EDITOR {
        if editor_is_playing() {
            log_warning("Cannot save scene while play mode is running");
            return false;
        }

        scene := engine_state.current_scene;
        if !scene {
            log_warning("Cannot save scene: no active scene");
            return false;
        }

        return editor_save_active_scene();
    } else {
        return false;
    }
}

editor_create_scene :: (path: string) -> bool {
    #if BUILD_MODE == .EDITOR {
        if editor_is_playing() {
            log_warning("Cannot create scene while play mode is running");
            return false;
        }
        if !path {
            log_warning("Cannot create scene: empty path");
            return false;
        }

        return editor_create_scene_tab(path);
    } else {
        return false;
    }
}

editor_open_scene :: (path: string) -> bool {
    #if BUILD_MODE == .EDITOR {
        if editor_is_playing() {
            log_warning("Cannot open scene while play mode is running");
            return false;
        }
        if !path {
            log_warning("Cannot open scene: empty path");
            return false;
        }

        return editor_open_scene_tab(path);
    } else {
        return false;
    }
}

// route editor rendering through the viewport framebuffer first, then
// optionally through the fog resolve chain.
app_render_scene :: () {
    scene := engine_state.current_scene;
    output_framebuffer: *Framebuffer;
    output_width := engine_state.window.framebuffer_width;
    output_height := engine_state.window.framebuffer_height;
    #if BUILD_MODE == .EDITOR {
        if engine_state.main_framebuffer {
            output_framebuffer = engine_state.main_framebuffer;
            framebuffer_width := output_framebuffer.pixel_width;
            framebuffer_height := output_framebuffer.pixel_height;
            if ui_state.viewport_pixel_width > 0 && ui_state.viewport_pixel_height > 0 {
                framebuffer_width = ui_state.viewport_pixel_width;
                framebuffer_height = ui_state.viewport_pixel_height;
            }

            framebuffer_resize(output_framebuffer, framebuffer_width, framebuffer_height);
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

    render_environment := scene.environment;
    include_scene_lights := true;
    previous_view_mode := renderer_get_view_mode();
    previous_wireframe := renderer_get_wireframe();
    #if BUILD_MODE == .EDITOR {
        if !editor_is_playing() {
            render_environment = editor_render_mode_apply_environment(scene.environment);
            include_scene_lights = editor_render_mode_uses_scene_lights();
            renderer_set_view_mode(editor_render_mode_to_renderer_view_mode());
            renderer_set_wireframe(editor_render_mode_is_wireframe());
        }
    }
    scene_apply_environment_settings(scene, render_environment);
    fog_resolve_enabled := fog_resolve_get_enabled();

    render_framebuffer := output_framebuffer;
    if fog_resolve_enabled {
        render_framebuffer = runtime_state.scene_framebuffer;
        framebuffer_resize(render_framebuffer, output_width, output_height);
    }

    if render_framebuffer {
        framebuffer_bind(render_framebuffer);
    } else {
        renderer_set_viewport_size(output_width, output_height);
    }

    renderer_begin_frame(render_environment.clear_color);

    scene_update_transforms(scene);
    scene_update_cameras(scene);
    sprite_delta_time := engine_get_delta_time();
    #if BUILD_MODE == .EDITOR {
        if !editor_is_playing() {
            sprite_delta_time = 0.0;
        }
    }
    sprite_system_update(scene, camera, delta_time = sprite_delta_time);

    #if BUILD_MODE == .EDITOR {
        editor_picking_render(scene, camera, output_width, output_height);
        if render_framebuffer {
            framebuffer_bind(render_framebuffer);
        } else {
            renderer_set_viewport_size(output_width, output_height);
        }
    }

    render_queue_submit(runtime_state.render_queue, scene, include_scene_lights);
    render_aspect := 1.0;
    if output_height > 0 {
        render_aspect = cast(float) output_width / cast(float) output_height;
    }

    render_queue_flush_opaque(
        runtime_state.render_queue,
        camera,
        render_aspect,
        shader_fog_enabled = !fog_resolve_enabled
    );

    if runtime_state.skybox && render_environment.skybox_enabled {
        skybox_draw(
            runtime_state.skybox,
            camera_get_view_matrix(camera.*),
            camera_get_projection_matrix(camera.*, render_aspect),
            shader_fog_enabled = !fog_resolve_enabled
        );
    }

    if fog_resolve_enabled {
        // fog resolve composites fullscreen fog after opaque and skybox
        // rendering, then transparent items render on top of that result.
        fog_resolve_apply(
            runtime_state.scene_framebuffer,
            output_framebuffer,
            camera,
            output_width,
            output_height
        );

        framebuffer_blit_depth(
            runtime_state.scene_framebuffer,
            output_framebuffer,
            output_width,
            output_height
        );

        if output_framebuffer {
            framebuffer_bind(output_framebuffer);
        } else {
            framebuffer_unbind();
            renderer_set_viewport_size(output_width, output_height);
        }
    }

    render_queue_flush_transparent(
        runtime_state.render_queue,
        camera,
        render_aspect,
        shader_fog_enabled = true
    );

    render_queue_clear(runtime_state.render_queue);

    #if BUILD_MODE == .EDITOR {
        if !editor_is_playing() {
            renderer_set_wireframe(previous_wireframe);
            renderer_set_view_mode(previous_view_mode);
        }

        if output_framebuffer {
            framebuffer_unbind();
        }
    } else {
        if output_framebuffer {
            framebuffer_unbind();
        }
    }
}

// choose the editor camera while editing, otherwise fall back to the active
// scene camera or the runtime fallback camera.
app_get_render_camera :: () -> *Camera {
    scene := engine_state.current_scene;
    #if BUILD_MODE == .EDITOR {
        if !editor_is_playing() {
            camera := editor_get_active_camera();
            if camera then return camera;
        }
    }

    if scene {
        app_ensure_scene_camera(scene);
        if scene.camera then return scene.camera;
    }

    if !runtime_state.missing_camera_warning_emitted {
        log_warning("No active scene camera found");
        runtime_state.missing_camera_warning_emitted = true;
    }

    return *runtime_state.fallback_camera;
}

app_ensure_scene_camera :: (scene: *Scene) {
    if !scene || scene.camera then return;

    component := scene_find_first_component(scene, Camera_Component);
    if component {
        scene_set_active_camera(scene, component);
    }
}
