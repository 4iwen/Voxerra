#scope_file

#import "Basic";
#import "Math";

#scope_export

Component :: struct {
    type: Type;
    node: *Node;
}

Static_Mesh_Component :: struct {
    #as using base: Component;
    base.type = Static_Mesh_Component;
    
    mesh: *Mesh;
    material: *Material;
}

Light_Component :: struct {
    #as using base: Component;
    base.type = Light_Component;
    
    light: Light;
}

Node :: struct {
    name: string;

    // transform
    local: Transform;
    world_matrix: Matrix4;
    world_position: Vector3;

    // hierarchy
    parent: *Node;
    children: [..] *Node;

    components: [..] *Component;

    active: bool = true;
}

node_add_node :: (parent: *Node) -> *Node {
    node := New(Node);
    node.name = "New Node";
    node.active = true;
    node.parent = parent;
    array_add(*parent.children, node);

    return node;
}

node_add_component :: (node: *Node, $T: Type) -> *T {
    component := New(T);
    component.node = node;
    array_add(*node.components, component);

    return component;
}

node_get_component :: (node: *Node, $T: Type) -> *T {
    for node.components {
        if it.type == T {
            return cast(*T) it;
        }
    }
    
    return null;
}

node_remove_component :: (node: *Node, component: *Component) {
    for i: 0..node.components.count-1 {
        if node.components[i] == component {
            array_ordered_remove_by_index(*node.components, i);
            free(component);
            return;
        }
    }
}

Scene :: struct {
    name: string;

    // scene graph
    root: *Node;
    
    // camera
    camera: *Camera;

    // lighting
    lights: *Light_System;
}

scene_create :: (name: string = "") -> *Scene {
    scene := New(Scene);
    scene.name = copy_string(name);
    scene.root.name = "Root";
    scene.root.active = true;

    return scene;
}

scene_destroy :: (scene: *Scene) {
    assert(scene != null, "scene_destroy: scene is null");

    destroy_children(scene.root);
    free(scene.name);
    free(scene);
}

scene_update_transforms :: (scene: *Scene) {
    assert(scene != null, "scene_update_transforms: scene is null");

    update_node_transforms(scene.root, Matrix4_Identity);
}

#scope_file

destroy_children :: (node: *Node) {
    for node.children {
        destroy_children(it);
        free(it.name);
        for component: it.components {
            free(component);
        }
        array_free(it.components);
        free(it);
    }
    array_free(node.children);
}

update_node_transforms :: (node: *Node, parent_world_matrix: Matrix4) {
    if !node.active then return;

    local_matrix := transform_to_matrix(node.local);

    if parent_world_matrix != Matrix4_Identity {
        node.world_matrix = parent_world_matrix * local_matrix;
    } else {
        node.world_matrix = local_matrix;
    }

    node.world_position = Vector3.{
        node.world_matrix._14,
        node.world_matrix._24,
        node.world_matrix._34
    };

    for node.children {
        update_node_transforms(it, node.world_matrix);
    }
}
