#scope_file

#import "Basic";
#import "Math";

#scope_module

Sprite_System_State :: struct {
    quad_mesh: *Mesh;
    default_shader: *Shader;
}

sprite_system_state: Sprite_System_State;

#scope_export

sprite_system_shutdown :: () {
    if sprite_system_state.quad_mesh {
        mesh_destroy(sprite_system_state.quad_mesh);
        sprite_system_state.quad_mesh = null;
    }
    sprite_system_state.default_shader = null;
    sprite_system_state = .{};
}

sprite_system_update :: (
    scene: *Scene,
    camera: *Camera,
    delta_time: float64
) {
    if !scene || !scene.root then return;
    sprite_system_update_node(scene.root, camera, delta_time);
}

sprite_system_get_quad_mesh :: () -> *Mesh {
    if !sprite_system_state.quad_mesh {
        sprite_system_state.quad_mesh = mesh_create_quad();
    }

    return sprite_system_state.quad_mesh;
}

sprite_system_resolve_shader :: (sprite: *Sprite_Component) -> *Shader {
    if sprite && sprite.shader {
        return sprite.shader;
    }

    if !sprite_system_state.default_shader {
        sprite_system_state.default_shader = asset_manager_load_shader(
            "engine/assets/shaders/unlit_alpha.vert",
            "engine/assets/shaders/unlit_alpha.frag",
            true
        );
    }

    return sprite_system_state.default_shader;
}

sprite_system_resolve_texture :: (sprite: *Sprite_Component) -> *Texture {
    if sprite && sprite.texture {
        return sprite.texture;
    }

    return asset_manager_get_default_texture();
}

#scope_file

sprite_system_update_node :: (
    node: *Node,
    camera: *Camera,
    delta_time: float64
) {
    if !node || !node.active then return;

    animated_sprite := node_get_animated_sprite_component(node);
    sprite := node_get_sprite_component(node);

    if sprite {
        sprite_component_ensure_defaults(sprite);

        if animated_sprite {
            animated_sprite_update(animated_sprite, sprite, delta_time);
        }

        sprite_component_update_render_matrix(sprite, camera);
    }

    for node.children {
        sprite_system_update_node(it, camera, delta_time);
    }
}

sprite_component_ensure_defaults :: (sprite: *Sprite_Component) {
    if !sprite then return;

    if sprite.uv_transform.coef[2][2] == 0.0 {
        sprite.uv_transform.coef[0][0] = 1.0;
        sprite.uv_transform.coef[1][1] = 1.0;
        sprite.uv_transform.coef[2][2] = 1.0;
    }
}

animated_sprite_update :: (
    animated_sprite: *Animated_Sprite_Component,
    sprite: *Sprite_Component,
    delta_time: float64
) {
    if !animated_sprite || !sprite then return;

    columns := max(animated_sprite.columns, 1);
    rows := max(animated_sprite.rows, 1);
    max_frames := columns * rows;
    frame_count := clamp(animated_sprite.frame_count, 1, max_frames);
    animated_sprite.frame_count = frame_count;

    if animated_sprite.playing && animated_sprite.fps > 0.0 {
        frame_duration := 1.0 / cast(float64) animated_sprite.fps;
        animated_sprite.frame_accumulator += delta_time;

        while animated_sprite.frame_accumulator >= frame_duration {
            animated_sprite.frame_accumulator -= frame_duration;
            next_frame := animated_sprite.current_frame + 1;

            if next_frame >= frame_count {
                if animated_sprite.loop {
                    next_frame = 0;
                } else {
                    next_frame = frame_count - 1;
                    animated_sprite.playing = false;
                }
            }

            animated_sprite.current_frame = next_frame;
        }
    }

    animated_sprite.current_frame = clamp(animated_sprite.current_frame, 0, frame_count - 1);
    sprite.uv_transform = animated_sprite_make_uv_transform(animated_sprite.current_frame, columns, rows);
}

animated_sprite_make_uv_transform :: (
    frame_index: s32,
    columns: s32,
    rows: s32
) -> Matrix3 {
    safe_columns := max(columns, 1);
    safe_rows := max(rows, 1);

    scale_x := 1.0 / cast(float) safe_columns;
    scale_y := 1.0 / cast(float) safe_rows;

    column := frame_index % safe_columns;
    row := frame_index / safe_columns;

    translate_x := cast(float) column * scale_x;
    translate_y := 1.0 - cast(float) (row + 1) * scale_y;

    matrix: Matrix3 = .{};
    matrix.coef[0][0] = scale_x;
    matrix.coef[0][2] = translate_x;
    matrix.coef[1][1] = scale_y;
    matrix.coef[1][2] = translate_y;
    matrix.coef[2][2] = 1.0;
    return matrix;
}

sprite_component_update_render_matrix :: (
    sprite: *Sprite_Component,
    camera: *Camera
) {
    if !sprite || !sprite.node then return;

    node := sprite.node;

    parent_world := Matrix4_Identity;
    if node.parent {
        parent_world = node.parent.world_matrix;
    }

    translation := make_translation_matrix4(node.local.position);
    rotation := rotation_matrix(
        Matrix4,
        sprite_component_get_billboard_rotation(sprite, camera)
    );
    node_scale := scale(Matrix4_Identity, node.local.scale);

    half_size := Vector3.{
        max(sprite.size.x, 0.0001) * 0.5,
        max(sprite.size.y, 0.0001) * 0.5,
        1.0
    };
    pivot_offset := sprite_component_get_pivot_offset(sprite.pivot);
    sprite_local := make_translation_matrix4(pivot_offset) * scale(Matrix4_Identity, half_size);

    sprite.render_matrix = parent_world * translation * rotation * node_scale * sprite_local;
}

sprite_component_get_billboard_rotation :: (
    sprite: *Sprite_Component,
    camera: *Camera
) -> Quaternion {
    if !sprite || !sprite.node then return .{0, 0, 0, 1};

    node := sprite.node;
    if sprite.billboard_mode == .NONE || !camera {
        return node.local.rotation;
    }

    to_camera := camera.position - node.world_position;
    if length_squared(to_camera) <= 0.000001 {
        return node.local.rotation;
    }

    if sprite.billboard_mode == .Y_AXIS {
        to_camera.y = 0.0;
        if length_squared(to_camera) <= 0.000001 {
            return node.local.rotation;
        }

        yaw := atan2(to_camera.x, to_camera.z);
        return quaternion_from_euler_xyz(.{0.0, yaw + PI, 0.0});
    }

    horizontal_length := sqrt(to_camera.x * to_camera.x + to_camera.z * to_camera.z);
    yaw := atan2(to_camera.x, to_camera.z);
    pitch := -atan2(to_camera.y, max(horizontal_length, 0.0001));
    return quaternion_from_euler_xyz(.{pitch, yaw + PI, 0.0});
}

sprite_component_get_pivot_offset :: (pivot: Sprite_Pivot) -> Vector3 {
    if pivot == .BOTTOM_CENTER {
        return .{0.0, 1.0, 0.0};
    }
    if pivot == .TOP_CENTER {
        return .{0.0, -1.0, 0.0};
    }

    return .{0.0, 0.0, 0.0};
}
