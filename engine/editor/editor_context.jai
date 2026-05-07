// File:        editor_context.jai
// Author:      Lukáš Bien
// Description: Owns editor scene tabs, selection state, scene editing
//              operations, and editor render mode state.

#scope_file

#import "Basic";
#import "String";
#import "Math";
#import "File";

#scope_export

EDITOR_VIEW_CAMERA_DEFAULT_DISTANCE :: 12.0;
EDITOR_VIEW_CAMERA_MIN_DISTANCE     :: 0.2;
EDITOR_VIEW_CAMERA_MAX_DISTANCE     :: 500.0;
EDITOR_VIEW_CAMERA_COORDINATE_LIMIT :: 100000.0;

Editor_Node_Handle :: struct {
    runtime_id: u64;
    scene_id: string;
}

Editor_View_Camera :: struct {
    camera: Camera;
    focus: Vector3 = .{0.0, 0.0, 0.0};
    distance: float = EDITOR_VIEW_CAMERA_DEFAULT_DISTANCE;
    yaw: float = -90.0;
    pitch: float = -18.0;
    initialized: bool;
}

Editor_Render_Mode :: enum u32 {
    LIT;
    UNLIT;
    WIREFRAME;
    LIGHTING_ONLY;
    ALBEDO;
}

Editor_Scene_Tab :: struct {
    scene: *Scene;
    path: string;
    title: string;
    dirty: bool;
    selection: Editor_Node_Handle;
    view_camera: Editor_View_Camera;
}

Editor_Context :: struct {
    tabs: [..] Editor_Scene_Tab;
    active_tab_index: s32 = -1;
    requested_tab_selection_index: s32 = -1;
    pending_close_tab_index: s32 = -1;
    project_asset_root: string;
    render_mode: Editor_Render_Mode;
}

editor_context: Editor_Context;
selected_node: *Node;

editor_context_init :: (project: Project_Descriptor) {
    editor_context = .{};
    editor_context.active_tab_index = -1;
    editor_context.requested_tab_selection_index = -1;
    editor_context.pending_close_tab_index = -1;
    editor_context.project_asset_root = copy_string(project.asset_root);
    editor_context.render_mode = .LIT;
    editor_curve_init();
}

editor_context_shutdown :: () {
    for * editor_context.tabs {
        editor_scene_tab_destroy(it);
    }
    array_free(editor_context.tabs);
    free(editor_context.project_asset_root);
    editor_context = .{};
    editor_context.active_tab_index = -1;
    editor_context.requested_tab_selection_index = -1;
    editor_context.pending_close_tab_index = -1;
    selected_node = null;
    engine_state.current_scene = null;
    editor_curve_shutdown();
}

editor_create_scene_tab :: (path: string) -> bool {
    if !path {
        log_warning("Cannot create scene tab: empty path");
        return false;
    }
    if editor_is_playing() {
        log_warning("Cannot create scene tab while play mode is running");
        return false;
    }

    for * tab, index: editor_context.tabs {
        if tab.path == path {
            log_warning("Cannot create scene tab: tab already open");
            return false;
        }
    }

    if file_exists(path) {
        log_warning("Cannot create scene tab: file already exists");
        return false;
    }

    scene := scene_create(path_filename(path));
    scene.source_path = copy_string(path);

    ok := scene_save_toml(scene, path);
    if !ok {
        log_error("Failed to save new scene to disk: %", path);
        scene_destroy(scene);
        return false;
    }

    metadata := asset_manager_ensure_metadata(path, .SCENE);

    tab: Editor_Scene_Tab;
    tab.scene = scene;
    tab.path = copy_string(path);
    tab.title = copy_string(path_filename(path));
    tab.view_camera = editor_view_camera_create();

    asset_ref: Asset_Ref;
    asset_ref_acquire_scene(*asset_ref, path, metadata.guid);
    asset_ref_release(*asset_ref);

    array_add(*editor_context.tabs, tab);
    new_index := cast(s32) editor_context.tabs.count - 1;
    editor_set_active_scene_tab(new_index);
    editor_propagate_scene_changes_from_tab(new_index);
    return true;
}

editor_open_scene_tab :: (path: string) -> bool {
    if !path {
        log_warning("Cannot open scene tab: empty path");
        return false;
    }
    if editor_is_playing() {
        log_warning("Cannot open scene tab while play mode is running");
        return false;
    }

    for * tab, index: editor_context.tabs {
        if tab.path == path {
            editor_set_active_scene_tab(cast(s32) index);
            return true;
        }
    }

    scene, ok := scene_load_toml(path);
    if !ok {
        log_error("Failed to open scene tab: %", path);
        return false;
    }

    metadata := asset_manager_ensure_metadata(path, .SCENE);

    tab: Editor_Scene_Tab;
    tab.scene = scene;
    tab.path = copy_string(path);
    tab.title = copy_string(path_filename(path));
    tab.view_camera = editor_view_camera_create();
    asset_ref: Asset_Ref;
    asset_ref_acquire_scene(*asset_ref, path, metadata.guid);
    asset_ref_release(*asset_ref);

    array_add(*editor_context.tabs, tab);
    new_index := cast(s32) editor_context.tabs.count - 1;
    editor_refresh_scene_instances_for_tab(new_index);
    editor_set_active_scene_tab(new_index);
    editor_propagate_scene_changes_from_tab(new_index);
    return true;
}

editor_set_active_scene_tab :: (index: s32, request_ui_selection := true) {
    if index < 0 || index >= cast(s32) editor_context.tabs.count then return;
    if editor_is_playing() {
        log_warning("Cannot switch scene tabs while play mode is running");
        return;
    }

    editor_context.active_tab_index = index;
    if request_ui_selection {
        editor_context.requested_tab_selection_index = index;
    }
    tab := *editor_context.tabs[index];
    engine_state.current_scene = tab.scene;
    scene_apply_environment_settings(tab.scene);

    selected_node = editor_resolve_selection(tab);
    editor_curve_on_node_selected(selected_node);
    if selected_node {
        ui_reset_rotation_state(selected_node.local.rotation);
    }
}

editor_get_active_tab :: () -> *Editor_Scene_Tab {
    index := editor_context.active_tab_index;
    if index < 0 || index >= cast(s32) editor_context.tabs.count then return null;
    return *editor_context.tabs[index];
}

editor_get_active_scene :: () -> *Scene {
    tab := editor_get_active_tab();
    if tab then return tab.scene;
    return null;
}

editor_get_active_camera :: () -> *Camera {
    tab := editor_get_active_tab();
    if !tab then return null;
    return *tab.view_camera.camera;
}

editor_handle_global_shortcuts :: () {
    if input_editor_shortcuts_blocked() then return;

    if input_primary_modifier_down() && input_key_pressed(.S) {
        editor_save_active_scene();
    }
}

editor_create_model_node_from_asset :: (
    parent: *Node,
    model_path: string,
    local_position: Vector3 = .{0.0, 0.0, 0.0}
) -> *Node {
    if editor_is_playing() {
        log_warning("Cannot add model while play mode is running");
        return null;
    }
    if !model_path {
        log_warning("Cannot add model: empty asset path");
        return null;
    }

    scene := editor_get_active_scene();
    if !scene || !scene.root {
        log_warning("Cannot add model: no active scene");
        return null;
    }

    target_parent := ifx parent then parent else scene.root;
    if !editor_can_parent_under(target_parent) {
        log_warning("Cannot add child under this node");
        return null;
    }

    node := editor_add_child_node(target_parent, path_filename(model_path));
    if !node then return null;
    node.local.position = local_position;

    model_component := node_add_component(node, Model_Component);
    if !scene_set_model_component_model(model_component, model_path) {
        editor_delete_node(node);
        return null;
    }

    scene_update_transforms(scene);
    editor_select_node(node);
    editor_mark_current_scene_dirty();
    return node;
}

editor_create_scene_instance_from_asset :: (
    parent: *Node,
    scene_path: string,
    local_position: Vector3 = .{0.0, 0.0, 0.0}
) -> *Node {
    if editor_is_playing() {
        log_warning("Cannot add scene instance while play mode is running");
        return null;
    }
    if !scene_path {
        log_warning("Cannot add scene instance: empty asset path");
        return null;
    }

    scene := editor_get_active_scene();
    if !scene || !scene.root {
        log_warning("Cannot add scene instance: no active scene");
        return null;
    }

    // prevent recursion
    if scene.source_path {
        if scene.source_path == scene_path {
            log_warning("Cannot instantiate a scene into itself.");
            return null;
        }

        empty_stack: [0] string;
        target_scene, ok := scene_load_toml_internal(scene_path, .{apply_scene_settings = false, instance_stack = empty_stack});
        if ok {
            has_cycle := scene_has_instance_path(target_scene, scene.source_path);
            scene_destroy(target_scene);

            if has_cycle {
                log_warning("Cannot instantiate scene because it would create a cyclic dependency.");
                return null;
            }
        }
    }

    target_parent := ifx parent then parent else scene.root;
    if !editor_can_parent_under(target_parent) {
        log_warning("Cannot add child under this node");
        return null;
    }

    node := editor_add_child_node(target_parent, path_filename(scene_path));
    if !node then return null;
    node.local.position = local_position;
    node.instance_path = copy_string(scene_path);

    scene_refresh_instances_from_path(scene, scene_path);

    scene_update_transforms(scene);
    editor_select_node(node);
    editor_mark_current_scene_dirty();
    return node;
}

editor_create_sprite_node_from_asset :: (
    parent: *Node,
    texture_path: string,
    local_position: Vector3 = .{0.0, 0.0, 0.0}
) -> *Node {
    if editor_is_playing() {
        log_warning("Cannot add sprite while play mode is running");
        return null;
    }
    if !texture_path {
        log_warning("Cannot add sprite: empty asset path");
        return null;
    }
    if asset_type_from_path(texture_path) != .TEXTURE {
        log_warning("Cannot add sprite from non-texture asset: %", texture_path);
        return null;
    }

    scene := editor_get_active_scene();
    if !scene || !scene.root {
        log_warning("Cannot add sprite: no active scene");
        return null;
    }

    target_parent := ifx parent then parent else scene.root;
    if !editor_can_parent_under(target_parent) {
        log_warning("Cannot add child under this node");
        return null;
    }

    node := editor_add_child_node(target_parent, path_filename(texture_path));
    if !node then return null;
    node.local.position = local_position;

    sprite := node_add_component(node, Sprite_Component);
    if !editor_set_sprite_texture(sprite, texture_path) {
        editor_delete_node(node);
        return null;
    }

    if sprite.texture && sprite.texture.height > 0 {
        sprite.size = .{cast(float) sprite.texture.width / cast(float) sprite.texture.height, 1.0};
    }

    scene_update_transforms(scene);
    editor_select_node(node);
    editor_mark_current_scene_dirty();
    return node;
}

editor_set_sprite_texture :: (
    sprite: *Sprite_Component,
    texture_path: string,
    texture_filter: string = "linear"
) -> bool {
    if !sprite || !texture_path then return false;
    if asset_type_from_path(texture_path) != .TEXTURE {
        log_warning("Rejected non-texture asset for sprite: %", texture_path);
        return false;
    }

    spec := editor_texture_spec_from_filter(texture_filter, srgb = true);
    metadata := asset_manager_ensure_metadata(texture_path, .TEXTURE);
    texture := asset_ref_acquire_texture(
        *sprite.texture_ref,
        metadata.path,
        metadata.guid,
        spec,
        false
    );
    if !texture {
        log_warning("Failed to assign sprite texture: %", texture_path);
        return false;
    }

    free(sprite.texture_path);
    free(sprite.texture_guid);
    free(sprite.texture_filter);
    sprite.texture_path = copy_string(metadata.path);
    sprite.texture_guid = copy_string(metadata.guid);
    sprite.texture_filter = copy_string(texture_filter);
    sprite.texture = texture;
    sprite.uv_transform = Matrix3_Identity;
    return true;
}

editor_set_material_override_diffuse_texture :: (
    override: *Model_Material_Override,
    texture_path: string
) -> bool {
    return editor_set_material_override_texture(override, texture_path, diffuse = true);
}

editor_set_material_override_specular_texture :: (
    override: *Model_Material_Override,
    texture_path: string
) -> bool {
    return editor_set_material_override_texture(override, texture_path, diffuse = false);
}

editor_set_material_override_texture :: (
    override: *Model_Material_Override,
    texture_path: string,
    diffuse: bool
) -> bool {
    if !override || !texture_path then return false;
    if asset_type_from_path(texture_path) != .TEXTURE {
        log_warning("Rejected non-texture asset for material override: %", texture_path);
        return false;
    }

    spec := editor_texture_spec_from_filter("linear", srgb = diffuse);
    metadata := asset_manager_ensure_metadata(texture_path, .TEXTURE);

    if diffuse {
        texture := asset_ref_acquire_texture(
            *override.diffuse_texture_ref,
            metadata.path,
            metadata.guid,
            spec,
            false
        );
        if !texture then return false;

        free(override.diffuse_texture_path);
        free(override.diffuse_texture_guid);
        override.diffuse_texture_path = copy_string(metadata.path);
        override.diffuse_texture_guid = copy_string(metadata.guid);
        override.diffuse_map = texture;
        return true;
    }

    texture := asset_ref_acquire_texture(
        *override.specular_texture_ref,
        metadata.path,
        metadata.guid,
        spec,
        false
    );
    if !texture then return false;

    free(override.specular_texture_path);
    free(override.specular_texture_guid);
    override.specular_texture_path = copy_string(metadata.path);
    override.specular_texture_guid = copy_string(metadata.guid);
    override.specular_map = texture;
    return true;
}

editor_texture_spec_from_filter :: (filter: string, srgb: bool) -> Texture_Spec {
    spec := UI_TEXTURE_SPEC;
    spec.srgb = srgb;

    if filter == "nearest" {
        spec.min_filter = .NEAREST;
        spec.mag_filter = .NEAREST;
        spec.generate_mipmaps = false;
        return spec;
    }

    spec.min_filter = .LINEAR;
    spec.mag_filter = .LINEAR;
    spec.generate_mipmaps = false;
    return spec;
}

editor_viewport_drop_position :: () -> Vector3 {
    tab := editor_get_active_tab();
    if tab {
        return tab.view_camera.focus;
    }
    return .{0.0, 0.0, 0.0};
}

editor_add_child_node :: (parent: *Node, name: string = "Node") -> *Node {
    if editor_is_playing() {
        log_warning("Cannot add node while play mode is running");
        return null;
    }

    scene := editor_get_active_scene();
    if !scene || !scene.root {
        log_warning("Cannot add node: no active scene");
        return null;
    }
    target_parent := ifx parent then parent else scene.root;
    if !editor_can_parent_under(target_parent) {
        log_warning("Cannot add child under this node");
        return null;
    }

    node_name := ifx name && name.count > 0 then name else "Node";
    node := node_add_node(target_parent, node_name);
    scene_id := editor_make_unique_scene_id(scene, node_name);
    node_set_scene_id(node, scene_id);
    free(scene_id);

    scene_update_transforms(scene);
    editor_select_node(node);
    editor_mark_current_scene_dirty();
    return node;
}

editor_delete_node :: (node: *Node) -> bool {
    if !editor_can_edit_node(node, allow_root = false) {
        log_warning("Cannot delete this node");
        return false;
    }

    parent := node.parent;
    if !node_detach_from_parent(node) then return false;

    if selected_node == node {
        editor_select_node(parent);
    }
    node_destroy(node);
    scene_update_transforms(editor_get_active_scene());
    editor_mark_current_scene_dirty();
    return true;
}

editor_reparent_node :: (node: *Node, new_parent: *Node) -> bool {
    if !editor_can_edit_node(node, allow_root = false) {
        log_warning("Cannot reparent this node");
        return false;
    }
    if !editor_can_parent_under(new_parent) {
        log_warning("Cannot reparent under this node");
        return false;
    }
    if !editor_node_belongs_to_scene(node, editor_get_active_scene()) ||
       !editor_node_belongs_to_scene(new_parent, editor_get_active_scene()) {
        return false;
    }
    if !node_reparent(node, new_parent) then return false;

    scene_update_transforms(editor_get_active_scene());
    editor_select_node(node);
    editor_mark_current_scene_dirty();
    return true;
}

editor_move_node_to_parent_index :: (node: *Node, new_parent: *Node, child_index: s64) -> bool {
    if !editor_can_edit_node(node, allow_root = false) {
        log_warning("Cannot move this node");
        return false;
    }
    if !editor_can_parent_under(new_parent) {
        log_warning("Cannot move under this node");
        return false;
    }
    if !editor_node_belongs_to_scene(node, editor_get_active_scene()) ||
       !editor_node_belongs_to_scene(new_parent, editor_get_active_scene()) {
        return false;
    }
    if !node_reparent_at(node, new_parent, child_index) then return false;

    scene_update_transforms(editor_get_active_scene());
    editor_select_node(node);
    editor_mark_current_scene_dirty();
    return true;
}

editor_move_node_in_parent :: (node: *Node, offset: s32) -> bool {
    if !editor_can_edit_node(node, allow_root = false) then return false;
    if !node_move_in_parent(node, offset) then return false;

    editor_mark_current_scene_dirty();
    return true;
}

editor_rename_node :: (node: *Node, name: string) -> bool {
    if !editor_can_edit_node(node, allow_root = true) then return false;
    node_set_name(node, name);
    editor_mark_current_scene_dirty();
    return true;
}

editor_mark_current_scene_dirty :: () {
    if editor_is_playing() {
        return;
    }

    tab := editor_get_active_tab();
    if !tab then return;

    tab.dirty = true;
}

editor_save_active_scene :: () -> bool {
    if editor_is_playing() {
        log_warning("Cannot save scene while play mode is running");
        return false;
    }

    tab := editor_get_active_tab();
    if !tab || !tab.scene then return false;

    ok := scene_save_toml(tab.scene, tab.path);
    if ok {
        tab.dirty = false;
        editor_propagate_scene_changes_from_tab(editor_context.active_tab_index);
    }
    return ok;
}

editor_request_close_scene_tab :: (index: s32) {
    if index < 0 || index >= cast(s32) editor_context.tabs.count then return;
    if editor_is_playing() {
        log_warning("Cannot close scene tabs while play mode is running");
        return;
    }

    tab := *editor_context.tabs[index];
    if tab.dirty {
        editor_context.pending_close_tab_index = index;
        return;
    }

    editor_close_scene_tab(index);
}

editor_close_scene_tab :: (index: s32) {
    if index < 0 || index >= cast(s32) editor_context.tabs.count then return;

    old_active_index := editor_context.active_tab_index;
    was_active := index == old_active_index;
    closing_path := copy_string(editor_context.tabs[index].path);
    defer free(closing_path);

    if was_active {
        selected_node = null;
        engine_state.current_scene = null;
    }

    editor_scene_tab_destroy(*editor_context.tabs[index]);
    array_ordered_remove_by_index(*editor_context.tabs, index);

    if editor_context.tabs.count == 0 {
        editor_context.active_tab_index = -1;
        engine_state.current_scene = null;
        selected_node = null;
        return;
    }

    new_index := old_active_index;
    if was_active {
        new_index = min(index, cast(s32) editor_context.tabs.count - 1);
    } else if old_active_index > index {
        new_index = old_active_index - 1;
    }
    editor_context.active_tab_index = new_index;

    editor_refresh_scene_instances_from_disk(closing_path);

    editor_set_active_scene_tab(new_index);
}

editor_select_node :: (node: *Node) {
    selected_node = node;
    editor_curve_on_node_selected(node);

    if editor_is_playing() {
        if node {
            ui_reset_rotation_state(node.local.rotation);
        }
        return;
    }

    tab := editor_get_active_tab();
    if tab {
        editor_node_handle_clear(*tab.selection);
        if node {
            tab.selection.runtime_id = node.runtime_id;
            tab.selection.scene_id = copy_string(node.scene_id);
        }
    }

    if node {
        ui_reset_rotation_state(node.local.rotation);
    }
}

editor_validate_selection :: () {
    if editor_is_playing() {
        scene := engine_state.current_scene;
        if !scene {
            selected_node = null;
            editor_curve_on_node_selected(null);
            return;
        }

        if selected_node && editor_node_belongs_to_scene(selected_node, scene) {
            return;
        }

        selected_node = null;
        editor_curve_on_node_selected(null);
        return;
    }

    tab := editor_get_active_tab();
    if !tab {
        selected_node = null;
        editor_curve_on_node_selected(null);
        return;
    }

    if selected_node && editor_node_belongs_to_scene(selected_node, tab.scene) {
        return;
    }

    selected_node = editor_resolve_selection(tab);
    editor_curve_on_node_selected(selected_node);
}

editor_refresh_scene_instances_for_tab :: (target_index: s32) {
    if target_index < 0 || target_index >= cast(s32) editor_context.tabs.count then return;

    target := *editor_context.tabs[target_index];
    if !target.scene then return;

    refreshed := false;
    for * source, source_index: editor_context.tabs {
        if cast(s32) source_index == target_index then continue;
        if !source.scene || !source.path then continue;

        if scene_refresh_instances_from_source(target.scene, source.path, source.scene) {
            refreshed = true;
        }
    }

    if refreshed {
        scene_update_transforms(target.scene);
    }
}

editor_propagate_scene_changes_from_tab :: (source_index: s32) {
    if source_index < 0 || source_index >= cast(s32) editor_context.tabs.count then return;

    visited: [..] s32;
    defer array_free(visited);

    editor_propagate_scene_changes_recursive(source_index, *visited);
    editor_validate_selection();
}

editor_refresh_scene_instances_from_disk :: (source_path: string) {
    if !source_path then return;

    visited: [..] s32;
    defer array_free(visited);

    for * tab, index: editor_context.tabs {
        if !tab.scene then continue;

        if scene_refresh_instances_from_path(tab.scene, source_path) {
            scene_update_transforms(tab.scene);
            editor_propagate_scene_changes_recursive(cast(s32) index, *visited);
        }
    }

    editor_validate_selection();
}

#scope_file

// instance propagation can bounce between open tabs, so track visited tabs
// to stop cyclical refresh cascades.
editor_propagate_scene_changes_recursive :: (
    source_index: s32,
    visited: *[..] s32
) {
    if source_index < 0 || source_index >= cast(s32) editor_context.tabs.count then return;

    for visited.* {
        if it == source_index then return;
    }
    array_add(visited, source_index);

    source := *editor_context.tabs[source_index];
    if !source.scene || !source.path then return;

    for * target, target_index: editor_context.tabs {
        target_index_s32 := cast(s32) target_index;
        if target_index_s32 == source_index then continue;
        if !target.scene then continue;

        if scene_refresh_instances_from_source(target.scene, source.path, source.scene) {
            scene_update_transforms(target.scene);
            editor_propagate_scene_changes_recursive(target_index_s32, visited);
        }
    }
}

editor_scene_tab_destroy :: (tab: *Editor_Scene_Tab) {
    if !tab then return;

    if tab.scene {
        scene_destroy(tab.scene);
    }
    free(tab.path);
    free(tab.title);
    editor_node_handle_clear(*tab.selection);
    tab.* = .{};
}

editor_node_handle_clear :: (handle: *Editor_Node_Handle) {
    if !handle then return;
    free(handle.scene_id);
    handle.* = .{};
}

editor_resolve_selection :: (tab: *Editor_Scene_Tab) -> *Node {
    if !tab || !tab.scene then return null;

    return node_find_by_runtime_or_scene_id(
        tab.scene.root,
        tab.selection.runtime_id,
        tab.selection.scene_id
    );
}

editor_node_belongs_to_scene :: (node: *Node, scene: *Scene) -> bool {
    if !node || !scene then return false;

    current := node;
    while current.parent {
        current = current.parent;
    }
    return current == scene.root;
}

editor_can_edit_node :: (node: *Node, allow_root: bool) -> bool {
    if editor_is_playing() then return false;
    scene := editor_get_active_scene();
    if !node || !scene then return false;
    if !editor_node_belongs_to_scene(node, scene) then return false;
    if node.inherited_from_instance then return false;
    if !allow_root && node == scene.root then return false;
    return true;
}

editor_can_parent_under :: (node: *Node) -> bool {
    if !editor_can_edit_node(node, allow_root = true) then return false;
    if node.instance_path then return false;
    return true;
}

#scope_export

editor_node_can_add_child :: (node: *Node) -> bool {
    return editor_can_parent_under(node);
}

editor_node_can_delete :: (node: *Node) -> bool {
    return editor_can_edit_node(node, allow_root = false);
}

editor_node_can_move :: (node: *Node) -> bool {
    return editor_can_edit_node(node, allow_root = false);
}

editor_node_can_edit_components :: (node: *Node) -> bool {
    if !editor_can_edit_node(node, allow_root = true) then return false;
    if node.instance_path then return false;
    return true;
}

#scope_file

editor_make_unique_scene_id :: (scene: *Scene, base: string) -> string {
    id_base := base;
    if !id_base || id_base.count == 0 {
        id_base = "node";
    }

    if !node_find_authored_by_scene_id(scene.root, id_base) {
        return copy_string(id_base);
    }

    index := 2;
    while true {
        candidate := tprint("%_%", id_base, index);
        if !node_find_authored_by_scene_id(scene.root, candidate) {
            return copy_string(candidate);
        }
        index += 1;
    }

    return copy_string(id_base);
}

editor_remove_child_node :: (parent: *Node, node: *Node) {
    if !parent || !node then return;

    for child: parent.children {
        if child == node {
            array_ordered_remove_by_index(*parent.children, it_index);
            node_destroy(node);
            return;
        }
    }
}

#scope_export

editor_render_mode_apply_environment :: (environment: Scene_Environment) -> Scene_Environment {
    result := environment;

    if editor_context.render_mode != .LIT {
        result.skybox_enabled = false;
        result.fog_resolve_enabled = false;
        result.fog_enabled = false;
    }

    if editor_context.render_mode == .UNLIT ||
       editor_context.render_mode == .WIREFRAME ||
       editor_context.render_mode == .ALBEDO {
        result.ambient_color = .{1.0, 1.0, 1.0};
    }

    return result;
}

editor_render_mode_uses_scene_lights :: () -> bool {
    return editor_context.render_mode == .LIT ||
        editor_context.render_mode == .LIGHTING_ONLY;
}

editor_render_mode_is_wireframe :: () -> bool {
    return editor_context.render_mode == .WIREFRAME;
}

editor_render_mode_to_renderer_view_mode :: () -> Render_View_Mode {
    if editor_context.render_mode == .UNLIT then return .UNLIT;
    if editor_context.render_mode == .LIGHTING_ONLY then return .LIGHTING_ONLY;
    if editor_context.render_mode == .ALBEDO then return .ALBEDO;
    if editor_context.render_mode == .WIREFRAME then return .UNLIT;
    return .LIT;
}

editor_render_mode_label :: () -> string {
    if editor_context.render_mode == .UNLIT then return "Unlit";
    if editor_context.render_mode == .WIREFRAME then return "Wireframe";
    if editor_context.render_mode == .LIGHTING_ONLY then return "Lighting Only";
    if editor_context.render_mode == .ALBEDO then return "Albedo";
    return "Lit";
}

editor_view_camera_create :: () -> Editor_View_Camera {
    view: Editor_View_Camera;
    view.camera = camera_create(.{0.0, 4.0, 12.0});
    view.focus = .{0.0, 0.0, 0.0};
    view.distance = EDITOR_VIEW_CAMERA_DEFAULT_DISTANCE;
    view.yaw = -90.0;
    view.pitch = -18.0;
    view.initialized = true;
    editor_view_camera_rebuild(*view);
    return view;
}

#scope_export

// sanitize editor camera state before rebuilding vectors so broken serialized
// values cannot poison viewport navigation.
editor_view_camera_rebuild :: (view: *Editor_View_Camera) {
    if !view then return;

    view.focus.x = editor_view_camera_sanitize_coordinate(view.focus.x);
    view.focus.y = editor_view_camera_sanitize_coordinate(view.focus.y);
    view.focus.z = editor_view_camera_sanitize_coordinate(view.focus.z);
    view.yaw = editor_view_camera_wrap_degrees(
        editor_view_camera_sanitize_scalar(view.yaw, -90.0, -360000.0, 360000.0)
    );
    view.pitch = editor_view_camera_sanitize_scalar(view.pitch, -18.0, -89.0, 89.0);
    view.distance = editor_view_camera_sanitize_scalar(
        view.distance,
        EDITOR_VIEW_CAMERA_DEFAULT_DISTANCE,
        EDITOR_VIEW_CAMERA_MIN_DISTANCE,
        EDITOR_VIEW_CAMERA_MAX_DISTANCE
    );

    yaw_radians := degrees_to_radians(view.yaw);
    pitch_radians := degrees_to_radians(view.pitch);

    front: Vector3;
    front.x = cos(yaw_radians) * cos(pitch_radians);
    front.y = sin(pitch_radians);
    front.z = sin(yaw_radians) * cos(pitch_radians);
    front = normalize(front);

    view.camera.front = front;
    view.camera.position = view.focus - front * view.distance;
    view.camera.yaw = view.yaw;
    view.camera.pitch = view.pitch;
    camera_update_vectors(*view.camera);
}

editor_view_camera_sanitize_scalar :: (
    value: float,
    fallback: float,
    min_value: float,
    max_value: float
) -> float {
    if value != value then return fallback;
    if value < min_value then return min_value;
    if value > max_value then return max_value;
    return value;
}

editor_view_camera_sanitize_coordinate :: (value: float) -> float {
    return editor_view_camera_sanitize_scalar(
        value,
        0.0,
        -EDITOR_VIEW_CAMERA_COORDINATE_LIMIT,
        EDITOR_VIEW_CAMERA_COORDINATE_LIMIT
    );
}

editor_view_camera_wrap_degrees :: (angle: float) -> float {
    result := angle;
    while result > 180.0 result -= 360.0;
    while result < -180.0 result += 360.0;
    return result;
}
