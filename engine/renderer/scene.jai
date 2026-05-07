// File:        scene.jai
// Author:      Lukáš Bien
// Description: Owns scene lifetime, active camera state, and scene-wide transform updates.

#scope_file

#import "Basic";
#import "Math";

#scope_export

Scene_Environment :: struct {
    clear_color: Vector4 = .{0.08, 0.08, 0.09, 1.0}; @Color
    ambient_color: Vector3 = .{0.5, 0.5, 0.5}; @Color
    skybox_enabled: bool = true;
    skybox_cubemap_guid: string;
    skybox_cubemap_path: string;
    fog_resolve_enabled: bool;
    fog_enabled: bool;
    fog_color: Vector4 = .{0.72, 0.78, 0.86, 1.0}; @Color
    fog_near: float = 12.0;
    fog_far: float = 40.0;
}

Scene :: struct {
    name: string;
    source_path: string;

    // graph
    root: *Node;
    
    // camera
    camera: *Camera;

    // lights
    lights: *Light_System;
    
    ambient_color: Vector3 = .{127.0 / 255.0, 127.0 / 255.0, 127.0 / 255.0}; @Color
    environment: Scene_Environment;
}

scene_create :: (name: string = "") -> *Scene {
    scene := New(Scene);
    scene.name = copy_string(name);

    scene.root = New(Node);
    scene.root.runtime_id = node_allocate_runtime_id();
    scene.root.scene_id   = copy_string("root");
    scene.root.name       = copy_string("Root");
    scene.root.active     = true;

    return scene;
}

scene_destroy :: (scene: *Scene) {
    assert(scene != null, "scene_destroy: scene is null");

    node_destroy(scene.root);
    free(scene.name);
    free(scene.source_path);
    free(scene.environment.skybox_cubemap_guid);
    free(scene.environment.skybox_cubemap_path);
    free(scene);
}

scene_update_transforms :: (scene: *Scene) {
    assert(scene != null, "scene_update_transforms: scene is null");

    node_update_transforms(scene.root, Matrix4_Identity);
}

scene_update_curve_followers :: (scene: *Scene, delta_time: float64) {
    assert(scene != null, "scene_update_curve_followers: scene is null");

    scene_update_curve_followers_recursive(scene.root, scene.root, delta_time);
}

scene_update_cameras :: (scene: *Scene) {
    assert(scene != null, "scene_update_cameras: scene is null");

    scene_update_cameras_recursive(scene.root);
}

scene_clone :: (scene: *Scene) -> *Scene {
    assert(scene != null, "scene_clone: scene is null");

    clone := scene_create(scene.name);
    clone.source_path = copy_string(scene.source_path);
    clone.ambient_color = scene.ambient_color;
    clone.environment = scene.environment;
    clone.environment.skybox_cubemap_guid = copy_string(scene.environment.skybox_cubemap_guid);
    clone.environment.skybox_cubemap_path = copy_string(scene.environment.skybox_cubemap_path);

    node_destroy(clone.root);
    clone.root = node_clone(scene.root, scene.camera, *clone.camera);

    return clone;
}

scene_find_first_component :: (scene: *Scene, $T: Type) -> *T {
    if !scene then return null;
    return node_find_first_component(scene.root, T);
}

scene_get_active_camera :: (scene: *Scene) -> *Camera {
    if !scene then return null;
    return scene.camera;
}

scene_set_active_camera :: (scene: *Scene, component: *Camera_Component) {
    assert(scene != null, "scene_set_active_camera: scene is null");

    if component {
        scene.camera = *component.camera;
    } else {
        scene.camera = null;
    }
}

#scope_file

scene_update_curve_followers_recursive :: (root: *Node, node: *Node, delta_time: float64) {
    if !root || !node then return;

    follower := node_get_curve_follower_component(node);
    if follower {
        scene_update_curve_follower(root, follower, delta_time);
    }

    for child: node.children {
        scene_update_curve_followers_recursive(root, child, delta_time);
    }
}

scene_update_curve_follower :: (root: *Node, follower: *Curve_Follower_Component, delta_time: float64) {
    if !root || !follower || !follower.node || !follower.enabled then return;

    curve_node := node_find_by_runtime_or_scene_id(
        root,
        follower.curve_node_runtime_id,
        follower.curve_node_scene_id
    );
    if !curve_node then return;

    curve := node_get_curve_component(curve_node);
    if !curve || curve.points.count < 2 then return;

    follower.curve_node_runtime_id = curve_node.runtime_id;

    if delta_time != 0.0 {
        follower.progress += delta_time * cast(float64) follower.speed;
    }

    normalized_time := cast(float64) follower.start_offset + follower.progress;
    if follower.loop {
        normalized_time -= floor(normalized_time);
        if normalized_time < 0.0 {
            normalized_time += 1.0;
        }
    } else {
        normalized_time = clamp(normalized_time, 0.0, 1.0);
        follower.progress = normalized_time - cast(float64) follower.start_offset;
    }

    segment_count := curve_segment_count(cast(s32) curve.points.count, curve.closed);
    if segment_count <= 0 then return;

    segment_float := normalized_time * cast(float64) segment_count;
    segment_index := cast(s32) floor(segment_float);
    if segment_index >= segment_count {
        segment_index = segment_count - 1;
        segment_float = cast(float64) segment_index + 1.0;
    }

    local_t := cast(float) (segment_float - cast(float64) segment_index);
    if segment_index == segment_count - 1 && local_t >= 1.0 {
        local_t = 0.999999;
    }

    curve_position := curve_catmull_rom_segment_position(
        curve.points,
        curve.closed,
        segment_index,
        local_t
    );
    curve_tangent := curve_catmull_rom_segment_tangent(
        curve.points,
        curve.closed,
        segment_index,
        local_t
    );

    world_position := (curve_node.world_matrix *
        Vector4.{curve_position.x, curve_position.y, curve_position.z, 1.0}).xyz;
    world_tangent := (curve_node.world_matrix *
        Vector4.{curve_tangent.x, curve_tangent.y, curve_tangent.z, 0.0}).xyz;
    if dot(world_tangent, world_tangent) <= 0.000001 {
        world_tangent = .{0, 0, 1};
    } else {
        world_tangent = normalize(world_tangent);
    }

    if follower.node.parent {
        success, parent_inverse := inverse(follower.node.parent.world_matrix);
        if success {
            follower.node.local.position = (parent_inverse *
                Vector4.{world_position.x, world_position.y, world_position.z, 1.0}).xyz;
        } else {
            follower.node.local.position = world_position;
        }
    } else {
        follower.node.local.position = world_position;
    }

    if follower.orientation == .NONE then return;

    yaw := atan2(world_tangent.x, world_tangent.z) + follower.yaw_offset;
    rotation_euler := Vector3.{0.0, yaw, 0.0};
    if follower.orientation == .FULL {
        horizontal_length := length(Vector2.{world_tangent.x, world_tangent.z});
        rotation_euler.x = atan2(world_tangent.y, horizontal_length);
    }

    world_rotation := quaternion_from_euler_xyz(rotation_euler);
    local_rotation_matrix := rotation_matrix(Matrix4, world_rotation);
    if follower.node.parent {
        success, parent_inverse := inverse(follower.node.parent.world_matrix);
        if success {
            local_rotation_matrix = parent_inverse * local_rotation_matrix;
        }
    }

    follower.node.local.rotation = transform_extract_rotation(local_rotation_matrix);
}

scene_update_cameras_recursive :: (node: *Node) {
    if !node then return;

    camera_component := node_get_component(node, Camera_Component);
    if camera_component {
        camera_component.camera.position = node.world_position;
        camera_update_vectors(*camera_component.camera);
    }

    for child: node.children {
        scene_update_cameras_recursive(child);
    }
}
