#import "Basic";
#import "Math";

#load "camera_controller.jai";
#load "suzanne_mesh_data.jai";
#load "default_scene.jai";

Game_State :: struct {
    scene: *Scene;
    time: float64;
    camera_controller: Game_Camera_Controller;
}

game_state: Game_State;

#scope_export

game_module_get_api :: () -> Game_Module {
    module: Game_Module;
    module.game_init =         game_init;
    module.game_fixed_update = game_fixed_update;
    module.game_update =       game_update;
    module.game_shutdown =     game_shutdown;
    return module;
}

game_init :: () {
    log("game_init");

    camera_ids := game_camera_controller_get_ids(*game_state.camera_controller);
    game_state = .{};
    game_camera_controller_set_ids(*game_state.camera_controller, camera_ids);

    scene := engine_state.current_scene;
    if !scene {
        log_error("game_init called without an active scene");
        return;
    } else {
        game_rebind_default_scene_runtime(scene);
        game_camera_controller_rebind(*game_state.camera_controller, scene);
    }

    game_state.scene = scene;
    game_state.time = 0.0;
}

game_fixed_update :: (fixed_delta_time: float64) {
    game_sync_current_scene();

    game_state.time += fixed_delta_time;

    scene := game_state.scene;
    if scene {
        game_update_scene_runtime(game_state.time, scene.camera);
    }
}

game_update :: () {
    game_sync_current_scene();

    scene := game_state.scene;
    if !scene then return;

    viewport_input_allowed := true;
    #if BUILD_MODE == .EDITOR {
        viewport_input_allowed = input_viewport_mouse_allowed();
    }

    game_camera_controller_update(
        *game_state.camera_controller,
        scene,
        engine_get_window(),
        engine_get_delta_time(),
        viewport_input_allowed
    );
}

game_shutdown :: () {
    log("game_shutdown");

    window := engine_get_window();
    if window {
        window_set_cursor_mode(window, .NORMAL);
    }

    camera_ids := game_camera_controller_get_ids(*game_state.camera_controller);
    game_state = .{};
    game_camera_controller_set_ids(*game_state.camera_controller, camera_ids);
}

#scope_file

game_sync_current_scene :: () {
    if game_state.scene != engine_state.current_scene {
        game_state.scene = engine_state.current_scene;
        game_state.time = 0.0;
        game_rebind_default_scene_runtime(game_state.scene);
        game_camera_controller_rebind(*game_state.camera_controller, game_state.scene);
    }
}
