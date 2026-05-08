// File:        sprite_system.jai
// Author:      Lukáš Bien
// Description: Builds sprite render data and draws billboard and animated sprite quads.

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
    rotation := sprite_component_get_rotation_matrix(sprite, camera, parent_world);
    node_scale := scale(Matrix4_Identity, node.local.scale);

    half_size := Vector3.{
        max(sprite.size.x, 0.0001) * 0.5,
        max(sprite.size.y, 0.0001) * 0.5,
        1.0
    };
    pivot_offset := sprite_component_get_pivot_offset(sprite);
    sprite_local := make_translation_matrix4(pivot_offset) * scale(Matrix4_Identity, half_size);

    sprite.render_matrix = parent_world * translation * rotation * node_scale * sprite_local;
}

sprite_component_get_rotation_matrix :: (
    sprite: *Sprite_Component,
    camera: *Camera,
    parent_world: Matrix4
) -> Matrix4 {
    if !sprite || !sprite.node then return Matrix4_Identity;

    node := sprite.node;
    if sprite.billboard_mode == .NONE || !camera {
        return rotation_matrix(Matrix4, node.local.rotation);
    }

    world_rotation := sprite_component_get_billboard_world_matrix(sprite, camera);
    if node.parent {
        return sprite_component_world_rotation_to_parent(parent_world, world_rotation);
    }

    return world_rotation;
}

sprite_component_get_billboard_world_matrix :: (
    sprite: *Sprite_Component,
    camera: *Camera
) -> Matrix4 {
    if !sprite || !sprite.node || !camera then return Matrix4_Identity;

    node := sprite.node;

    forward := camera.position - node.world_position;
    if sprite.billboard_mode == .Y_AXIS {
        forward.y = 0.0;
    }

    if length_squared(forward) <= 0.000001 {
        return sprite_component_get_node_world_rotation(node);
    }
    forward = normalize(forward);

    up := ifx sprite.billboard_mode == .Y_AXIS then Vector3.{0.0, 1.0, 0.0} else camera.up;
    right := cross(up, forward);
    if length_squared(right) <= 0.000001 {
        right = camera.right;
    }
    if length_squared(right) <= 0.000001 {
        right = .{1.0, 0.0, 0.0};
    }
    right = normalize(right);

    up = cross(forward, right);
    if length_squared(up) <= 0.000001 {
        up = .{0.0, 1.0, 0.0};
    } else {
        up = normalize(up);
    }

    matrix := Matrix4_Identity;
    matrix._11 = right.x;   matrix._21 = right.y;   matrix._31 = right.z;
    matrix._12 = up.x;      matrix._22 = up.y;      matrix._32 = up.z;
    matrix._13 = forward.x; matrix._23 = forward.y; matrix._33 = forward.z;
    return matrix;
}

sprite_component_get_node_world_rotation :: (node: *Node) -> Matrix4 {
    if !node then return Matrix4_Identity;

    x := Vector3.{node.world_matrix._11, node.world_matrix._21, node.world_matrix._31};
    y := Vector3.{node.world_matrix._12, node.world_matrix._22, node.world_matrix._32};
    z := Vector3.{node.world_matrix._13, node.world_matrix._23, node.world_matrix._33};

    if length_squared(x) <= 0.000001 then x = .{1.0, 0.0, 0.0};
    if length_squared(y) <= 0.000001 then y = .{0.0, 1.0, 0.0};
    if length_squared(z) <= 0.000001 then z = .{0.0, 0.0, 1.0};

    x = normalize(x);
    y = normalize(y);
    z = normalize(z);

    matrix := Matrix4_Identity;
    matrix._11 = x.x; matrix._21 = x.y; matrix._31 = x.z;
    matrix._12 = y.x; matrix._22 = y.y; matrix._32 = y.z;
    matrix._13 = z.x; matrix._23 = z.y; matrix._33 = z.z;
    return matrix;
}

sprite_component_world_rotation_to_parent :: (
    parent_world: Matrix4,
    world_rotation: Matrix4
) -> Matrix4 {
    parent_x := Vector3.{parent_world._11, parent_world._21, parent_world._31};
    parent_y := Vector3.{parent_world._12, parent_world._22, parent_world._32};
    parent_z := Vector3.{parent_world._13, parent_world._23, parent_world._33};

    if length_squared(parent_x) <= 0.000001 then parent_x = .{1.0, 0.0, 0.0};
    if length_squared(parent_y) <= 0.000001 then parent_y = .{0.0, 1.0, 0.0};
    if length_squared(parent_z) <= 0.000001 then parent_z = .{0.0, 0.0, 1.0};

    parent_x = normalize(parent_x);
    parent_y = normalize(parent_y);
    parent_z = normalize(parent_z);

    world_x := Vector3.{world_rotation._11, world_rotation._21, world_rotation._31};
    world_y := Vector3.{world_rotation._12, world_rotation._22, world_rotation._32};
    world_z := Vector3.{world_rotation._13, world_rotation._23, world_rotation._33};

    local := Matrix4_Identity;
    local._11 = dot(parent_x, world_x); local._21 = dot(parent_y, world_x); local._31 = dot(parent_z, world_x);
    local._12 = dot(parent_x, world_y); local._22 = dot(parent_y, world_y); local._32 = dot(parent_z, world_y);
    local._13 = dot(parent_x, world_z); local._23 = dot(parent_y, world_z); local._33 = dot(parent_z, world_z);
    return local;
}

sprite_component_get_pivot_offset :: (sprite: *Sprite_Component) -> Vector3 {
    pivot := sprite_component_get_pivot(sprite);
    return .{
        (0.5 - pivot.x) * 2.0,
        (0.5 - pivot.y) * 2.0,
        0.0
    };
}

sprite_component_get_pivot :: (sprite: *Sprite_Component) -> Vector2 {
    if !sprite then return .{0.5, 0.5};
    if sprite.custom_pivot_enabled {
        return .{
            clamp(sprite.custom_pivot.x, 0.0, 1.0),
            clamp(sprite.custom_pivot.y, 0.0, 1.0)
        };
    }

    if sprite.pivot == .TOP_LEFT      then return .{0.0, 1.0};
    if sprite.pivot == .TOP_CENTER    then return .{0.5, 1.0};
    if sprite.pivot == .TOP_RIGHT     then return .{1.0, 1.0};
    if sprite.pivot == .CENTER_LEFT   then return .{0.0, 0.5};
    if sprite.pivot == .CENTER_RIGHT  then return .{1.0, 0.5};
    if sprite.pivot == .BOTTOM_LEFT   then return .{0.0, 0.0};
    if sprite.pivot == .BOTTOM_CENTER then return .{0.5, 0.0};
    if sprite.pivot == .BOTTOM_RIGHT  then return .{1.0, 0.0};
    return .{0.5, 0.5};
}
