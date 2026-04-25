#scope_export
#import "Basic";
#import "Math";

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

node_add_node :: (parent: *Node, name: string = "New Node") -> *Node {
    node := New(Node);
    node.name   = copy_string(name);
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
    if !node then return null;

    for node.components {
        if it.type == T {
            return cast(*T) it;
        }
    }
    
    return null;
}

node_find_first_component :: (
    node: *Node,
    $T: Type,
    recursive: bool = true
) -> *T {
    if !node then return null;

    component := node_get_component(node, T);
    if component then return component;

    if !recursive then return null;

    for node.children {
        component = node_find_first_component(it, T, true);
        if component then return component;
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

node_destroy :: (node: *Node) {
    if !node then return;

    for node.children {
        node_destroy(it);
    }

    free(node.name);
    for component: node.components {
        free(component);
    }
    array_free(node.components);
    array_free(node.children);

    free(node);
}

node_update_transforms :: (node: *Node, parent_world_matrix: Matrix4) {
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
        node_update_transforms(it, node.world_matrix);
    }
}

node_clone :: (
    node: *Node,
    active_camera_source: *Camera = null,
    active_camera_result: **Camera = null
) -> *Node {
    if !node then return null;

    clone := New(Node);
    clone.name = copy_string(node.name);
    clone.local = node.local;
    clone.world_matrix = node.world_matrix;
    clone.world_position = node.world_position;
    clone.active = node.active;

    for component: node.components {
        component_clone(component, clone, active_camera_source, active_camera_result);
    }

    for child: node.children {
        child_clone := node_clone(child, active_camera_source, active_camera_result);
        child_clone.parent = clone;
        array_add(*clone.children, child_clone);
    }

    return clone;
}
