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
