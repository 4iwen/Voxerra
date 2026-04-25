#import "Basic";
#import "Math";

Game_State :: struct {
    camera: *Camera;
    time: float64;
}

game_state: Game_State;

game_init :: () {
    log("game_init");

    game_state = .{};

    scene := engine_get_current_scene();
    if !scene {
        log_warning("game_init called without an active scene");
        return;
    }

    camera_component := scene_find_first_component(scene, Camera_Component);
    if !camera_component {
        log_warning("No camera component found in scene");
        return;
    }

    scene_set_active_camera(scene, camera_component);
    game_state.camera = *camera_component.camera;
}

game_fixed_update :: (fixed_delta_time: float64) {
    game_state.time += fixed_delta_time;
}

game_update :: () {
    if !game_state.camera then return;
    game_state.camera.fov = 45.0 + cast(float) sin(game_state.time * 1.5) * 4.0;
}

game_shutdown :: () {
    log("game_shutdown");
    game_state = .{};
}
