#scope_file

#import "Basic";
#import "Math";

#scope_export

Scene :: struct {
    name: string;

    // graph
    root: *Node;
    
    // camera
    camera: *Camera;

    // lights
    lights: *Light_System;
}

scene_create :: (name: string = "") -> *Scene {
    scene := New(Scene);
    scene.name = copy_string(name);

    scene.root = New(Node);
    scene.root.name   = copy_string("Root");
    scene.root.active = true;

    return scene;
}

scene_destroy :: (scene: *Scene) {
    assert(scene != null, "scene_destroy: scene is null");

    node_destroy(scene.root);
    free(scene.name);
    free(scene);
}

scene_update_transforms :: (scene: *Scene) {
    assert(scene != null, "scene_update_transforms: scene is null");

    node_update_transforms(scene.root, Matrix4_Identity);
}

scene_clone :: (scene: *Scene) -> *Scene {
    assert(scene != null, "scene_clone: scene is null");

    clone := scene_create(scene.name);

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
