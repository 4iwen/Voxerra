#scope_module

draw_vec3_control :: (
    label: string,
    value: *Vector3,
    speed: float = 0.1,
    value_min: float = -FLOAT32_MAX,
    value_max: float = FLOAT32_MAX,
    reset_value := Vector3.{},
    draw_label: bool = true
) -> bool {
    changed := false;

    PushID(label);

    if draw_label {
        AlignTextToFramePadding();
        Text(label);
    }

    // axis colors
    flags: SliderFlags = .ColorMarkers;

    drag_changed := DragFloat3(
        "##value",
        *value.component,
        speed,
        value_min,
        value_max,
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
    value_min: float = -FLOAT32_MAX,
    value_max: float = FLOAT32_MAX,
    reset_value := Vector3.{},
    draw_label: bool = true
) -> bool {
    using ui_state.rotation_state;

    changed := false;

    if !quaternion_equal_rotation(value.*, last_quaternion) {
        fresh_euler := quaternion_to_euler_xyz(value.*);
        euler_radians = make_euler_continuous(fresh_euler, euler_radians);
        last_quaternion = value.*;
    }

    PushID(label);

    if draw_label {
        AlignTextToFramePadding();
        Text(label);
    }

    // axis colors
    flags: SliderFlags = .ColorMarkers;
    
    // convert internal radians to degrees for the ui display
    euler_degrees: Vector3 = .{
        euler_radians.x * (180.0 / PI),
        euler_radians.y * (180.0 / PI),
        euler_radians.z * (180.0 / PI)
    };

    drag_changed := DragFloat3(
        "##value",
        *euler_degrees.component,
        speed * 10.0, // scale speed for degrees
        value_min,
        value_max,
        flags = flags
    );

    if drag_changed {
        // convert from ui degrees back to internal radians
        euler_radians.x = euler_degrees.x * (PI / 180.0);
        euler_radians.y = euler_degrees.y * (PI / 180.0);
        euler_radians.z = euler_degrees.z * (PI / 180.0);
        
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

draw_transform_component :: (node: *Node) {
    if CollapsingHeader("Transform", COLLAPSING_HEADER_FLAGS) {
        if BeginTable("Transform_Table", 2, TABLE_FLAGS, ImVec2.{0, 0}) {
            TableSetupColumn("Name", .WidthFixed, 0.0);
            TableSetupColumn("Value", .WidthStretch, 0.0);

            TableNextRow(); TableNextColumn();
            AlignTextToFramePadding();
            Text("Active");
            if BeginItemTooltip() {
                TextUnformatted("Whether this node and its children are active and rendered");
                EndTooltip();
            }
            TableNextColumn();
            PushItemWidth(-1);
            Checkbox("##Active", *node.active);
            PopItemWidth();

            t_info := cast(*Type_Info_Struct) type_info(Transform);
            ui_draw_struct_fields(cast(*void) *node.local, t_info, false);

            EndTable();
        }
    }
}
