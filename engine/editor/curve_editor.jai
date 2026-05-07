// File:        curve_editor.jai
// Author:      Lukáš Bien
// Description: Handles curve viewport drawing, point sub-selection, and point editing.

#scope_file

#import "Basic";
#import "Math";
#import "jai-imgui";

#scope_export

CURVE_EDITOR_POINT_RADIUS :: 7.0;
CURVE_EDITOR_SEGMENT_SAMPLES :: 16;

Editor_Curve_State :: struct {
    selected_node_runtime_id: u64;
    selected_point_index: s32 = -1;
    hovered_point_index: s32 = -1;
}

editor_curve_state: Editor_Curve_State;

editor_curve_init :: () {
    editor_curve_state = .{};
    editor_curve_state.selected_point_index = -1;
    editor_curve_state.hovered_point_index = -1;
}

editor_curve_shutdown :: () {
    editor_curve_state = .{};
    editor_curve_state.selected_point_index = -1;
    editor_curve_state.hovered_point_index = -1;
}

editor_curve_on_node_selected :: (node: *Node) {
    runtime_id := cast(u64) 0;
    if node {
        runtime_id = node.runtime_id;
    }

    if editor_curve_state.selected_node_runtime_id == runtime_id then return;

    editor_curve_state.selected_node_runtime_id = runtime_id;
    editor_curve_state.selected_point_index = -1;
    editor_curve_state.hovered_point_index = -1;
}

editor_curve_get_selected_component :: () -> *Curve_Component {
    if !selected_node then return null;
    return node_get_curve_component(selected_node);
}

editor_curve_has_selected_point :: () -> bool {
    curve := editor_curve_get_selected_component();
    if !curve then return false;
    return editor_curve_state.selected_point_index >= 0 &&
        editor_curve_state.selected_point_index < cast(s32) curve.points.count;
}

editor_curve_get_selected_point :: (curve: *Curve_Component = null) -> *Vector3 {
    resolved_curve := curve;
    if !resolved_curve {
        resolved_curve = editor_curve_get_selected_component();
    }
    if !resolved_curve then return null;
    if !editor_curve_has_selected_point() then return null;
    return *resolved_curve.points[editor_curve_state.selected_point_index];
}

editor_curve_select_point :: (index: s32) {
    editor_curve_state.selected_point_index = index;
}

editor_curve_clear_point_selection :: () {
    editor_curve_state.selected_point_index = -1;
    editor_curve_state.hovered_point_index = -1;
}

editor_curve_handle_viewport_selection :: () -> bool {
    curve := editor_curve_get_selected_component();
    if !curve || !selected_node then return false;
    if curve.points.count == 0 then return false;

    camera := app_get_render_camera();
    if !camera then return false;

    point_index := editor_curve_pick_point(curve, camera, CURVE_EDITOR_POINT_RADIUS);
    if point_index < 0 then return false;

    editor_curve_select_point(point_index);
    editor_gizmo_suppress_until_lmb_release();
    return true;
}

editor_curve_draw_viewport_overlay :: () {
    curve := editor_curve_get_selected_component();
    editor_curve_state.hovered_point_index = -1;

    if !curve || !selected_node || !ui_state.viewport_image_visible then return;

    camera := app_get_render_camera();
    if !camera then return;

    draw_list := GetWindowDrawList();
    if !draw_list then return;

    clip_min := ui_state.viewport_screen_min;
    clip_max := ui_state.viewport_screen_max;
    ImDrawList.PushClipRect(draw_list, clip_min, clip_max, true);
    defer ImDrawList.PopClipRect(draw_list);

    editor_curve_draw_control_polygon(draw_list, curve, camera);
    editor_curve_draw_spline(draw_list, curve, camera);
    editor_curve_draw_points(draw_list, curve, camera);
}

#scope_file

editor_curve_pick_point :: (
    curve: *Curve_Component,
    camera: *Camera,
    pixel_radius: float
) -> s32 {
    if !curve || !camera || !selected_node then return -1;

    mouse_x, mouse_y := input_mouse_position();
    mouse := ImVec2.{cast(float) mouse_x, cast(float) mouse_y};
    view := camera_get_view_matrix(camera.*);
    aspect := editor_curve_get_viewport_aspect();
    projection := camera_get_projection_matrix(camera.*, aspect);

    best_index: s32 = -1;
    best_distance_squared := pixel_radius * pixel_radius;
    for curve.points {
        world_position := (selected_node.world_matrix * Vector4.{it.x, it.y, it.z, 1.0}).xyz;
        visible, screen := editor_curve_project_world_point(world_position, view, projection);
        if !visible then continue;

        delta := screen - mouse;
        distance_squared := delta.x * delta.x + delta.y * delta.y;
        if distance_squared <= best_distance_squared {
            best_distance_squared = distance_squared;
            best_index = cast(s32) it_index;
        }
    }

    return best_index;
}

editor_curve_get_viewport_aspect :: () -> float {
    if ui_state.viewport_size.y <= 0.0 then return 1.0;
    return cast(float) ui_state.viewport_size.x / cast(float) ui_state.viewport_size.y;
}

editor_curve_project_world_point :: (
    world_position: Vector3,
    view: Matrix4,
    projection: Matrix4
) -> bool, ImVec2 {
    view_position := view * Vector4.{world_position.x, world_position.y, world_position.z, 1.0};
    clip_position := projection * view_position;
    if clip_position.w <= 0.0001 {
        return false, .{};
    }

    ndc := clip_position.xyz / clip_position.w;
    if ndc.z < -1.5 || ndc.z > 1.5 {
        return false, .{};
    }

    screen_x := ui_state.viewport_screen_min.x + (ndc.x * 0.5 + 0.5) * ui_state.viewport_size.x;
    screen_y := ui_state.viewport_screen_min.y + (1.0 - (ndc.y * 0.5 + 0.5)) * ui_state.viewport_size.y;
    return true, ImVec2.{screen_x, screen_y};
}

editor_curve_draw_control_polygon :: (
    draw_list: *ImDrawList,
    curve: *Curve_Component,
    camera: *Camera
) {
    if curve.points.count < 2 then return;

    view := camera_get_view_matrix(camera.*);
    projection := camera_get_projection_matrix(camera.*, editor_curve_get_viewport_aspect());
    control_color := GetColorU32(ImVec4.{0.82, 0.62, 0.22, 0.55});

    previous_visible := false;
    previous_screen: ImVec2;
    for curve.points {
        world_position := (selected_node.world_matrix * Vector4.{it.x, it.y, it.z, 1.0}).xyz;
        visible, screen := editor_curve_project_world_point(world_position, view, projection);
        if visible && previous_visible {
            ImDrawList.AddLine(draw_list, previous_screen, screen, control_color, 1.0);
        }
        previous_visible = visible;
        previous_screen = screen;
    }

    if curve.closed && curve.points.count > 2 {
        first_world := (selected_node.world_matrix *
            Vector4.{curve.points[0].x, curve.points[0].y, curve.points[0].z, 1.0}).xyz;
        first_visible, first_screen := editor_curve_project_world_point(first_world, view, projection);
        if previous_visible && first_visible {
            ImDrawList.AddLine(draw_list, previous_screen, first_screen, control_color, 1.0);
        }
    }
}

// draw a sampled overlay instead of a scene primitive so the curve tool stays
// editor-only until a runtime path system is added.
editor_curve_draw_spline :: (
    draw_list: *ImDrawList,
    curve: *Curve_Component,
    camera: *Camera
) {
    point_count := cast(s32) curve.points.count;
    segment_count := curve_segment_count(point_count, curve.closed);
    if segment_count <= 0 then return;

    view := camera_get_view_matrix(camera.*);
    projection := camera_get_projection_matrix(camera.*, editor_curve_get_viewport_aspect());
    spline_color := GetColorU32(ImVec4.{0.28, 0.82, 1.0, 0.95});

    for segment_index: 0..segment_count - 1 {
        previous_visible := false;
        previous_screen: ImVec2;

        for sample_index: 0..CURVE_EDITOR_SEGMENT_SAMPLES {
            t := cast(float) sample_index / cast(float) CURVE_EDITOR_SEGMENT_SAMPLES;
            local_position := curve_catmull_rom_segment_position(
                curve.points,
                curve.closed,
                segment_index,
                t
            );
            world_position := (selected_node.world_matrix *
                Vector4.{local_position.x, local_position.y, local_position.z, 1.0}).xyz;
            visible, screen := editor_curve_project_world_point(world_position, view, projection);
            if visible && previous_visible {
                ImDrawList.AddLine(draw_list, previous_screen, screen, spline_color, 2.0);
            }
            previous_visible = visible;
            previous_screen = screen;
        }
    }
}

editor_curve_draw_points :: (
    draw_list: *ImDrawList,
    curve: *Curve_Component,
    camera: *Camera
) {
    if !curve || !camera || !selected_node then return;

    view := camera_get_view_matrix(camera.*);
    projection := camera_get_projection_matrix(camera.*, editor_curve_get_viewport_aspect());
    mouse_x, mouse_y := input_mouse_position();
    mouse := ImVec2.{cast(float) mouse_x, cast(float) mouse_y};

    hovered_index: s32 = -1;
    hovered_distance_squared := CURVE_EDITOR_POINT_RADIUS * CURVE_EDITOR_POINT_RADIUS;

    for curve.points {
        world_position := (selected_node.world_matrix * Vector4.{it.x, it.y, it.z, 1.0}).xyz;
        visible, screen := editor_curve_project_world_point(world_position, view, projection);
        if !visible then continue;

        delta := screen - mouse;
        distance_squared := delta.x * delta.x + delta.y * delta.y;
        if distance_squared <= hovered_distance_squared {
            hovered_distance_squared = distance_squared;
            hovered_index = cast(s32) it_index;
        }
    }

    editor_curve_state.hovered_point_index = hovered_index;

    for curve.points {
        world_position := (selected_node.world_matrix * Vector4.{it.x, it.y, it.z, 1.0}).xyz;
        visible, screen := editor_curve_project_world_point(world_position, view, projection);
        if !visible then continue;

        is_selected := cast(s32) it_index == editor_curve_state.selected_point_index;
        is_hovered := cast(s32) it_index == editor_curve_state.hovered_point_index;

        fill_color := GetColorU32(ImVec4.{0.14, 0.15, 0.17, 0.95});
        border_color := GetColorU32(ImVec4.{0.78, 0.80, 0.84, 0.95});
        radius := CURVE_EDITOR_POINT_RADIUS - 1.0;

        if is_selected {
            fill_color = GetColorU32(ImVec4.{1.0, 0.74, 0.20, 1.0});
            border_color = GetColorU32(ImVec4.{1.0, 0.96, 0.82, 1.0});
            radius = CURVE_EDITOR_POINT_RADIUS;
        } else if is_hovered {
            fill_color = GetColorU32(ImVec4.{0.34, 0.58, 1.0, 0.95});
            border_color = GetColorU32(ImVec4.{0.90, 0.96, 1.0, 1.0});
        }

        ImDrawList.AddCircleFilled(draw_list, screen, radius, fill_color);
        ImDrawList.AddCircle(draw_list, screen, radius, border_color, 0, 2.0);
    }
}
