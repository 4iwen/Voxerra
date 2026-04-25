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
    editor_scene: *Scene;
    play_scene: *Scene;
    is_playing: bool;
    fixed_delta_time: float64 = 1.0 / 60.0;
    fixed_accumulator: float64;
    editor_camera: Camera_Controller;
    render_queue: *Render_Queue;
    skybox: *Skybox;
    missing_camera_warning_emitted: bool;
}

runtime_state: Runtime_State;

#scope_export

app_init :: (game_module: Game_Module) -> bool {
    runtime_state = .{};
    runtime_state.game_module = game_module;
    runtime_state.editor_camera = camera_controller_create(.{0.0, 1.5, 5.0});

    if !engine_init() {
        return false;
    }

    window := window_init(1512, 982, "Engine");
    if !window {
        engine_shutdown();
        return false;
    }

    window_set_vsync(true);

    runtime_state.render_queue = render_queue_create();
    runtime_state.skybox = skybox_init();
    app_load_default_assets();

    #if BUILD_MODE == .EDITOR {
        ui_init(window);
        engine_state.main_framebuffer = framebuffer_create(
            window.framebuffer_width,
            window.framebuffer_height
        );
    }

    scene := scene_create("Default Scene");
    app_populate_default_scene(scene);

    runtime_state.editor_scene = scene;
    engine_state.current_scene = scene;

    #if BUILD_MODE == .EDITOR {
        selected_node = scene.root;
    }

    return true;
}

app_shutdown :: () {
    if runtime_state.editor_scene {
        scene_destroy(runtime_state.editor_scene);
    }
    if engine_state.main_framebuffer {
        framebuffer_destroy(engine_state.main_framebuffer);
    }
    skybox_shutdown(runtime_state.skybox);
    render_queue_destroy(runtime_state.render_queue);

    #if BUILD_MODE == .EDITOR {
        ui_shutdown();
    }

    engine_shutdown();
}

app_run_frame :: () {
    delta_time := engine_begin_frame();
    #if MEMORY_DEBUGGER_ENABLED then memory_visualizer_per_frame_update();

    #if BUILD_MODE == .EDITOR {
        ui_begin_frame();
        ui_draw();
    }

    if runtime_state.is_playing {
        app_update_game(delta_time);
    } else #if BUILD_MODE == .EDITOR {
        viewport_hovered := true;
        viewport_hovered = ui_state.viewport_hovered;
        camera_controller_update(
            *runtime_state.editor_camera,
            engine_state.window,
            delta_time,
            viewport_hovered
        );
    }

    app_render_scene();

    #if BUILD_MODE == .EDITOR {
        ui_end_frame();
    }

    engine_end_frame();
}

app_should_close :: () -> bool {
    return window_should_close(engine_state.window);
}

#scope_file

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

app_load_default_assets :: () {
    shader := asset_manager_load_shader(
        "engine/assets/shaders/blinn_phong.vert",
        "engine/assets/shaders/blinn_phong.frag",
        true
    );
    if shader {
        asset_manager_set_default_shader(shader);
    } else {
        log_error("Failed to load default scene shader");
    }
}

app_populate_default_scene :: (scene: *Scene) {
    assert(scene != null, "app_populate_default_scene: scene is null");

    camera_node := node_add_node(scene.root, "Camera");
    camera_node.local.position = .{0.0, 1.5, 5.0};
    camera_component := node_add_component(camera_node, Camera_Component);
    camera_component.camera = camera_create(camera_node.local.position);
    scene_set_active_camera(scene, camera_component);

    model := asset_manager_load_model("game/assets/models/utah_teapot.obj");
    if model {
        model_node := node_add_node(scene.root, "Teapot");
        model_node.local.position = .{0.0, 0.0, -10.0};

        for model.submeshes {
            sub_node := node_add_node(model_node, "teapot_mesh");
            mesh_component := node_add_component(sub_node, Static_Mesh_Component);
            mesh_component.mesh = it.mesh;
            mesh_component.material = it.material;
        }
    } else {
        log_error("Failed to load default scene model");
    }

    sun_node := node_add_node(scene.root, "Sun");
    sun_node.local.rotation = quaternion_from_euler_xyz(.{-PI / 2.0 - 0.2, 0.0, 0.0});
    sun_light := node_add_component(sun_node, Light_Component);
    sun_light.light.type = .Directional;
    sun_light.light.color = .{1.0, 0.95, 0.9};
    sun_light.light.intensity = 2.0;

    point_node := node_add_node(scene.root, "Point Light");
    point_node.local.position = .{3.0, 3.0, -7.5};
    point_light := node_add_component(point_node, Light_Component);
    point_light.light.type = .Point;
    point_light.light.color = .{1.0, 0.0, 0.0};
    point_light.light.intensity = 2.0;
    point_light.light.range = 20.0;
}

app_render_scene :: () {
    scene := engine_state.current_scene;
    if !scene {
        #if BUILD_MODE == .EDITOR {
            if engine_state.main_framebuffer {
                framebuffer_bind(engine_state.main_framebuffer);
                renderer_begin_frame(.{0.08, 0.08, 0.09, 1.0});
                framebuffer_unbind();
            } else {
                renderer_begin_frame(.{0.08, 0.08, 0.09, 1.0});
            }
        } else {
            renderer_begin_frame(.{0.08, 0.08, 0.09, 1.0});
        }
        return;
    }

    camera := app_get_render_camera();
    if !camera {
        return;
    }

    #if BUILD_MODE == .EDITOR {
        if engine_state.main_framebuffer {
            framebuffer_bind(engine_state.main_framebuffer);
        } else {
            renderer_set_viewport_size(
                engine_state.window.framebuffer_width,
                engine_state.window.framebuffer_height
            );
        }
    } else {
        renderer_set_viewport_size(
            engine_state.window.framebuffer_width,
            engine_state.window.framebuffer_height
        );
    }

    renderer_begin_frame(.{0.08, 0.08, 0.09, 1.0});

    scene_update_transforms(scene);
    render_queue_submit(runtime_state.render_queue, scene);
    render_queue_flush(runtime_state.render_queue, camera);

    if runtime_state.skybox {
        aspect := 1.0;
        if engine_state.main_framebuffer {
            aspect = engine_state.main_framebuffer.aspect;
        } else if engine_state.window.framebuffer_height > 0 {
            aspect = cast(float) engine_state.window.framebuffer_width /
                     cast(float) engine_state.window.framebuffer_height;
        }

        skybox_draw(
            runtime_state.skybox,
            camera_get_view_matrix(camera.*),
            camera_get_projection_matrix(camera.*, aspect)
        );
    }

    #if BUILD_MODE == .EDITOR {
        if engine_state.main_framebuffer {
            framebuffer_unbind();
        }
    }
}

app_get_render_camera :: () -> *Camera {
    if runtime_state.is_playing {
        scene := engine_state.current_scene;
        if scene {
            app_ensure_scene_camera(scene);
            if scene.camera {
                return scene.camera;
            }
        }

        if !runtime_state.missing_camera_warning_emitted {
            log_warning("No active scene camera found, using editor camera fallback");
            runtime_state.missing_camera_warning_emitted = true;
        }
    }

    return *runtime_state.editor_camera.camera;
}

app_ensure_scene_camera :: (scene: *Scene) {
    if !scene || scene.camera then return;

    component := scene_find_first_component(scene, Camera_Component);
    if component {
        scene_set_active_camera(scene, component);
    }
}
