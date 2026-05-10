// File:        default_scene.jai
// Author:      Lukáš Bien
// Description: Binds scene-authored demo content and updates its runtime behavior.

#scope_file

#import "Basic";
#import "Math";

#scope_export

SHIP_SCENE_ID :: "ship-small.glb";
TEAPOT_SCENE_ID :: "utah_teapot.obj";
SUZANNE_SCENE_ID :: "suzanne";
FIRE_SCENE_ID :: "fire";
FIRE_LIGHT_SCENE_ID :: "fire_light";

Game_Scene_Runtime :: struct {
    scene: *Scene;

    ship_node: *Node;
    ship_node_runtime_id: u64;
    ship_follower: *Curve_Follower_Component;
    ship_missing_warned: bool;
    ship_follower_missing_warned: bool;

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

// rebind scene-authored nodes after reloads and recreate only the hardcoded
// Suzanne mesh that does not come from the authored scene file.
game_rebind_default_scene_runtime :: (scene: *Scene) {
    if !scene then return;

    teapot_materials := game_scene_runtime.teapot_materials;
    ship_node_runtime_id := game_scene_runtime.ship_node_runtime_id;
    teapot_node_runtime_id := game_scene_runtime.teapot_node_runtime_id;
    fire_node_runtime_id := game_scene_runtime.fire_node_runtime_id;
    fire_light_node_runtime_id := game_scene_runtime.fire_light_node_runtime_id;
    game_scene_runtime = .{};
    game_scene_runtime.teapot_materials = teapot_materials;
    array_reset(*game_scene_runtime.teapot_materials);

    game_scene_runtime.scene = scene;
    game_scene_runtime.ship_node_runtime_id = ship_node_runtime_id;
    game_scene_runtime.teapot_node_runtime_id = teapot_node_runtime_id;
    game_scene_runtime.fire_node_runtime_id = fire_node_runtime_id;
    game_scene_runtime.fire_light_node_runtime_id = fire_light_node_runtime_id;

    if !node_find_by_scene_id(scene.root, SUZANNE_SCENE_ID) {
        game_create_hardcoded_suzanne(scene);
    }

    game_bind_ship_small(scene);
    game_bind_teapot(scene);
    game_bind_fire(scene);
}

#scope_file

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
    node_set_scene_id(suzanne_node, SUZANNE_SCENE_ID);
    suzanne_node.local.position = .{-0.676, 2.077, 0.808};
    suzanne_node.local.scale = .{0.5, 0.5, 0.5};
    suzanne_node.local.rotation = quaternion_from_euler_xyz(.{0, -PI/6, 0});

    mesh_component := node_add_component(suzanne_node, Static_Mesh_Component);
    mesh_component.mesh = mesh;
    mesh_component.material = material;
}

#scope_export

// keep the remaining demo-specific visual reactions in one place while
// movement itself is handled by engine components.
game_update_scene_runtime :: (time: float64, camera: *Camera = null) {
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
        flicker_a := cast(float) (0.5 + 0.5 * sin(time * 7.7));
        flicker_b := cast(float) (0.5 + 0.5 * sin(time * 13.3 + 0.7));
        flicker := clamp(0.65 * flicker_a + 0.35 * flicker_b, 0.0, 1.0);

        game_scene_runtime.fire_light.light.intensity = 1.2 + 2.4 * flicker;
        game_scene_runtime.fire_light.light.range = 6.5 + 4.5 * flicker;
        game_scene_runtime.fire_light.light.color = .{
            1.0,
            0.28 + 0.22 * flicker,
            0.04
        };
    }
}

game_toggle_picked_node :: (node: *Node) {
    if !node then return;

    if node == game_scene_runtime.teapot_node || game_node_is_descendant_of(node, game_scene_runtime.teapot_node) {
        game_scene_runtime.teapot_highlight_enabled = !game_scene_runtime.teapot_highlight_enabled;
        return;
    }

    if node == game_scene_runtime.ship_node || game_node_is_descendant_of(node, game_scene_runtime.ship_node) {
        if game_scene_runtime.ship_follower {
            game_scene_runtime.ship_follower.enabled = !game_scene_runtime.ship_follower.enabled;
        }
        return;
    }

    if node == game_scene_runtime.fire_node || game_node_is_descendant_of(node, game_scene_runtime.fire_node) {
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

// collect every material under the teapot hierarchy so the highlight toggle
// works whether the mesh comes from a direct model or nested submeshes.
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

// bind the authored ship by runtime id first and authored scene id second so
// scene reloads keep working without name-based guessing.
game_bind_ship_small :: (scene: *Scene) {
    if !scene || !scene.root then return;

    game_scene_runtime.ship_node = node_find_by_runtime_or_scene_id(
        scene.root,
        game_scene_runtime.ship_node_runtime_id,
        SHIP_SCENE_ID
    );

    if game_scene_runtime.ship_node {
        game_scene_runtime.ship_node_runtime_id = game_scene_runtime.ship_node.runtime_id;
        game_scene_runtime.ship_follower = node_get_component(
            game_scene_runtime.ship_node,
            Curve_Follower_Component
        );
        if !game_scene_runtime.ship_follower && !game_scene_runtime.ship_follower_missing_warned {
            log_warning("Ship Small is missing Curve_Follower_Component");
            game_scene_runtime.ship_follower_missing_warned = true;
        }
        return;
    }

    if !game_scene_runtime.ship_missing_warned {
        log_warning("Ship Small node not found in scene graph");
        game_scene_runtime.ship_missing_warned = true;
    }
}

game_bind_teapot :: (scene: *Scene) {
    if !scene || !scene.root then return;

    game_scene_runtime.teapot_node = node_find_by_runtime_or_scene_id(
        scene.root,
        game_scene_runtime.teapot_node_runtime_id,
        TEAPOT_SCENE_ID
    );
    if game_scene_runtime.teapot_node {
        game_scene_runtime.teapot_node_runtime_id = game_scene_runtime.teapot_node.runtime_id;
    }
    game_collect_teapot_materials(game_scene_runtime.teapot_node);
}

game_bind_fire :: (scene: *Scene) {
    if !scene || !scene.root then return;

    game_scene_runtime.fire_node = node_find_by_runtime_or_scene_id(
        scene.root,
        game_scene_runtime.fire_node_runtime_id,
        FIRE_SCENE_ID
    );
    if !game_scene_runtime.fire_node then return;

    game_scene_runtime.fire_node_runtime_id = game_scene_runtime.fire_node.runtime_id;
    game_scene_runtime.fire_animation = node_get_component(game_scene_runtime.fire_node, Animated_Sprite_Component);

    fire_light_node := node_find_by_runtime_or_scene_id(
        scene.root,
        game_scene_runtime.fire_light_node_runtime_id,
        FIRE_LIGHT_SCENE_ID
    );
    if fire_light_node {
        game_scene_runtime.fire_light_node_runtime_id = fire_light_node.runtime_id;
    }
    game_scene_runtime.fire_light = node_get_component(fire_light_node, Light_Component);
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
