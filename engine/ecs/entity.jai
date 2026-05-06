#scope_file

#import "Basic";
#import "Math";

#scope_export

Node :: struct {
    runtime_id: u64;
    scene_id: string;
    name: string;
    instance_path: string;
    inherited_from_instance: bool;

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

node_next_runtime_id: u64 = 1;

node_allocate_runtime_id :: () -> u64 {
    id := node_next_runtime_id;
    node_next_runtime_id += 1;
    return id;
}

node_add_node :: (parent: *Node, name: string = "New Node") -> *Node {
    assert(parent != null, "node_add_node: parent is null");

    node := New(Node);
    node.runtime_id = node_allocate_runtime_id();
    node.name       = copy_string(name);
    node.active     = true;
    node.parent     = parent;
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

node_find_by_runtime_id :: (node: *Node, id: u64) -> *Node {
    if !node then return null;
    if id == 0 then return null;
    if node.runtime_id == id then return node;

    for node.children {
        found := node_find_by_runtime_id(it, id);
        if found then return found;
    }

    return null;
}

node_remove_component :: (node: *Node, component: *Component) {
    for i: 0..node.components.count-1 {
        if node.components[i] == component {
            array_ordered_remove_by_index(*node.components, i);
            component_destroy(component);
            return;
        }
    }
}

node_set_name :: (node: *Node, name: string) {
    if !node then return;
    new_name := name;
    if !new_name || new_name.count == 0 {
        new_name = "Node";
    }

    free(node.name);
    node.name = copy_string(new_name);
}

node_is_ancestor_of :: (ancestor: *Node, node: *Node) -> bool {
    if !ancestor || !node then return false;

    current := node.parent;
    while current {
        if current == ancestor then return true;
        current = current.parent;
    }

    return false;
}

node_detach_from_parent :: (node: *Node) -> bool {
    if !node || !node.parent then return false;

    parent := node.parent;
    for child: parent.children {
        if child == node {
            array_ordered_remove_by_index(*parent.children, it_index);
            node.parent = null;
            return true;
        }
    }

    return false;
}

node_reparent :: (node: *Node, new_parent: *Node) -> bool {
    if !node || !new_parent then return false;
    if node == new_parent then return false;
    if !node.parent then return false;
    if node_is_ancestor_of(node, new_parent) then return false;
    if !node_detach_from_parent(node) then return false;

    node.parent = new_parent;
    array_add(*new_parent.children, node);
    return true;
}

node_reparent_at :: (node: *Node, new_parent: *Node, child_index: s64) -> bool {
    if !node || !new_parent then return false;
    if node == new_parent then return false;
    if !node.parent then return false;
    if node_is_ancestor_of(node, new_parent) then return false;

    old_parent := node.parent;
    old_index: s64 = -1;
    for child: old_parent.children {
        if child == node {
            old_index = cast(s64) it_index;
            break;
        }
    }
    if old_index < 0 then return false;

    insert_index := clamp(child_index, 0, cast(s64) new_parent.children.count);
    if old_parent == new_parent && old_index < insert_index {
        insert_index -= 1;
    }

    array_ordered_remove_by_index(*old_parent.children, old_index);
    node.parent = new_parent;
    array_insert_at(*new_parent.children, node, insert_index);
    return true;
}

node_move_in_parent :: (node: *Node, offset: s32) -> bool {
    if !node || !node.parent || offset == 0 then return false;

    parent := node.parent;
    for child: parent.children {
        if child != node then continue;

        old_index := cast(s64) it_index;
        new_index := clamp(old_index + cast(s64) offset, 0, cast(s64) parent.children.count - 1);
        if new_index == old_index then return false;

        other := parent.children[new_index];
        parent.children[new_index] = node;
        parent.children[old_index] = other;
        return true;
    }

    return false;
}

node_destroy :: (node: *Node) {
    if !node then return;

    for node.children {
        node_destroy(it);
    }

    free(node.scene_id);
    free(node.name);
    free(node.instance_path);
    for component: node.components {
        component_destroy(component);
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
    clone.runtime_id = node_allocate_runtime_id();
    clone.scene_id = copy_string(node.scene_id);
    clone.name = copy_string(node.name);
    clone.instance_path = copy_string(node.instance_path);
    clone.inherited_from_instance = node.inherited_from_instance;
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

node_set_scene_id :: (node: *Node, scene_id: string) {
    if !node then return;

    free(node.scene_id);
    node.scene_id = copy_string(scene_id);
}

node_find_by_scene_id :: (node: *Node, scene_id: string) -> *Node {
    if !node then return null;
    if !scene_id then return null;
    if node.scene_id == scene_id then return node;

    for node.children {
        found := node_find_by_scene_id(it, scene_id);
        if found then return found;
    }

    return null;
}

node_find_by_runtime_or_scene_id :: (node: *Node, runtime_id: u64, scene_id: string) -> *Node {
    found := node_find_by_runtime_id(node, runtime_id);
    if found then return found;

    return node_find_by_scene_id(node, scene_id);
}

node_find_authored_by_scene_id :: (node: *Node, scene_id: string) -> *Node {
    if !node then return null;
    if !scene_id then return null;
    if !node.inherited_from_instance && node.scene_id == scene_id then return node;

    for node.children {
        found := node_find_authored_by_scene_id(it, scene_id);
        if found then return found;
    }

    return null;
}

node_set_instance_path :: (node: *Node, instance_path: string) {
    if !node then return;

    free(node.instance_path);
    node.instance_path = copy_string(instance_path);
}

node_mark_inherited_from_instance :: (node: *Node) {
    if !node then return;

    node.inherited_from_instance = true;

    for node.children {
        node_mark_inherited_from_instance(it);
    }
}
