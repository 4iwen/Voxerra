// File:        node_hierarchy.jai
// Author:      Lukáš Bien
// Description: Draws the scene hierarchy tree and handles node reordering and parenting.

#scope_file

#import "jai-imgui";
#import "Math";

#scope_export

node_hierarchy_draw :: () {
    editor_validate_selection();

    SetNextWindowSize(ImVec2.{300, 0}, Cond.FirstUseEver);
    if Begin(UI_Icon_Window_Title(ICON_FA_SITEMAP, "Node Hierarchy", "Node Hierarchy")) {
        if engine_state.current_scene && engine_state.current_scene.root != null {
            parent := selected_node;
            if !editor_node_can_add_child(parent) {
                parent = engine_state.current_scene.root;
            }
            BeginDisabled(!editor_node_can_add_child(parent));
            if Button(UI_Icon_Label(ICON_FA_CIRCLE_PLUS, "Add Node"), ImVec2.{-1, 24}) {
                editor_add_child_node(parent);
            }
            EndDisabled();
            Separator();
            draw_node(engine_state.current_scene.root);
        } else {
            TextDisabled("No scene loaded");
        }
    }
    End();

    hierarchy_apply_pending_operation();
} @UI_Window

#scope_file

EDITOR_NODE_PAYLOAD :: "ENGINE_NODE";

Node_Drop_Mode :: enum {
    CHILD;
    BEFORE;
    AFTER;
}

Hierarchy_Pending_Operation_Kind :: enum {
    NONE;
    ADD_CHILD;
    DELETE;
    MOVE_OFFSET;
    DROP_NODE;
    DROP_MODEL;
    DROP_SCENE;
    DROP_TEXTURE;
    OPEN_SCENE;
}

Hierarchy_Pending_Operation :: struct {
    kind: Hierarchy_Pending_Operation_Kind;
    source_runtime_id: u64;
    target_runtime_id: u64;
    offset: s32;
    drop_mode: Node_Drop_Mode;
    path: string;
}

hierarchy_pending_operation: Hierarchy_Pending_Operation;

draw_node :: (node: *Node) {
    if node.inherited_from_instance && !editor_is_playing() {
        return;
    }

    PushID(node);
    defer PopID();

    flags: TreeNodeFlags = .OpenOnArrow | .SpanAvailWidth | .DrawLinesToNodes | .DefaultOpen;
    is_scene_instance := node.instance_path.count > 0;
    had_children := node.children.count > 0;
    pushed_tree := had_children && !is_scene_instance;

    if !pushed_tree {
        flags |= .Leaf | .NoTreePushOnOpen;
    }

    if node == selected_node {
        flags |= .Selected;
    }

    is_open := TreeNodeEx(temp_c_string(node.name), flags);

    if IsItemClicked() && !IsItemToggledOpen() {
        editor_select_node(node);
    }

    if BeginPopupContextItem("node_context") {
        if node.instance_path {
            if MenuItem(UI_Icon_Label(ICON_FA_FOLDER_OPEN, "Open Source Scene")) {
                hierarchy_queue_open_scene(node.instance_path);
            }
        }

        if MenuItem(UI_Icon_Label(ICON_FA_CIRCLE_PLUS, "Add Child Node"), enabled = editor_node_can_add_child(node)) {
            hierarchy_queue_target_operation(.ADD_CHILD, node);
        }
        if MenuItem(UI_Icon_Label(ICON_FA_ARROW_UP, "Move Up"), enabled = editor_node_can_move(node)) {
            hierarchy_queue_move_offset(node, -1);
        }
        if MenuItem(UI_Icon_Label(ICON_FA_ARROW_DOWN, "Move Down"), enabled = editor_node_can_move(node)) {
            hierarchy_queue_move_offset(node, 1);
        }
        if MenuItem(UI_Icon_Label(ICON_FA_TRASH, "Delete"), enabled = editor_node_can_delete(node)) {
            hierarchy_queue_target_operation(.DELETE, node);
        }
        EndPopup();
    }

    draw_node_drag_source(node);
    draw_node_drop_target(node);

    if is_open && pushed_tree {
        child_index: s64 = 0;
        while child_index < node.children.count {
            child := node.children[child_index];
            draw_node(child);

            if child_index < node.children.count && node.children[child_index] == child {
                child_index += 1;
            }
        }
        TreePop();
    }
}

draw_node_drag_source :: (node: *Node) {
    if !node || !node.parent || node.inherited_from_instance then return;

    if BeginDragDropSource() {
        runtime_id := node.runtime_id;
        SetDragDropPayload(
            temp_c_string(EDITOR_NODE_PAYLOAD),
            *runtime_id,
            size_of(u64)
        );
        Text("Move Node");
        TextUnformatted(node.name);
        EndDragDropSource();
    }
}

draw_node_drop_target :: (node: *Node) {
    if !node then return;

    row_min := GetItemRectMin();
    row_max := GetItemRectMax();
    drop_mode := node_drop_mode_from_row(node, row_min, row_max);

    if BeginDragDropTarget() {
        flags := DragDropFlags.AcceptBeforeDelivery | .AcceptNoDrawDefaultRect;

        asset_payload := AcceptDragDropPayload(temp_c_string(EDITOR_ASSET_PAYLOAD), flags);
        if asset_payload && asset_payload.Preview {
            draw_node_drop_preview(row_min, row_max, drop_mode);
        }
        if asset_payload && asset_payload.Delivery {
            dropped_asset := editor_asset_payload_to_drop(asset_payload);
            if dropped_asset.path {
                drop_asset_on_node(node, drop_mode, dropped_asset);
            }
            editor_asset_drop_destroy(*dropped_asset);
        }

        node_payload := AcceptDragDropPayload(temp_c_string(EDITOR_NODE_PAYLOAD), flags);
        if node_payload && node_payload.Preview {
            draw_node_drop_preview(row_min, row_max, drop_mode);
        }
        if node_payload && node_payload.Delivery && node_payload.DataSize == size_of(u64) {
            runtime_id := (cast(*u64) node_payload.Data).*;
            scene := editor_get_active_scene();
            dropped_node := ifx scene && scene.root then node_find_by_runtime_id(scene.root, runtime_id) else null;
            if dropped_node {
                drop_node_on_node(dropped_node, node, drop_mode);
            }
        }

        EndDragDropTarget();
    }
}

node_drop_mode_from_row :: (node: *Node, row_min: ImVec2, row_max: ImVec2) -> Node_Drop_Mode {
    if !node || !node.parent then return .CHILD;

    mouse := GetMousePos();
    row_height := max(row_max.y - row_min.y, 1.0);
    sibling_zone := min(row_height * 0.25, 6.0);

    if mouse.y <= row_min.y + sibling_zone then return .BEFORE;
    if mouse.y >= row_max.y - sibling_zone then return .AFTER;
    return .CHILD;
}

draw_node_drop_preview :: (row_min: ImVec2, row_max: ImVec2, mode: Node_Drop_Mode) {
    draw_list := GetWindowDrawList();
    color := GetColorU32(Col.DragDropTarget);

    if mode == .CHILD {
        ImDrawList.AddRect(draw_list, row_min, row_max, color, 0.0, .None, 1.5);
        return;
    }

    y := ifx mode == .BEFORE then row_min.y else row_max.y;
    ImDrawList.AddLine(
        draw_list,
        .{row_min.x, y},
        .{row_max.x, y},
        color,
        2.0
    );
}

drop_node_on_node :: (dropped_node: *Node, target: *Node, mode: Node_Drop_Mode) -> bool {
    if !dropped_node || !target then return false;
    if dropped_node == target then return false;

    hierarchy_queue_node_drop(dropped_node, target, mode);
    return true;
}

drop_asset_on_node :: (
    target: *Node,
    mode: Node_Drop_Mode,
    asset: Editor_Asset_Drop
) -> bool {
    if !target || !asset.path then return false;

    if asset.type == .MODEL {
        hierarchy_queue_model_drop(target, mode, asset.path);
        return true;
    }
    if asset.type == .SCENE {
        hierarchy_queue_scene_drop(target, mode, asset.path);
        return true;
    }
    if asset.type == .TEXTURE {
        hierarchy_queue_texture_drop(target, mode, asset.path);
        return true;
    }

    return false;
}

node_index_in_parent :: (node: *Node) -> s64 {
    if !node || !node.parent then return -1;

    for child: node.parent.children {
        if child == node then return cast(s64) it_index;
    }

    return -1;
}

hierarchy_queue_target_operation :: (
    kind: Hierarchy_Pending_Operation_Kind,
    target: *Node
) {
    if !target then return;

    hierarchy_clear_pending_operation();
    hierarchy_pending_operation.kind = kind;
    hierarchy_pending_operation.target_runtime_id = target.runtime_id;
}

hierarchy_queue_move_offset :: (node: *Node, offset: s32) {
    if !node then return;

    hierarchy_clear_pending_operation();
    hierarchy_pending_operation.kind = .MOVE_OFFSET;
    hierarchy_pending_operation.target_runtime_id = node.runtime_id;
    hierarchy_pending_operation.offset = offset;
}

hierarchy_queue_node_drop :: (
    source: *Node,
    target: *Node,
    mode: Node_Drop_Mode
) {
    if !source || !target then return;

    hierarchy_clear_pending_operation();
    hierarchy_pending_operation.kind = .DROP_NODE;
    hierarchy_pending_operation.source_runtime_id = source.runtime_id;
    hierarchy_pending_operation.target_runtime_id = target.runtime_id;
    hierarchy_pending_operation.drop_mode = mode;
}

hierarchy_queue_model_drop :: (
    target: *Node,
    mode: Node_Drop_Mode,
    model_path: string
) {
    if !target || !model_path then return;

    hierarchy_clear_pending_operation();
    hierarchy_pending_operation.kind = .DROP_MODEL;
    hierarchy_pending_operation.target_runtime_id = target.runtime_id;
    hierarchy_pending_operation.drop_mode = mode;
    hierarchy_pending_operation.path = copy_string(model_path);
}

hierarchy_queue_scene_drop :: (
    target: *Node,
    mode: Node_Drop_Mode,
    scene_path: string
) {
    if !target || !scene_path then return;

    hierarchy_clear_pending_operation();
    hierarchy_pending_operation.kind = .DROP_SCENE;
    hierarchy_pending_operation.target_runtime_id = target.runtime_id;
    hierarchy_pending_operation.drop_mode = mode;
    hierarchy_pending_operation.path = copy_string(scene_path);
}

hierarchy_queue_texture_drop :: (
    target: *Node,
    mode: Node_Drop_Mode,
    texture_path: string
) {
    if !target || !texture_path then return;

    hierarchy_clear_pending_operation();
    hierarchy_pending_operation.kind = .DROP_TEXTURE;
    hierarchy_pending_operation.target_runtime_id = target.runtime_id;
    hierarchy_pending_operation.drop_mode = mode;
    hierarchy_pending_operation.path = copy_string(texture_path);
}

hierarchy_queue_open_scene :: (path: string) {
    if !path then return;

    hierarchy_clear_pending_operation();
    hierarchy_pending_operation.kind = .OPEN_SCENE;
    hierarchy_pending_operation.path = copy_string(path);
}

hierarchy_apply_pending_operation :: () {
    if hierarchy_pending_operation.kind == .NONE then return;

    operation := hierarchy_pending_operation;
    hierarchy_pending_operation = .{};
    defer hierarchy_operation_destroy(*operation);

    if operation.kind == .OPEN_SCENE {
        editor_open_scene(operation.path);
        return;
    }

    scene := editor_get_active_scene();
    if !scene || !scene.root then return;

    target := node_find_by_runtime_id(scene.root, operation.target_runtime_id);

    if operation.kind == .ADD_CHILD {
        if target then editor_add_child_node(target);
        return;
    }

    if operation.kind == .DELETE {
        if target then editor_delete_node(target);
        return;
    }

    if operation.kind == .MOVE_OFFSET {
        if target then editor_move_node_in_parent(target, operation.offset);
        return;
    }

    if operation.kind == .DROP_MODEL {
        hierarchy_apply_model_drop(target, operation.drop_mode, operation.path);
        return;
    }

    if operation.kind == .DROP_SCENE {
        hierarchy_apply_scene_drop(target, operation.drop_mode, operation.path);
        return;
    }

    if operation.kind == .DROP_TEXTURE {
        hierarchy_apply_texture_drop(target, operation.drop_mode, operation.path);
        return;
    }

    if operation.kind == .DROP_NODE {
        source := node_find_by_runtime_id(scene.root, operation.source_runtime_id);
        hierarchy_apply_node_drop(source, target, operation.drop_mode);
        return;
    }
}

hierarchy_apply_model_drop :: (
    target: *Node,
    mode: Node_Drop_Mode,
    model_path: string
) -> bool {
    if !target || !model_path then return false;

    if mode == .CHILD || !target.parent {
        return editor_create_model_node_from_asset(target, model_path) != null;
    }

    index := node_index_in_parent(target);
    if index < 0 then return false;
    if mode == .AFTER then index += 1;

    new_node := editor_create_model_node_from_asset(target.parent, model_path);
    if !new_node then return false;
    return editor_move_node_to_parent_index(new_node, target.parent, index);
}

hierarchy_apply_scene_drop :: (
    target: *Node,
    mode: Node_Drop_Mode,
    scene_path: string
) -> bool {
    if !target || !scene_path then return false;

    if mode == .CHILD || !target.parent {
        return editor_create_scene_instance_from_asset(target, scene_path) != null;
    }

    index := node_index_in_parent(target);
    if index < 0 then return false;
    if mode == .AFTER then index += 1;

    new_node := editor_create_scene_instance_from_asset(target.parent, scene_path);
    if !new_node then return false;
    return editor_move_node_to_parent_index(new_node, target.parent, index);
}

hierarchy_apply_texture_drop :: (
    target: *Node,
    mode: Node_Drop_Mode,
    texture_path: string
) -> bool {
    if !target || !texture_path then return false;

    if mode == .CHILD || !target.parent {
        return editor_create_sprite_node_from_asset(target, texture_path) != null;
    }

    index := node_index_in_parent(target);
    if index < 0 then return false;
    if mode == .AFTER then index += 1;

    new_node := editor_create_sprite_node_from_asset(target.parent, texture_path);
    if !new_node then return false;
    return editor_move_node_to_parent_index(new_node, target.parent, index);
}

hierarchy_apply_node_drop :: (
    source: *Node,
    target: *Node,
    mode: Node_Drop_Mode
) -> bool {
    if !source || !target then return false;
    if source == target then return false;

    if mode == .CHILD || !target.parent {
        return editor_reparent_node(source, target);
    }

    index := node_index_in_parent(target);
    if index < 0 then return false;
    if mode == .AFTER then index += 1;

    return editor_move_node_to_parent_index(source, target.parent, index);
}

hierarchy_clear_pending_operation :: () {
    hierarchy_operation_destroy(*hierarchy_pending_operation);
    hierarchy_pending_operation = .{};
}

hierarchy_operation_destroy :: (operation: *Hierarchy_Pending_Operation) {
    if !operation then return;
    free(operation.path);
    operation.path = "";
}
