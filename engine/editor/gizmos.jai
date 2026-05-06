// File:        gizmos.jai
// Author:      Lukáš Bien
// Description: Draws and applies transform gizmo interaction inside the editor viewport.

#scope_file

#import "Basic";
#import "Math";
#import "jai-imgui";
#import "jai-imguizmo";

#scope_export

Gizmo_Operation :: enum {
    TRANSLATE;
    ROTATE;
    SCALE;
}

Gizmo_Space :: enum {
    LOCAL;
    WORLD;
}

Editor_Gizmo_State :: struct {
    operation: Gizmo_Operation = .TRANSLATE;
    space: Gizmo_Space = .LOCAL;
    snap_enabled: bool;
    move_snap: Vector3 = .{0.5, 0.5, 0.5};
    rotate_snap_degrees: float = 15.0;
    scale_snap: float = 0.1;
    is_over: bool;
    is_using: bool;
    rect_min: ImVec2;
    rect_size: ImVec2;
    valid_rect: bool;
    suppress_input_until_lmb_release: bool;
}

editor_gizmo_state: Editor_Gizmo_State;

editor_gizmo_init :: () {
    editor_gizmo_state = .{};
}

editor_gizmo_shutdown :: () {
    editor_gizmo_state = .{};
}

editor_gizmo_is_over_or_using :: () -> bool {
    return editor_gizmo_state.is_over || editor_gizmo_state.is_using;
}

editor_gizmo_wants_mouse_capture :: () -> bool {
    return editor_gizmo_state.is_over || editor_gizmo_state.is_using;
}

editor_gizmo_suppress_until_lmb_release :: () {
    editor_gizmo_state.suppress_input_until_lmb_release = true;
    editor_gizmo_state.is_over = false;
    editor_gizmo_state.is_using = false;
}

editor_gizmo_draw :: () {
    editor_gizmo_state.is_over = false;
    editor_gizmo_state.is_using = false;

    if editor_gizmo_state.suppress_input_until_lmb_release && !input_mouse_down(.LEFT) {
        editor_gizmo_state.suppress_input_until_lmb_release = false;
    }

    if !ui_state.viewport_image_visible then return;

    editor_gizmo_handle_hotkeys();

    if !selected_node {
        return;
    }

    scene := engine_state.current_scene;
    camera := app_get_render_camera();
    if !scene || !camera {
        return;
    }

    viewport_min := ui_state.viewport_screen_min;
    viewport_size := ui_state.viewport_size;
    gizmo_min := viewport_min;
    gizmo_size := viewport_size;

    if gizmo_size.x <= 8.0 || gizmo_size.y <= 8.0 then return;

    view := camera_get_view_matrix(camera.*);
    aspect := 1.0;
    if ui_state.viewport_size.y > 0 {
        aspect = cast(float) ui_state.viewport_size.x / cast(float) ui_state.viewport_size.y;
    }
    projection := camera_get_projection_matrix(camera.*, aspect);

    parent_world := Matrix4_Identity;
    if selected_node.parent {
        parent_world = selected_node.parent.world_matrix;
    }

    editor_imguizmo_begin_frame(gizmo_min, gizmo_size);
    allow_gizmo_input := !input_state.cursor_disabled && !editor_gizmo_state.suppress_input_until_lmb_release;
    ImGuizmo_Enable(allow_gizmo_input);

    rotate_snap_radians := editor_gizmo_state.rotate_snap_degrees * (PI / 180.0);
    changed := editor_imguizmo_manipulate_trs(
        view,
        projection,
        parent_world,
        *selected_node.local.position,
        *selected_node.local.rotation,
        *selected_node.local.scale,
        editor_gizmo_state.operation,
        editor_gizmo_state.space,
        editor_gizmo_state.move_snap,
        rotate_snap_radians,
        editor_gizmo_state.scale_snap,
        editor_gizmo_state.snap_enabled
    );

    if allow_gizmo_input {
        editor_gizmo_state.is_over = ImGuizmo_IsOver();
        editor_gizmo_state.is_using = ImGuizmo_IsUsing();
    }

    if changed {
        scene_update_transforms(scene);
        ui_reset_rotation_state(selected_node.local.rotation);
        editor_mark_current_scene_dirty();
    }
}

editor_gizmo_draw_viewport_menu_bar :: () {
    if editor_is_playing() {
        if MenuItem(UI_Icon_Label(ICON_FA_STOP, "Stop")) {
            editor_stop();
        }
    } else if MenuItem(UI_Icon_Label(ICON_FA_PLAY, "Play")) {
        editor_play();
    }

    Separator();

    if MenuItem(UI_Icon_Label(ICON_FA_UP_DOWN_LEFT_RIGHT, "Move"), "G", selected = editor_gizmo_state.operation == .TRANSLATE) {
        editor_gizmo_state.operation = .TRANSLATE;
    }
    if MenuItem(UI_Icon_Label(ICON_FA_ROTATE, "Rotate"), "R", selected = editor_gizmo_state.operation == .ROTATE) {
        editor_gizmo_state.operation = .ROTATE;
    }
    if MenuItem(UI_Icon_Label(ICON_FA_UP_RIGHT_AND_DOWN_LEFT_FROM_CENTER, "Scale"), "S", selected = editor_gizmo_state.operation == .SCALE) {
        editor_gizmo_state.operation = .SCALE;
    }

    Separator();

    if MenuItem(UI_Icon_Label(ICON_FA_OBJECT_GROUP, "Local"), "", selected = editor_gizmo_state.space == .LOCAL) {
        editor_gizmo_state.space = .LOCAL;
    }
    if MenuItem(UI_Icon_Label(ICON_FA_GLOBE, "World"), "", selected = editor_gizmo_state.space == .WORLD) {
        editor_gizmo_state.space = .WORLD;
    }

    Separator();

    snap_label := "Snap";
    if editor_gizmo_state.snap_enabled {
        snap_label = "Snap On";
    }
    if BeginMenu(temp_c_string(tprint("% %", ICON_FA_MAGNET, snap_label))) {
        Checkbox("Enabled", *editor_gizmo_state.snap_enabled);
        Separator();

        BeginDisabled(!editor_gizmo_state.snap_enabled);
        SetNextItemWidth(220.0);
        DragFloat3("Move", *editor_gizmo_state.move_snap.component, 0.05, 0.01, 100.0);
        SetNextItemWidth(220.0);
        DragFloat("Rotate Degrees", *editor_gizmo_state.rotate_snap_degrees, 1.0, 1.0, 180.0);
        SetNextItemWidth(220.0);
        DragFloat("Scale", *editor_gizmo_state.scale_snap, 0.01, 0.01, 10.0);
        EndDisabled();

        EndMenu();
    }

    Separator();

    render_mode_label := tprint("% Render Mode: %", ICON_FA_EYE, editor_render_mode_label());
    BeginDisabled(editor_is_playing());
    if BeginMenu(temp_c_string(render_mode_label)) {
        if MenuItem(UI_Icon_Label(ICON_FA_SUN, "Lit"), "", selected = editor_context.render_mode == .LIT) {
            editor_context.render_mode = .LIT;
        }
        if MenuItem(UI_Icon_Label(ICON_FA_MOON, "Unlit"), "", selected = editor_context.render_mode == .UNLIT) {
            editor_context.render_mode = .UNLIT;
        }
        if MenuItem(UI_Icon_Label(ICON_FA_CUBE, "Wireframe"), "", selected = editor_context.render_mode == .WIREFRAME) {
            editor_context.render_mode = .WIREFRAME;
        }
        if MenuItem(UI_Icon_Label(ICON_FA_LIGHTBULB, "Lighting Only"), "", selected = editor_context.render_mode == .LIGHTING_ONLY) {
            editor_context.render_mode = .LIGHTING_ONLY;
        }
        if MenuItem(UI_Icon_Label(ICON_FA_PALETTE, "Albedo"), "", selected = editor_context.render_mode == .ALBEDO) {
            editor_context.render_mode = .ALBEDO;
        }
        EndMenu();
    }
    EndDisabled();
}

#scope_file

editor_gizmo_handle_hotkeys :: () {
    if !input_viewport_shortcuts_allowed() then return;
    if input_state.cursor_disabled then return;
    if input_primary_modifier_down() then return;

    if input_key_pressed(.G) then editor_gizmo_state.operation = .TRANSLATE;
    if input_key_pressed(.R) then editor_gizmo_state.operation = .ROTATE;
    if input_key_pressed(.S) then editor_gizmo_state.operation = .SCALE;
}

editor_imguizmo_begin_frame :: (rect_min: ImVec2, rect_size: ImVec2) {
    editor_gizmo_state.rect_min = rect_min;
    editor_gizmo_state.rect_size = rect_size;
    editor_gizmo_state.valid_rect = rect_size.x > 1.0 && rect_size.y > 1.0;

    ctx := GetCurrentContext();
    if ctx {
        ImGuizmo_SetImGuiContext(ctx);
    }

    ImGuizmo_BeginFrame();
    ImGuizmo_SetDrawlist();

    if editor_gizmo_state.valid_rect {
        ImGuizmo_SetRect(rect_min.x, rect_min.y, rect_size.x, rect_size.y);
    }
}

// ImGuizmo operates in world space, so convert the edited local transform
// through the parent and then pull the result back.
editor_imguizmo_manipulate_trs :: (
    view: Matrix4,
    projection: Matrix4,
    parent_world: Matrix4,
    local_position: *Vector3,
    local_rotation: *Quaternion,
    local_scale: *Vector3,
    operation: Gizmo_Operation,
    mode: Gizmo_Space,
    move_snap: Vector3,
    rotate_snap_radians: float,
    scale_snap: float,
    snap_enabled: bool
) -> bool {
    if !editor_gizmo_state.valid_rect || !local_position || !local_rotation || !local_scale {
        return false;
    }

    local_matrix := editor_gizmo_compose_trs(local_position.*, local_rotation.*, local_scale.*);
    world_matrix := parent_world * local_matrix;

    im_view := transpose(view);
    im_projection := transpose(projection);
    im_world := transpose(world_matrix);
    im_delta := Matrix4_Identity;

    im_operation := ImGuizmo_Operation.TRANSLATE;
    if operation == .ROTATE {
        im_operation = .ROTATE;
    } else if operation == .SCALE {
        im_operation = .SCALE;
    }

    im_mode := ImGuizmo_Mode.LOCAL;
    if mode == .WORLD {
        im_mode = .WORLD;
    }

    snap_buffer: [3]float;
    snap_ptr: *float = null;
    if snap_enabled {
        if operation == .TRANSLATE {
            snap_buffer[0] = move_snap.x;
            snap_buffer[1] = move_snap.y;
            snap_buffer[2] = move_snap.z;
            snap_ptr = *snap_buffer[0];
        } else if operation == .ROTATE {
            snap_buffer[0] = rotate_snap_radians * (180.0 / PI);
            snap_ptr = *snap_buffer[0];
        } else {
            snap_buffer[0] = scale_snap;
            snap_ptr = *snap_buffer[0];
        }
    }

    changed := ImGuizmo_Manipulate(
        *im_view.floats[0],
        *im_projection.floats[0],
        im_operation,
        im_mode,
        *im_world.floats[0],
        *im_delta.floats[0],
        snap_ptr,
        null,
        null
    );
    if !changed then return false;

    world_result := transpose(im_world);
    delta_result := transpose(im_delta);

    parent_inverse_success, parent_inverse := inverse(parent_world);
    local_result := world_result;
    if parent_inverse_success {
        local_result = parent_inverse * world_result;
    }

    if operation == .TRANSLATE {
        local_position.* = editor_gizmo_get_translation(local_result);
    } else if operation == .ROTATE {
        local_rotation.* = editor_gizmo_extract_rotation(local_result);
        normalize_or_identity(local_rotation);
    } else if operation == .SCALE {
        delta_scale := editor_gizmo_extract_scale(delta_result);
        local_scale.x *= delta_scale.x;
        local_scale.y *= delta_scale.y;
        local_scale.z *= delta_scale.z;
    }

    return true;
}

editor_gizmo_compose_trs :: (position: Vector3, rotation: Quaternion, scale_value: Vector3) -> Matrix4 {
    return make_translation_matrix4(position) *
        rotation_matrix(Matrix4, rotation) *
        scale(Matrix4_Identity, scale_value);
}

editor_gizmo_get_translation :: (m: Matrix4) -> Vector3 {
    return .{m._14, m._24, m._34};
}

editor_gizmo_extract_scale :: (m: Matrix4) -> Vector3 {
    return .{
        length(Vector3.{m._11, m._21, m._31}),
        length(Vector3.{m._12, m._22, m._32}),
        length(Vector3.{m._13, m._23, m._33}),
    };
}

editor_gizmo_extract_rotation :: (m: Matrix4) -> Quaternion {
    r := m;

    x := Vector3.{r._11, r._21, r._31};
    y := Vector3.{r._12, r._22, r._32};
    z := Vector3.{r._13, r._23, r._33};

    normalize(*x, 0.000001, .{1, 0, 0});
    normalize(*y, 0.000001, .{0, 1, 0});
    normalize(*z, 0.000001, .{0, 0, 1});

    r._11 = x.x; r._21 = x.y; r._31 = x.z;
    r._12 = y.x; r._22 = y.y; r._32 = y.z;
    r._13 = z.x; r._23 = z.y; r._33 = z.z;

    q := get_rotation(r);
    normalize_or_identity(*q);
    return q;
}
