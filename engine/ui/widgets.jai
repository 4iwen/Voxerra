#scope_module

draw_vec3_control :: (
    label: string,
    value: *Vector3,
    speed: float = 0.1,
    reset_value := Vector3.{}
) -> bool {
    changed := false;

    PushID(label);

    AlignTextToFramePadding();
    Text(label);

    // axis colors
    flags: SliderFlags = .ColorMarkers;

    drag_changed := DragFloat3(
        "##value",
        *value.component,
        speed,
        -FLOAT32_MAX,
        FLOAT32_MAX,
        flags = flags
    );
    if value.* != reset_value {
        SameLine();
        if SmallButton("Reset") {
            value.* = reset_value;
            changed = true;
        }
    }

    if drag_changed {
        changed = true;
    }

    PopID();

    return changed;
}

Rotation_Edit_State :: struct {
    euler_radians: Vector3;
    last_quaternion: Quaternion;
}

ui_reset_rotation_state :: (value: Quaternion) {
    using ui_state.rotation_state;
    
    euler_radians = quaternion_to_euler_xyz(value);
    last_quaternion = value;
}

draw_rotation_control :: (
    label: string,
    value: *Quaternion,
    speed: float = 0.01,
    reset_value := Vector3.{}
) -> bool {
    using ui_state.rotation_state;

    changed := false;

    if !quaternion_equal_rotation(value.*, last_quaternion) {
        fresh_euler := quaternion_to_euler_xyz(value.*);
        euler_radians = make_euler_continuous(fresh_euler, euler_radians);
        last_quaternion = value.*;
    }

    PushID(label);

    AlignTextToFramePadding();
    Text(label);

    // axis colors
    flags: SliderFlags = .ColorMarkers;

    drag_changed := DragFloat3(
        "##value",
        *euler_radians.component,
        speed,
        -FLOAT32_MAX,
        FLOAT32_MAX,
        flags = flags
    );

    if drag_changed {
        value.* = quaternion_from_euler_xyz(euler_radians);
        normalize_or_identity(value);
        last_quaternion = value.*;
    }

    reset_quat := quaternion_from_euler_xyz(reset_value);
    normalize_or_identity(*reset_quat);

    // reset button if value changed
    if !quaternion_equal_rotation(value.*, reset_quat) {
        SameLine();
        if SmallButton("Reset") {
            value.* = reset_quat;
            euler_radians = reset_value;
            last_quaternion = value.*;
            changed = true;
        }
    }

    if drag_changed {
        changed = true;
    }

    PopID();

    return changed;
}

COLLAPSING_HEADER_FLAGS: TreeNodeFlags : .DefaultOpen | .Framed | .SpanAvailWidth;

// @Cleanup: bring out selected_node into the params for which this should be drawn
draw_transform_component :: () {
    if CollapsingHeader("Transform", COLLAPSING_HEADER_FLAGS) {
        Checkbox("Active", *selected_node.active);

        Separator();

        draw_vec3_control(
            "Position",
            *selected_node.local.position,
            0.1,
            .{0, 0, 0}
        );
        draw_rotation_control(
            "Rotation",
            *selected_node.local.rotation,
            0.01,
            .{0, 0, 0}
        );
        draw_vec3_control(
            "Scale",
            *selected_node.local.scale,
            0.1,
            .{1, 1, 1}
        );
    }
}
