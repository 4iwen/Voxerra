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

game_init :: () {
    log("game_init");

    game_state = .{};
    scene := scene_create("Default Scene");
    game_camera_controller_init(*game_state.camera_controller, scene);
    game_build_default_scene(scene);
    engine_state.current_scene = scene;
    game_state.scene = scene;

    #if BUILD_MODE == .EDITOR {
        selected_node = scene.root;
    }
}

game_fixed_update :: (fixed_delta_time: float64) {
    game_state.time += fixed_delta_time;
}

game_update :: () {
    scene := game_state.scene;
    if !scene then return;

    viewport_hovered := true;
    #if BUILD_MODE == .EDITOR {
        viewport_hovered = ui_state.viewport_hovered;
    }

    game_camera_controller_update(
        *game_state.camera_controller,
        scene,
        engine_get_window(),
        engine_get_delta_time(),
        viewport_hovered
    );
}

game_shutdown :: () {
    log("game_shutdown");
    game_state = .{};
}
