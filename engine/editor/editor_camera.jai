// File:        editor_camera.jai
// Author:      Lukáš Bien
// Description: Updates the editor orbit camera and its viewport interaction behavior.

#scope_file

#import "Basic";
#import "Math";

Editor_Camera_State :: struct {
    fly_active: bool;
    block_fly_until_rmb_release: bool;
    skip_next_mouse_delta: bool;
}

editor_camera_state: Editor_Camera_State;

EDITOR_CAMERA_MAX_SCROLL_DELTA :: 24.0;
EDITOR_CAMERA_MAX_DELTA_TIME   :: 0.1;
EDITOR_CAMERA_FLY_SPEED        :: 8.0;
EDITOR_CAMERA_FLY_FAST_MULT    :: 3.0;

#scope_export

editor_camera_update :: (delta_time: float64) {
    window := engine_get_window();
    rmb_down := input_mouse_down(.RIGHT);

    if editor_camera_state.block_fly_until_rmb_release && !rmb_down {
        editor_camera_state.block_fly_until_rmb_release = false;
    }

    if editor_camera_state.fly_active {
        should_cancel := !rmb_down || input_key_pressed(.ESCAPE);
        if !window || !window_is_focused(window) then should_cancel = true;

        if should_cancel {
            editor_camera_end_fly(block_until_rmb_release = rmb_down);
            rmb_down = false;
        }
    }

    tab := editor_get_active_tab();
    if !tab {
        editor_camera_cancel_fly();
        return;
    }

    if !editor_camera_state.fly_active && !input_viewport_mouse_allowed() then return;
    if input_state.cursor_disabled && !editor_camera_state.fly_active then return;

    view := *tab.view_camera;
    mouse_dx, mouse_dy := input_mouse_delta();
    scroll_x, scroll_y := input_scroll();

    if input_viewport_shortcuts_allowed() && input_key_pressed(.F) {
        editor_camera_frame_selection(view);
    }

    if !editor_camera_state.fly_active &&
       input_mouse_pressed(.RIGHT) &&
       input_viewport_mouse_allowed() &&
       !editor_camera_state.block_fly_until_rmb_release {
        editor_camera_begin_fly(window);
    }

    if editor_camera_state.skip_next_mouse_delta {
        mouse_dx = 0.0;
        mouse_dy = 0.0;
        editor_camera_state.skip_next_mouse_delta = false;
    }

    if editor_camera_state.fly_active {
        editor_camera_fly(view, delta_time, mouse_dx, mouse_dy);
    } else if input_mouse_down(.MIDDLE) {
        if input_key_down(.LEFT_SHIFT) || input_key_down(.RIGHT_SHIFT) {
            editor_camera_pan(view, mouse_dx, mouse_dy);
        } else {
            editor_camera_orbit(view, mouse_dx, mouse_dy);
        }
    }

    if !editor_camera_state.fly_active && (scroll_x != 0.0 || scroll_y != 0.0) {
        editor_camera_scroll_zoom(view, scroll_y);
    }

    editor_view_camera_rebuild(view);
}

editor_camera_cancel_fly :: () {
    editor_camera_end_fly(block_until_rmb_release = input_mouse_down(.RIGHT));
}

#scope_file

editor_camera_begin_fly :: (window: *Window) {
    if !window then return;

    window_set_cursor_mode(window, .DISABLED);
    editor_camera_state.fly_active = true;
    editor_camera_state.skip_next_mouse_delta = true;
}

editor_camera_end_fly :: (block_until_rmb_release: bool = false) {
    if editor_camera_state.fly_active && engine_state.window {
        window_set_cursor_mode(engine_state.window, .NORMAL);
    }

    editor_camera_state.fly_active = false;
    editor_camera_state.skip_next_mouse_delta = false;
    editor_camera_state.block_fly_until_rmb_release = block_until_rmb_release;
}

editor_camera_orbit :: (
    view: *Editor_View_Camera,
    mouse_dx: float64,
    mouse_dy: float64
) {
    sensitivity := 0.18;
    view.yaw += cast(float) mouse_dx * sensitivity;
    view.pitch -= cast(float) mouse_dy * sensitivity;
}

editor_camera_pan :: (
    view: *Editor_View_Camera,
    mouse_dx: float64,
    mouse_dy: float64
) {
    pan_scale := view.distance * 0.0018;
    view.focus -= view.camera.right * cast(float) mouse_dx * pan_scale;
    view.focus += view.camera.up * cast(float) mouse_dy * pan_scale;
}

editor_camera_fly :: (
    view: *Editor_View_Camera,
    delta_time: float64,
    mouse_dx: float64,
    mouse_dy: float64
) {
    camera_position := view.camera.position;

    editor_camera_orbit(view, mouse_dx, mouse_dy);
    front := editor_camera_front_from_angles(view.yaw, view.pitch);
    view.focus = camera_position + front * view.distance;
    editor_view_camera_rebuild(view);

    speed := EDITOR_CAMERA_FLY_SPEED;
    if input_key_down(.LEFT_SHIFT) then speed *= EDITOR_CAMERA_FLY_FAST_MULT;
    velocity := cast(float) editor_camera_sanitize_delta_time(delta_time) * speed;

    movement: Vector3;
    if input_key_down(.W) then movement += view.camera.front;
    if input_key_down(.S) then movement -= view.camera.front;
    if input_key_down(.A) then movement -= view.camera.right;
    if input_key_down(.D) then movement += view.camera.right;
    if input_key_down(.E) then movement += view.camera.world_up;
    if input_key_down(.Q) then movement -= view.camera.world_up;

    if length_squared(movement) > 0.00001 {
        movement = normalize(movement) * velocity;
        camera_position = view.camera.position + movement;
        view.focus = camera_position + view.camera.front * view.distance;
    }
}

editor_camera_scroll_zoom :: (
    view: *Editor_View_Camera,
    scroll_y: float64
) {
    if scroll_y == 0.0 then return;
    editor_camera_zoom(view, scroll_y);
}

editor_camera_zoom :: (
    view: *Editor_View_Camera,
    scroll_y: float64
) {
    if scroll_y != scroll_y then return;

    clamped_scroll := clamp(
        scroll_y,
        -EDITOR_CAMERA_MAX_SCROLL_DELTA,
        EDITOR_CAMERA_MAX_SCROLL_DELTA
    );
    zoom_base := 0.88;
    zoom_factor := pow(zoom_base, cast(float) clamped_scroll);
    view.distance = clamp(
        view.distance * zoom_factor,
        EDITOR_VIEW_CAMERA_MIN_DISTANCE,
        EDITOR_VIEW_CAMERA_MAX_DISTANCE
    );
}

editor_camera_frame_selection :: (view: *Editor_View_Camera) {
    if !selected_node then return;

    view.focus = selected_node.world_position;
    view.distance = 5.0;
}

editor_camera_front_from_angles :: (yaw: float, pitch: float) -> Vector3 {
    yaw_radians := degrees_to_radians(yaw);
    pitch_radians := degrees_to_radians(clamp(pitch, -89.0, 89.0));

    front: Vector3;
    front.x = cos(yaw_radians) * cos(pitch_radians);
    front.y = sin(pitch_radians);
    front.z = sin(yaw_radians) * cos(pitch_radians);
    return normalize(front);
}

editor_camera_sanitize_delta_time :: (delta_time: float64) -> float64 {
    if delta_time != delta_time then return 0.0;
    if delta_time < 0.0 then return 0.0;
    return min(delta_time, EDITOR_CAMERA_MAX_DELTA_TIME);
}
