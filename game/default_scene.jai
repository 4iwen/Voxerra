#scope_file

#import "Basic";
#import "Math";

#scope_export

SUZANNE_PATH_CONTROL_POINTS : [6] Vector3 : .[
    Vector3.{-7.5, 1.45, -7.5},
    Vector3.{-2.8, 1.45, -15.5},
    Vector3.{4.0, 1.45, -14.0},
    Vector3.{8.0, 1.45, -8.0},
    Vector3.{4.0, 1.45, -3.5},
    Vector3.{-4.5, 1.45, -4.2}
];

Game_Scene_Runtime :: struct {
    scene: *Scene;
    suzanne_node: *Node;
    suzanne_node_runtime_id: u64;
    suzanne_material: *Material;
    suzanne_animation_enabled: bool = true;

    teapot_node: *Node;
    teapot_node_runtime_id: u64;
    teapot_materials: [..] *Material;
    teapot_highlight_enabled: bool;

    fire_node: *Node;
    fire_node_runtime_id: u64;
    fire_light_node_runtime_id: u64;
    fire_animation: *Animated_Sprite_Component;
    fire_light: *Light_Component;

    camera_bounds_min: Vector3 = .{-18.0, 1.0, -24.0};
    camera_bounds_max: Vector3 = .{18.0, 16.0, 18.0};
}

game_scene_runtime: Game_Scene_Runtime;

game_build_default_scene :: (scene: *Scene) {
    assert(scene != null, "game_build_default_scene: scene is null");

    game_scene_runtime = .{};
    game_scene_runtime.scene = scene;
    scene.ambient_color = .{0.16, 0.18, 0.22};

    game_load_default_scene_assets();
    game_create_hardcoded_suzanne(scene);
    game_create_teapot(scene);
    game_create_fire_billboard(scene);
    game_create_required_lights(scene);
}

game_rebind_default_scene_runtime :: (scene: *Scene) {
    if !scene then return;

    teapot_materials := game_scene_runtime.teapot_materials;
    suzanne_node_runtime_id := game_scene_runtime.suzanne_node_runtime_id;
    teapot_node_runtime_id := game_scene_runtime.teapot_node_runtime_id;
    fire_node_runtime_id := game_scene_runtime.fire_node_runtime_id;
    fire_light_node_runtime_id := game_scene_runtime.fire_light_node_runtime_id;
    game_scene_runtime = .{};
    game_scene_runtime.teapot_materials = teapot_materials;
    array_reset(*game_scene_runtime.teapot_materials);

    game_scene_runtime.scene = scene;
    game_scene_runtime.suzanne_node_runtime_id = suzanne_node_runtime_id;
    game_scene_runtime.teapot_node_runtime_id = teapot_node_runtime_id;
    game_scene_runtime.fire_node_runtime_id = fire_node_runtime_id;
    game_scene_runtime.fire_light_node_runtime_id = fire_light_node_runtime_id;
    game_scene_runtime.suzanne_animation_enabled = true;
    game_scene_runtime.suzanne_node = node_find_by_runtime_id(scene.root, game_scene_runtime.suzanne_node_runtime_id);
    if !game_scene_runtime.suzanne_node {
        game_scene_runtime.suzanne_node = node_find_by_scene_id(scene.root, "suzanne");
    }
    if game_scene_runtime.suzanne_node {
        game_scene_runtime.suzanne_node_runtime_id = game_scene_runtime.suzanne_node.runtime_id;
        mesh_component := node_get_component(game_scene_runtime.suzanne_node, Static_Mesh_Component);
        if mesh_component {
            game_scene_runtime.suzanne_material = mesh_component.material;
        }
    }

    game_scene_runtime.teapot_node = node_find_by_runtime_id(scene.root, game_scene_runtime.teapot_node_runtime_id);
    if !game_scene_runtime.teapot_node {
        game_scene_runtime.teapot_node = node_find_by_scene_id(scene.root, "teapot");
    }
    if game_scene_runtime.teapot_node {
        game_scene_runtime.teapot_node_runtime_id = game_scene_runtime.teapot_node.runtime_id;
    }
    game_collect_teapot_materials(game_scene_runtime.teapot_node);

    game_scene_runtime.fire_node = node_find_by_runtime_id(scene.root, game_scene_runtime.fire_node_runtime_id);
    if !game_scene_runtime.fire_node {
        game_scene_runtime.fire_node = node_find_by_scene_id(scene.root, "fire");
    }
    if game_scene_runtime.fire_node {
        game_scene_runtime.fire_node_runtime_id = game_scene_runtime.fire_node.runtime_id;
        game_scene_runtime.fire_animation = node_get_component(game_scene_runtime.fire_node, Animated_Sprite_Component);
        fire_light_node := node_find_by_runtime_id(game_scene_runtime.fire_node, game_scene_runtime.fire_light_node_runtime_id);
        if !fire_light_node {
            fire_light_node = node_find_by_scene_id(game_scene_runtime.fire_node, "fire_light");
        }
        if fire_light_node {
            game_scene_runtime.fire_light_node_runtime_id = fire_light_node.runtime_id;
        }
        game_scene_runtime.fire_light = node_get_component(fire_light_node, Light_Component);
    }
}

#scope_file

game_load_default_scene_assets :: () {
    shader := asset_manager_load_shader(
        "engine/assets/shaders/blinn_phong.vert",
        "engine/assets/shaders/blinn_phong.frag",
        true
    );
    if shader {
        asset_manager_set_default_shader(shader);
    } else {
        log_error("Failed to load default scene shader");
    }
}

game_create_hardcoded_suzanne :: (scene: *Scene) {
    shader := asset_manager_load_shader(
        "engine/assets/shaders/blinn_phong.vert",
        "engine/assets/shaders/blinn_phong.frag",
        true
    );

    mesh := game_create_suzanne_mesh();
    material := material_create("Suzanne");
    material.shader = shader;
    material.diffuse_map = asset_manager_get_default_texture();
    material.shininess = 48.0;
    material.tint_color = .{1.0, 1.0, 1.0};

    suzanne_node := node_add_node(scene.root, "Suzanne");
    suzanne_node.local.position = SUZANNE_PATH_CONTROL_POINTS[0];
    suzanne_node.local.scale = .{1.55, 1.55, 1.55};
    suzanne_node.local.rotation = quaternion_from_euler_xyz(.{0.0, 0.0, 0.0});

    mesh_component := node_add_component(suzanne_node, Static_Mesh_Component);
    mesh_component.mesh = mesh;
    mesh_component.material = material;

    game_scene_runtime.suzanne_node = suzanne_node;
    game_scene_runtime.suzanne_node_runtime_id = suzanne_node.runtime_id;
    game_scene_runtime.suzanne_material = material;
}

game_create_teapot :: (scene: *Scene) {
    mesh_node := game_add_model_component(
        scene.root,
        "Utah Teapot",
        "game/assets/models/utah_teapot.obj",
        .{2.2, 0.0, -12.0},
        .{0.0, -0.45, 0.0},
        .{0.85714287, 0.85714287, 0.85714287}
    );

    game_scene_runtime.teapot_node = mesh_node;
    if mesh_node {
        game_scene_runtime.teapot_node_runtime_id = mesh_node.runtime_id;
        game_collect_teapot_materials(mesh_node);
    }
}

game_create_required_lights :: (scene: *Scene) {
    sun_node := node_add_node(scene.root, "Sun");
    sun_node.local.rotation = quaternion_from_euler_xyz(.{-PI / 2.0 - 0.2, 0.0, 0.0});
    sun_light := node_add_component(sun_node, Light_Component);
    sun_light.light.type = .Directional;
    sun_light.light.color = .{1.0, 0.95, 0.9};
    sun_light.light.intensity = 1.6;

    point_node := node_add_node(scene.root, "Point Light");
    point_node.local.position = .{6.5, 5.8, -5.0};
    point_light := node_add_component(point_node, Light_Component);
    point_light.light.type = .Point;
    point_light.light.color = .{1.0, 0.0, 0.0};
    point_light.light.intensity = 2.3;
    point_light.light.range = 48.0;

    fill_node := node_add_node(scene.root, "Fill Light");
    fill_node.local.position = .{-10.5, 5.5, -7.0};
    fill_light := node_add_component(fill_node, Light_Component);
    fill_light.light.type = .Point;
    fill_light.light.color = .{0.2, 0.85, 1.0};
    fill_light.light.intensity = 2.0;
    fill_light.light.range = 44.0;

    rim_node := node_add_node(scene.root, "Rim Light");
    rim_node.local.position = .{0.0, 9.0, -20.0};
    rim_light := node_add_component(rim_node, Light_Component);
    rim_light.light.type = .Point;
    rim_light.light.color = .{1.0, 0.72, 0.3};
    rim_light.light.intensity = 1.8;
    rim_light.light.range = 40.0;

    spot_node := node_add_node(scene.root, "Spot Light");
    spot_node.local.position = .{-8.6, 8.0, 1.5};
    spot_node.local.rotation = quaternion_from_euler_xyz(.{-1.0, 0.45, 0.0});
    spot_light := node_add_component(spot_node, Light_Component);
    spot_light.light.type = .Spot;
    spot_light.light.color = .{0.25, 0.55, 1.0};
    spot_light.light.intensity = 4.2;
    spot_light.light.range = 42.0;
    spot_light.light.inner_cos = cast(float) cos(degrees_to_radians(16.0));
    spot_light.light.outer_cos = cast(float) cos(degrees_to_radians(28.0));

    accent_spot_node := node_add_node(scene.root, "Accent Spot Light");
    accent_spot_node.local.position = .{9.6, 8.8, 2.0};
    accent_spot_node.local.rotation = quaternion_from_euler_xyz(.{-1.02, -0.48, 0.0});
    accent_spot_light := node_add_component(accent_spot_node, Light_Component);
    accent_spot_light.light.type = .Spot;
    accent_spot_light.light.color = .{1.0, 0.45, 0.75};
    accent_spot_light.light.intensity = 3.6;
    accent_spot_light.light.range = 42.0;
    accent_spot_light.light.inner_cos = cast(float) cos(degrees_to_radians(14.0));
    accent_spot_light.light.outer_cos = cast(float) cos(degrees_to_radians(24.0));
}

game_create_fire_billboard :: (scene: *Scene) {
    texture_spec := UI_TEXTURE_SPEC;
    texture_spec.min_filter = .NEAREST;
    texture_spec.mag_filter = .NEAREST;
    texture := asset_manager_load_texture(
        "game/assets/textures/fire_animated.png",
        texture_spec,
        false
    );

    fire_node := node_add_node(scene.root, "Fire");
    fire_node.local.position = .{0.0, 1.6, -8.6};
    fire_node.local.scale = .{1.0, 1.0, 1.0};

    fire_animation := node_add_component(fire_node, Animated_Sprite_Component);
    fire_animation.texture = texture;
    fire_animation.tint_color = .{1.0, 0.95, 0.9};
    fire_animation.alpha_cutoff = 0.05;
    fire_animation.size = .{0.75, 1.4};
    fire_animation.pivot = .BOTTOM_CENTER;
    fire_animation.billboard_mode = .Y_AXIS;
    fire_animation.blend_mode = .ALPHA_BLEND;
    fire_animation.columns = 8;
    fire_animation.rows = 1;
    fire_animation.frame_count = 8;
    fire_animation.fps = 10.0;
    fire_animation.playing = true;
    fire_animation.loop = true;

    fire_light_node := node_add_node(fire_node, "Fire Light");
    fire_light_node.local.position = .{0.0, 0.55, 0.0};
    fire_light := node_add_component(fire_light_node, Light_Component);
    fire_light.light.type = .Point;
    fire_light.light.color = .{1.0, 0.42, 0.08};
    fire_light.light.intensity = 3.2;
    fire_light.light.range = 10.0;

    game_scene_runtime.fire_node = fire_node;
    game_scene_runtime.fire_node_runtime_id = fire_node.runtime_id;
    game_scene_runtime.fire_light_node_runtime_id = fire_light_node.runtime_id;
    game_scene_runtime.fire_animation = fire_animation;
    game_scene_runtime.fire_light = fire_light;
}

game_add_model_component :: (
    parent: *Node,
    name: string,
    path: string,
    position: Vector3,
    rotation: Vector3,
    scale_value: Vector3
) -> *Node {
    mesh_node := node_add_node(parent, name);
    mesh_node.local.position = position;
    mesh_node.local.rotation = quaternion_from_euler_xyz(rotation);
    mesh_node.local.scale = scale_value;

    model_component := node_add_component(mesh_node, Model_Component);
    model_component.model_path = copy_string(path);
    model_component.model_resource = asset_ref_acquire_model(*model_component.model_ref, path);
    model_component.model_local_matrix = Matrix4_Identity;

    return mesh_node;
}

#scope_export

game_update_scene_runtime :: (time: float64, camera: *Camera = null) {
    _ = camera;
    if game_scene_runtime.suzanne_node {
        suzanne_position, suzanne_forward := game_sample_suzanne_path(time);
        if game_scene_runtime.suzanne_animation_enabled {
            game_scene_runtime.suzanne_node.local.position = suzanne_position;
            yaw := atan2(suzanne_forward.x, suzanne_forward.z);
            game_scene_runtime.suzanne_node.local.rotation = quaternion_from_euler_xyz(
                .{0.0, yaw + PI, 0.0}
            );
        }
    }

    if game_scene_runtime.teapot_materials.count > 0 {
        teapot_tint := Vector3.{1.0, 1.0, 1.0};
        if game_scene_runtime.teapot_highlight_enabled {
            pulse := cast(float) (0.65 + 0.35 * sin(time * 4.0));
            teapot_tint = .{1.0, 0.8 + 0.2 * pulse, 0.35 + 0.25 * pulse};
        }

        for game_scene_runtime.teapot_materials {
            it.diffuse_map = asset_manager_get_default_texture();
            it.tint_color = teapot_tint;
        }
    }

    if game_scene_runtime.fire_light {
        base_intensity := 3.1;
        flicker_a := cast(float) (0.9 * sin(time * 7.7));
        flicker_b := cast(float) (0.45 * sin(time * 13.3 + 0.7));
        game_scene_runtime.fire_light.light.intensity = base_intensity + flicker_a + flicker_b;

        base_range := 10.0;
        range_flicker := cast(float) (1.25 * sin(time * 6.1 + 0.4) + 0.65 * sin(time * 11.4));
        game_scene_runtime.fire_light.light.range = base_range + range_flicker;
    }
}

game_toggle_picked_node :: (node: *Node) {
    if !node then return;

    if node == game_scene_runtime.suzanne_node {
        game_scene_runtime.suzanne_animation_enabled = !game_scene_runtime.suzanne_animation_enabled;
        return;
    }

    if node == game_scene_runtime.teapot_node || game_node_is_descendant_of(node, game_scene_runtime.teapot_node) {
        game_scene_runtime.teapot_highlight_enabled = !game_scene_runtime.teapot_highlight_enabled;
        return;
    }

    if node == game_scene_runtime.fire_node {
        if game_scene_runtime.fire_animation {
            game_scene_runtime.fire_animation.playing = !game_scene_runtime.fire_animation.playing;
        }
        return;
    }
}

game_clamp_camera_position :: (position: *Vector3) {
    if !position then return;

    position.x = clamp(
        position.x,
        game_scene_runtime.camera_bounds_min.x,
        game_scene_runtime.camera_bounds_max.x
    );
    position.y = clamp(
        position.y,
        game_scene_runtime.camera_bounds_min.y,
        game_scene_runtime.camera_bounds_max.y
    );
    position.z = clamp(
        position.z,
        game_scene_runtime.camera_bounds_min.z,
        game_scene_runtime.camera_bounds_max.z
    );
}

#scope_file

game_collect_teapot_materials :: (instance_node: *Node) {
    if !instance_node then return;

    array_reset(*game_scene_runtime.teapot_materials);
    game_collect_teapot_materials_recursive(instance_node);

    for game_scene_runtime.teapot_materials {
        it.diffuse_map = asset_manager_get_default_texture();
        it.tint_color = .{1.0, 1.0, 1.0};
    }
}

game_collect_teapot_materials_recursive :: (node: *Node) {
    if !node then return;

    model_component := node_get_component(node, Model_Component);
    if model_component && model_component.model_resource {
        for model_component.model_resource.submeshes {
            if it.material {
                array_add(*game_scene_runtime.teapot_materials, it.material);
            }
        }
    }

    mesh_component := node_get_component(node, Static_Mesh_Component);
    if mesh_component && mesh_component.material {
        array_add(*game_scene_runtime.teapot_materials, mesh_component.material);
    }

    for node.children {
        game_collect_teapot_materials_recursive(it);
    }
}

game_sample_suzanne_path :: (time: float64) -> Vector3, Vector3 {
    points := SUZANNE_PATH_CONTROL_POINTS;
    segment_count := points.count;
    path_time := time * 0.25;
    segment_float := path_time * cast(float64) segment_count;
    segment_index := cast(s32) floor(segment_float);
    local_t := cast(float) (segment_float - cast(float64) segment_index);

    p0 := points[(segment_index - 1 + segment_count) % segment_count];
    p1 := points[segment_index % segment_count];
    p2 := points[(segment_index + 1) % segment_count];
    p3 := points[(segment_index + 2) % segment_count];

    position := game_catmull_rom_position(p0, p1, p2, p3, local_t);
    tangent := normalize(game_catmull_rom_tangent(p0, p1, p2, p3, local_t));
    return position, tangent;
}

game_catmull_rom_position :: (
    p0: Vector3,
    p1: Vector3,
    p2: Vector3,
    p3: Vector3,
    t: float
) -> Vector3 {
    t2 := t * t;
    t3 := t2 * t;
    return 0.5 * (
        (2.0 * p1) +
        (-p0 + p2) * t +
        (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
        (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
    );
}

game_catmull_rom_tangent :: (
    p0: Vector3,
    p1: Vector3,
    p2: Vector3,
    p3: Vector3,
    t: float
) -> Vector3 {
    t2 := t * t;
    return 0.5 * (
        (-p0 + p2) +
        (4.0 * p0 - 10.0 * p1 + 8.0 * p2 - 2.0 * p3) * t +
        (-3.0 * p0 + 9.0 * p1 - 9.0 * p2 + 3.0 * p3) * t2
    );
}

game_node_is_descendant_of :: (node: *Node, ancestor: *Node) -> bool {
    if !node || !ancestor then return false;

    current := node;
    while current {
        if current == ancestor then return true;
        current = current.parent;
    }

    return false;
}
