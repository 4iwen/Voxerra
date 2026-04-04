#scope_file

#import "jai-imgui";
#import "Math";

#scope_export

selected_node: *Node;

scene_graph_draw :: () {
    SetNextWindowSize(ImVec2.{300, 0}, Cond.FirstUseEver);
    if Begin("Scene Graph") {
        if engine_state.current_scene.root != null {
            draw_node(engine_state.current_scene.root);
        } else {
            TextDisabled("No scene loaded");
        }
    }
    End();
} @UI_Window

#scope_file

draw_node :: (node: *Node) {
    flags: TreeNodeFlags = .OpenOnArrow | .SpanAvailWidth | .DrawLinesToNodes | .DefaultOpen;

    if node.children.count == 0 {
        flags |= .Leaf | .NoTreePushOnOpen;
    }

    if node == selected_node {
        flags |= .Selected;
    }

    is_open := TreeNodeEx(temp_c_string(node.name), flags);

    if IsItemClicked() && !IsItemToggledOpen() {
        selected_node = node;
        ui_reset_rotation_state(node.local.rotation);
    }

    if is_open && node.children.count > 0 {
        for node.children {
            draw_node(it);
        }
        TreePop();
    }
}
