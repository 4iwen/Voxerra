// File:        camera_controller.jai
// Author:      Lukáš Bien
// Description: Manages gameplay camera modes and free camera input behavior.

#scope_file

#import "Basic";

#scope_export

Game_Camera_Mode :: enum u8 {
    FREE;
    STATIC_1;
    STATIC_2;
}

FREE_CAMERA_SCENE_ID :: "free_camera";
STATIC_CAMERA_1_SCENE_ID :: "static_camera_1";
STATIC_CAMERA_2_SCENE_ID :: "static_camera_2";

Game_Free_Camera_Controller :: struct {
    active: bool = false;
    capture_blocked_until_click: bool = false;
    skip_next_mouse_delta: bool = false;
    movement_speed: float = 3.0;
    mouse_sensitivity: float = 0.2;
}

Game_Camera_Controller :: struct {
    active_mode: Game_Camera_Mode = .FREE;
    previous_mode: Game_Camera_Mode = .FREE;

    free_node: *Node;
    free_node_runtime_id: u64;
    static_1_node_runtime_id: u64;
    static_2_node_runtime_id: u64;
    free_camera: *Camera_Component;
    static_1_camera: *Camera_Component;
    static_2_camera: *Camera_Component;

    free_controller: Game_Free_Camera_Controller;
}

Game_Camera_Controller_Ids :: struct {
    free_node_runtime_id: u64;
    static_1_node_runtime_id: u64;
    static_2_node_runtime_id: u64;
}

game_camera_controller_init :: (
    controller: *Game_Camera_Controller,
    scene: *Scene
) {
    assert(controller != null, "game_camera_controller_init: controller is null");
    assert(scene != null, "game_camera_controller_init: scene is null");

    controller.* = .{};
    controller.active_mode = .FREE;
    controller.previous_mode = .FREE;

    controller.free_camera = game_create_camera_node(
        scene.root,
        "Free Camera",
        .{0.0, 5.0, 16.0},
        -90.0,
        -12.0
    );
    controller.free_node = controller.free_camera.node;
    controller.free_node_runtime_id = controller.free_node.runtime_id;
    controller.free_controller = .{};

    controller.static_1_camera = game_create_camera_node(
        scene.root,
        "Static View 1",
        .{0.0, 8.2, 20.5},
        -90.0,
        -17.5
    );
    controller.static_2_camera = game_create_camera_node(
        scene.root,
        "Static View 2",
        .{16.0, 11.5, 12.0},
        -149.0,
        -24.0
    );
    controller.static_1_node_runtime_id = controller.static_1_camera.node.runtime_id;
    controller.static_2_node_runtime_id = controller.static_2_camera.node.runtime_id;

    scene_set_active_camera(scene, controller.free_camera);
}

game_camera_controller_get_ids :: (
    controller: *Game_Camera_Controller
) -> Game_Camera_Controller_Ids {
    if !controller then return .{};

    return .{
        free_node_runtime_id = controller.free_node_runtime_id,
        static_1_node_runtime_id = controller.static_1_node_runtime_id,
        static_2_node_runtime_id = controller.static_2_node_runtime_id
    };
}

game_camera_controller_set_ids :: (
    controller: *Game_Camera_Controller,
    ids: Game_Camera_Controller_Ids
) {
    if !controller then return;

    controller.free_node_runtime_id = ids.free_node_runtime_id;
    controller.static_1_node_runtime_id = ids.static_1_node_runtime_id;
    controller.static_2_node_runtime_id = ids.static_2_node_runtime_id;
}

game_camera_controller_update :: (
    controller: *Game_Camera_Controller,
    scene: *Scene,
    window: *Window,
    delta_time: float64,
    viewport_hovered: bool
) {
    if !controller || !scene || !window then return;

    game_camera_controller_process_shortcuts(controller, scene, window);

    if controller.previous_mode != controller.active_mode {
        game_camera_controller_apply_mode_transition(controller, scene, window);
    }

    if controller.active_mode == .FREE && controller.free_camera {
        game_free_camera_controller_update(
            *controller.free_controller,
            *controller.free_camera.camera,
            window,
            delta_time,
            viewport_hovered
        );
        game_sync_camera_node_from_component(controller.free_node, controller.free_camera);
    }

    active_camera := game_camera_controller_get_active_camera(controller);
    if active_camera {
        scene_set_active_camera(scene, active_camera);
    }
}

game_camera_controller_set_mode :: (
    controller: *Game_Camera_Controller,
    scene: *Scene,
    mode: Game_Camera_Mode,
    window: *Window = null
) {
    if !controller || !scene then return;

    controller.active_mode = mode;
    if window {
        game_camera_controller_apply_mode_transition(controller, scene, window);
    }
}

game_camera_controller_get_mode :: (controller: *Game_Camera_Controller) -> Game_Camera_Mode {
    if !controller then return .FREE;
    return controller.active_mode;
}

// restore camera node bindings after scene reloads while keeping the user's
// current mode and free-camera state intact.
game_camera_controller_rebind :: (
    controller: *Game_Camera_Controller,
    scene: *Scene
) {
    if !controller || !scene then return;

    active_mode := controller.active_mode;
    previous_mode := controller.previous_mode;
    free_controller := controller.free_controller;

    free_node := node_find_by_runtime_or_scene_id(
        scene.root,
        controller.free_node_runtime_id,
        FREE_CAMERA_SCENE_ID
    );
    static_1_node := node_find_by_runtime_or_scene_id(
        scene.root,
        controller.static_1_node_runtime_id,
        STATIC_CAMERA_1_SCENE_ID
    );
    static_2_node := node_find_by_runtime_or_scene_id(
        scene.root,
        controller.static_2_node_runtime_id,
        STATIC_CAMERA_2_SCENE_ID
    );

    controller.free_node = free_node;
    controller.free_camera = node_get_component(free_node, Camera_Component);
    controller.static_1_camera = node_get_component(static_1_node, Camera_Component);
    controller.static_2_camera = node_get_component(static_2_node, Camera_Component);
    if free_node     then controller.free_node_runtime_id = free_node.runtime_id;
    if static_1_node then controller.static_1_node_runtime_id = static_1_node.runtime_id;
    if static_2_node then controller.static_2_node_runtime_id = static_2_node.runtime_id;
    controller.active_mode = active_mode;
    controller.previous_mode = previous_mode;
    controller.free_controller = free_controller;

    active_camera := game_camera_controller_get_active_camera(controller);
    if active_camera {
        scene_set_active_camera(scene, active_camera);
    }
}

#scope_file

game_create_camera_node :: (
    parent: *Node,
    name: string,
    position: Vector3,
    yaw: float32,
    pitch: float32
) -> *Camera_Component {
    node := node_add_node(parent, name);
    node.local.position = position;

    camera_component := node_add_component(node, Camera_Component);
    camera_component.camera = camera_create(position);
    camera_component.camera.yaw = yaw;
    camera_component.camera.pitch = pitch;
    camera_update_vectors(*camera_component.camera);

    return camera_component;
}

game_camera_controller_process_shortcuts :: (
    controller: *Game_Camera_Controller,
    scene: *Scene,
    window: *Window
) {
    if input_key_pressed(.NUM_1) {
        game_camera_controller_set_mode(controller, scene, .FREE, window);
    }
    if input_key_pressed(.NUM_2) {
        game_camera_controller_set_mode(controller, scene, .STATIC_1, window);
    }
    if input_key_pressed(.NUM_3) {
        game_camera_controller_set_mode(controller, scene, .STATIC_2, window);
    }
}

// when switching back to free mode, seed it from the previous active camera
// so the transition feels continuous instead of snapping to an old state.
game_camera_controller_apply_mode_transition :: (
    controller: *Game_Camera_Controller,
    scene: *Scene,
    window: *Window
) {
    if controller.active_mode == .FREE {
        source_camera := game_camera_controller_get_camera_for_mode(
            controller,
            controller.previous_mode
        );
        if !source_camera {
            source_camera = game_camera_controller_get_camera_for_mode(
                controller,
                controller.active_mode
            );
        }

        if source_camera && controller.free_camera {
            controller.free_camera.camera = source_camera.camera;
            controller.free_controller.active = false;
            controller.free_controller.capture_blocked_until_click = false;
            controller.free_controller.skip_next_mouse_delta = true;
            game_sync_camera_node_from_component(controller.free_node, controller.free_camera);
        }
    } else {
        controller.free_controller.active = false;
        controller.free_controller.skip_next_mouse_delta = false;
        controller.free_controller.capture_blocked_until_click = false;
    }

    if window {
        window_set_cursor_mode(window, .NORMAL);
    }

    controller.previous_mode = controller.active_mode;
}

game_camera_controller_get_active_camera :: (
    controller: *Game_Camera_Controller
) -> *Camera_Component {
    return game_camera_controller_get_camera_for_mode(controller, controller.active_mode);
}

game_camera_controller_get_camera_for_mode :: (
    controller: *Game_Camera_Controller,
    mode: Game_Camera_Mode
) -> *Camera_Component {
    if !controller then return null;

    if mode == .FREE then return controller.free_camera;
    if mode == .STATIC_1 then return controller.static_1_camera;
    if mode == .STATIC_2 then return controller.static_2_camera;

    return null;
}

game_sync_camera_node_from_component :: (
    node: *Node,
    camera_component: *Camera_Component
) {
    if node && camera_component {
        node.local.position = camera_component.camera.position;
    }
}

// gate cursor capture on viewport focus and click state so editor mode and
// free camera movement do not fight each other.
game_free_camera_controller_update :: (
    controller: *Game_Free_Camera_Controller,
    camera: *Camera,
    window: *Window,
    delta_time: float64,
    viewport_hovered: bool = true
) {
    assert(controller != null, "game_free_camera_controller_update: controller is null");
    assert(camera != null, "game_free_camera_controller_update: camera is null");
    assert(window != null, "game_free_camera_controller_update: window is null");

    camera_update_vectors(camera);

    if controller.active && (!window_is_focused(window) || input_key_pressed(.ESCAPE)) {
        window_set_cursor_mode(window, .NORMAL);
        controller.active = false;
        controller.capture_blocked_until_click = true;
        controller.skip_next_mouse_delta = false;
    }

    if controller.capture_blocked_until_click {
        if viewport_hovered && input_mouse_pressed(.LEFT) {
            controller.capture_blocked_until_click = false;
        } else {
            return;
        }
    }

    if !controller.active && viewport_hovered && window_is_focused(window) {
        window_set_cursor_mode(window, .DISABLED);
        controller.active = true;
        controller.skip_next_mouse_delta = true;
    }

    if controller.active {
        game_free_camera_process_keyboard(controller, camera, delta_time);
        game_free_camera_process_mouse(controller, camera);
        game_clamp_camera_position(*camera.position);
        camera_update_vectors(camera);
    }
}

game_free_camera_process_keyboard :: (
    controller: *Game_Free_Camera_Controller,
    camera: *Camera,
    delta_time: float64
) {
    speed := controller.movement_speed;
    if input_key_down(.LEFT_SHIFT) then speed *= 2.5;

    velocity := speed * delta_time;

    if input_key_down(.W) then camera.position += camera.front * velocity;
    if input_key_down(.S) then camera.position -= camera.front * velocity;
    if input_key_down(.A) then camera.position -= camera.right * velocity;
    if input_key_down(.D) then camera.position += camera.right * velocity;
    if input_key_down(.E) then camera.position += camera.world_up * velocity;
    if input_key_down(.Q) then camera.position -= camera.world_up * velocity;
}

game_free_camera_process_mouse :: (
    controller: *Game_Free_Camera_Controller,
    camera: *Camera
) {
    dx, dy := input_mouse_delta();

    if controller.skip_next_mouse_delta {
        controller.skip_next_mouse_delta = false;
        return;
    }

    camera.yaw += cast(float32) dx * controller.mouse_sensitivity;
    camera.pitch -= cast(float32) dy * controller.mouse_sensitivity;

    camera.pitch = clamp(camera.pitch, -89.9, 89.9);

    camera_update_vectors(camera);
}
