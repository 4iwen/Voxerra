#scope_file

#import "Basic";
#import "Math";

#scope_export

game_build_default_scene :: (scene: *Scene) {
    assert(scene != null, "game_build_default_scene: scene is null");

    scene.ambient_color = .{0.16, 0.18, 0.22};

    game_load_default_scene_assets();
    game_create_hardcoded_suzanne(scene);
    game_create_teapot(scene);
    game_create_required_lights(scene);
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
    texture := asset_manager_load_texture(
        "game/assets/textures/forest.png",
        DEFAULT_TEXTURE_SPEC,
        false
    );

    mesh := game_create_suzanne_mesh();
    material := material_create("Suzanne");
    material.shader = shader;
    material.diffuse_map = texture;
    material.shininess = 48.0;

    suzanne_node := node_add_node(scene.root, "Suzanne");
    suzanne_node.local.position = .{-2.2, 1.45, -12.0};
    suzanne_node.local.scale = .{1.55, 1.55, 1.55};
    suzanne_node.local.rotation = quaternion_from_euler_xyz(.{0.0, 0.35, 0.0});

    mesh_component := node_add_component(suzanne_node, Static_Mesh_Component);
    mesh_component.mesh = mesh;
    mesh_component.material = material;
}

game_create_teapot :: (scene: *Scene) {
    game_add_model_instance_height(
        scene.root,
        "Utah Teapot",
        "game/assets/models/utah_teapot.obj",
        .{2.2, 0.0, -12.0},
        .{0.0, -0.45, 0.0},
        2.7
    );
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

Model_Metrics :: struct {
    model: *Model;
    bounds_min: Vector3;
    bounds_max: Vector3;
    bounds_center: Vector3;
    extent: Vector3;
}

game_measure_model :: (path: string) -> Model_Metrics, bool {
    metrics: Model_Metrics;

    model := asset_manager_load_model(path);
    if !model {
        log_error("Failed to load default scene model: %", path);
        return metrics, false;
    }

    bounds_min := Vector3.{1.0e30, 1.0e30, 1.0e30};
    bounds_max := Vector3.{-1.0e30, -1.0e30, -1.0e30};

    for model.submeshes {
        mesh := it.mesh;
        bounds_min.x = min(bounds_min.x, mesh.bounds_min.x);
        bounds_min.y = min(bounds_min.y, mesh.bounds_min.y);
        bounds_min.z = min(bounds_min.z, mesh.bounds_min.z);
        bounds_max.x = max(bounds_max.x, mesh.bounds_max.x);
        bounds_max.y = max(bounds_max.y, mesh.bounds_max.y);
        bounds_max.z = max(bounds_max.z, mesh.bounds_max.z);
    }

    metrics.model = model;
    metrics.bounds_min = bounds_min;
    metrics.bounds_max = bounds_max;
    metrics.bounds_center = (bounds_min + bounds_max) * 0.5;
    metrics.extent = bounds_max - bounds_min;

    return metrics, true;
}

game_add_model_instance_measured :: (
    parent: *Node,
    name: string,
    metrics: Model_Metrics,
    position: Vector3,
    rotation: Vector3,
    uniform_scale: float
) {
    instance_node := node_add_node(parent, name);
    instance_node.local.position = position;
    instance_node.local.rotation = quaternion_from_euler_xyz(rotation);
    instance_node.local.scale = .{uniform_scale, uniform_scale, uniform_scale};

    model_root := node_add_node(instance_node, "Model");
    model_root.local.position = .{
        -metrics.bounds_center.x,
        -metrics.bounds_min.y,
        -metrics.bounds_center.z
    };

    for metrics.model.submeshes {
        sub_node := node_add_node(model_root, "mesh");
        mesh_component := node_add_component(sub_node, Static_Mesh_Component);
        mesh_component.mesh = it.mesh;
        mesh_component.material = it.material;
    }
}

game_add_model_instance_height :: (
    parent: *Node,
    name: string,
    path: string,
    position: Vector3,
    rotation: Vector3,
    target_height: float
) {
    metrics, ok := game_measure_model(path);
    if !ok then return;

    height := max(metrics.extent.y, 0.0001);
    uniform_scale := target_height / height;
    game_add_model_instance_measured(parent, name, metrics, position, rotation, uniform_scale);
}
