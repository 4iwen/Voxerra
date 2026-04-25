#scope_file

#import "Math";

#scope_export

Camera_Controller :: struct {
    camera: Camera;
    active: bool = false;
    block_reactivate_until_rmb_release: bool = false;
    skip_next_mouse_delta: bool = false;
    movement_speed: float = 3.0;
    mouse_sensitivity: float = 0.2;
}

camera_controller_create :: (position: Vector3) -> Camera_Controller {
    controller: Camera_Controller;
    controller.camera = camera_create(position);
    return controller;
}

camera_controller_update :: (
    controller: *Camera_Controller,
    window: *Window,
    delta_time: float64,
    viewport_hovered: bool = true
) {
    assert(controller != null, "camera_controller_update: controller is null");
    assert(window != null, "camera_controller_update: window is null");

    if controller.block_reactivate_until_rmb_release && !input_mouse_down(.RIGHT) {
        controller.block_reactivate_until_rmb_release = false;
    }

    // toggle on right click
    if input_mouse_pressed(.RIGHT) &&
       viewport_hovered &&
       !controller.block_reactivate_until_rmb_release {
        window_set_cursor_mode(window, .DISABLED);
        controller.active = true;
        controller.skip_next_mouse_delta = true;
    }
    if input_key_pressed(.ESCAPE) {
        window_set_cursor_mode(window, .NORMAL);
        controller.active = false;
        controller.block_reactivate_until_rmb_release = true;
        controller.skip_next_mouse_delta = false;
    }

    if controller.active {
        process_keyboard(controller, delta_time);
        process_mouse(controller);
    }
}

#scope_file

process_keyboard :: (controller: *Camera_Controller, delta_time: float64) {
    speed := controller.movement_speed;
    if input_key_down(.LEFT_SHIFT) then speed *= 2.5;

    velocity := speed * delta_time;

    if input_key_down(.W) then controller.camera.position += controller.camera.front * velocity;
    if input_key_down(.S) then controller.camera.position -= controller.camera.front * velocity;
    if input_key_down(.A) then controller.camera.position -= controller.camera.right * velocity;
    if input_key_down(.D) then controller.camera.position += controller.camera.right * velocity;
    if input_key_down(.E) then controller.camera.position += controller.camera.world_up * velocity;
    if input_key_down(.Q) then controller.camera.position -= controller.camera.world_up * velocity;
}

process_mouse :: (controller: *Camera_Controller) {
    dx, dy := input_mouse_delta();

    if controller.skip_next_mouse_delta {
        controller.skip_next_mouse_delta = false;
        return;
    }

    controller.camera.yaw += cast(float32) dx * controller.mouse_sensitivity;
    controller.camera.pitch -= cast(float32) dy * controller.mouse_sensitivity;

    controller.camera.pitch = clamp(controller.camera.pitch, -89.9, 89.9);

    camera_update_vectors(*controller.camera);
}
