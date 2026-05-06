// File:        scene_loader.jai
// Author:      Lukáš Bien
// Description: Loads, saves, and refreshes scene data and scene instances from TOML files.

#scope_file

#import "Basic";
#import "File";
#import "Math";

using Toml :: #import "toml-jai";

#scope_export

Scene_Load_Options :: struct {
    apply_scene_settings: bool = true;
    instance_stack: [] string;
}

scene_load_toml :: (path: string) -> *Scene, bool {
    empty_stack: [0] string;
    scene, ok := scene_load_toml_internal(path, .{apply_scene_settings = true, instance_stack = empty_stack});
    return scene, ok;
}

// load authored nodes first, then instantiate inherited scene content so
// parent ids always resolve against authored structure.
scene_load_toml_internal :: (path: string, options: Scene_Load_Options) -> *Scene, bool {
    contents, read_ok := read_entire_file(path);
    if !read_ok {
        log_error("Failed to read scene file: %", path);
        return null, false;
    }
    defer free(contents);

    parse_ok, root := Toml.string_to_type(contents, Toml.Value);
    if !parse_ok {
        log_error("Failed to parse scene TOML: %", path);
        return null, false;
    }

    version := scene_toml_get_int(root, "version", 1);
    if version != 1 {
        log_error("Unsupported scene version % in %", version, path);
        return null, false;
    }

    scene_name := scene_toml_get_string(root, "name", "Scene");
    scene := scene_create(scene_name);
    scene.source_path = copy_string(path);
    if options.apply_scene_settings {
        scene.ambient_color = scene_toml_get_vec3(root, "ambient_color", .{0.0, 0.0, 0.0});
        scene.environment.ambient_color = scene.ambient_color;

        found_environment, environment_value := scene_toml_find(root, "environment");
        if found_environment {
            scene_load_environment(scene, environment_value);
        }

        scene_apply_environment_settings(scene);
    }

    found_nodes, nodes_value := scene_toml_find(root, "nodes");
    if !found_nodes || nodes_value.kind != .ARRAY {
        log_error("Scene file % does not contain a nodes array", path);
        scene_destroy(scene);
        return null, false;
    }

    for node_value: nodes_value.array {
        if node_value.kind != .TABLE {
            log_error("Scene node entry in % is not a table", path);
            scene_destroy(scene);
            return null, false;
        }

        id := scene_toml_get_string(node_value, "id", "");
        name := scene_toml_get_string(node_value, "name", id);
        parent_id := scene_toml_get_string(node_value, "parent", "root");

        if !id {
            log_error("Scene node in % is missing id", path);
            scene_destroy(scene);
            return null, false;
        }

        parent := scene.root;
        if parent_id != "root" {
            parent = node_find_authored_by_scene_id(scene.root, parent_id);
            if !parent {
                log_error("Scene node % references unknown parent %", id, parent_id);
                scene_destroy(scene);
                return null, false;
            }
            if parent.instance_path {
                log_error("Scene node % cannot be authored under scene instance %. Open the source scene instead.", id, parent_id);
                scene_destroy(scene);
                return null, false;
            }
        }

        node := node_add_node(parent, name);
        node_set_scene_id(node, id);
        node.local.position = scene_toml_get_vec3(node_value, "position", .{0.0, 0.0, 0.0});
        node.local.rotation = quaternion_from_euler_xyz(scene_toml_get_vec3(node_value, "rotation", .{0.0, 0.0, 0.0}));
        node.local.scale    = scene_toml_get_vec3(node_value, "scale", .{1.0, 1.0, 1.0});

        instance_path := scene_toml_get_string(node_value, "instance", "");
        if instance_path {
            if !scene_instantiate_source(scene, node, instance_path, options.instance_stack) {
                log_error("Failed to instantiate scene % on node %", instance_path, id);
                scene_destroy(scene);
                return null, false;
            }
        }

        found_components, components_value := scene_toml_find(node_value, "components");
        if found_components {
            if components_value.kind != .ARRAY {
                log_error("Scene node % components entry is not an array", id);
                scene_destroy(scene);
                return null, false;
            }

            for component_value: components_value.array {
                if component_value.kind != .TABLE {
                    log_error("Scene node % component entry is not a table", id);
                    scene_destroy(scene);
                    return null, false;
                }

                if !scene_load_component(scene, node, component_value) {
                    log_error("Failed to load component on scene node %", id);
                    scene_destroy(scene);
                    return null, false;
                }
            }
        }
    }

    scene_update_transforms(scene);
    log("Loaded scene: %", path);
    return scene, true;
}

scene_save_toml :: (scene: *Scene, path: string = "") -> bool {
    if !scene {
        log_error("scene_save_toml: scene is null");
        return false;
    }

    output_path := path;
    if !output_path {
        output_path = scene.source_path;
    }
    if !output_path {
        log_error("scene_save_toml: scene has no source path");
        return false;
    }

    builder: String_Builder;
    scene_write_header(*builder, scene);
    scene_write_nodes(*builder, scene.root);

    contents := builder_to_string(*builder);
    defer free(contents);

    ok := write_entire_file(output_path, contents);
    if ok {
        if scene.source_path != output_path {
            free(scene.source_path);
            scene.source_path = copy_string(output_path);
        }
        log("Saved scene: %", output_path);
    } else {
        log_error("Failed to save scene: %", output_path);
    }

    return ok;
}

scene_refresh_instances_from_source :: (
    scene: *Scene,
    source_path: string,
    source_scene: *Scene
) -> bool {
    if !scene || !scene.root then return false;
    if !source_path || !source_scene || !source_scene.root then return false;

    return scene_refresh_node_instances_from_source(scene.root, source_path, source_scene);
}

scene_refresh_instances_from_path :: (
    scene: *Scene,
    source_path: string
) -> bool {
    if !scene || !source_path then return false;
    if !scene_has_instance_path(scene, source_path) then return false;

    stack: [..] string;
    defer array_free(stack);
    if scene.source_path {
        array_add(*stack, scene.source_path);
    }

    source_scene, ok := scene_load_toml_internal(
        source_path,
        .{apply_scene_settings = false, instance_stack = stack}
    );
    if !ok {
        log_warning("Failed to refresh scene instance from disk: %", source_path);
        return false;
    }
    defer scene_destroy(source_scene);

    return scene_refresh_instances_from_source(scene, source_path, source_scene);
}

scene_set_model_component_model :: (
    model_component: *Model_Component,
    path: string,
    guid: string = "",
    preserve_material_overrides := false
) -> bool {
    if !model_component || !path then return false;
    if asset_type_from_path(path) != .MODEL {
        log_warning("Rejected non-model asset for model component: %", path);
        return false;
    }
    if !file_exists(path) {
        log_warning("Rejected missing model asset for model component: %", path);
        return false;
    }

    metadata := asset_manager_ensure_metadata(path, .MODEL, guid);
    model := asset_ref_acquire_model(
        *model_component.model_ref,
        metadata.path,
        metadata.guid
    );
    if !model {
        log_error("Failed to acquire scene model: %", metadata.path);
        return false;
    }

    free(model_component.model_path);
    free(model_component.model_guid);
    model_component.model_path = copy_string(metadata.path);
    model_component.model_guid = copy_string(metadata.guid);
    model_component.model_resource = model;
    model_component.model_local_matrix = Matrix4_Identity;
    if !preserve_material_overrides {
        model_component_clear_material_overrides(model_component);
    }
    return true;
}

scene_has_instance_path :: (scene: *Scene, source_path: string) -> bool {
    if !scene || !scene.root || !source_path then return false;
    return scene_node_has_instance_path(scene.root, source_path);
}

#scope_file

// keep a per-load stack of source paths so nested scene instances cannot
// recursively instantiate each other forever.
scene_instantiate_source :: (
    scene: *Scene,
    node: *Node,
    instance_path: string,
    parent_stack: [] string
) -> bool {
    if !scene || !node || !instance_path then return false;

    stack: [..] string;
    defer array_free(stack);

    for parent_stack {
        array_add(*stack, it);
    }

    if scene.source_path && !scene_stack_contains(stack, scene.source_path) {
        array_add(*stack, scene.source_path);
    }

    if scene_stack_contains(stack, instance_path) {
        log_error("Recursive scene instance detected: %", instance_path);
        return false;
    }

    array_add(*stack, instance_path);

    source_scene, ok := scene_load_toml_internal(
        instance_path,
        .{apply_scene_settings = false, instance_stack = stack}
    );
    if !ok {
        return false;
    }
    defer scene_destroy(source_scene);

    node_set_instance_path(node, instance_path);

    for child: source_scene.root.children {
        child_clone := node_clone(child);
        child_clone.parent = node;
        node_mark_inherited_from_instance(child_clone);
        array_add(*node.children, child_clone);
    }

    return true;
}

scene_refresh_node_instances_from_source :: (
    node: *Node,
    source_path: string,
    source_scene: *Scene
) -> bool {
    if !node then return false;

    if scene_instance_path_matches(node.instance_path, source_path) {
        scene_replace_instance_children(node, source_scene);
        return true;
    }

    refreshed := false;
    for child: node.children {
        if scene_refresh_node_instances_from_source(child, source_path, source_scene) {
            refreshed = true;
        }
    }

    return refreshed;
}

scene_node_has_instance_path :: (node: *Node, source_path: string) -> bool {
    if !node then return false;

    if scene_instance_path_matches(node.instance_path, source_path) {
        return true;
    }

    for child: node.children {
        if scene_node_has_instance_path(child, source_path) {
            return true;
        }
    }

    return false;
}

scene_replace_instance_children :: (node: *Node, source_scene: *Scene) {
    if !node || !source_scene || !source_scene.root then return;

    scene_clear_instance_children(node);

    for child: source_scene.root.children {
        child_clone := node_clone(child);
        child_clone.parent = node;
        node_mark_inherited_from_instance(child_clone);
        array_add(*node.children, child_clone);
    }
}

scene_clear_instance_children :: (node: *Node) {
    if !node then return;

    index := cast(s64) node.children.count - 1;
    while index >= 0 {
        child := node.children[index];
        if child.inherited_from_instance {
            array_ordered_remove_by_index(*node.children, index);
            node_destroy(child);
        }

        index -= 1;
    }
}

scene_instance_path_matches :: (left: string, right: string) -> bool {
    if !left || !right then return false;
    if left == right then return true;

    left_absolute, left_ok := get_absolute_path(left);
    if !left_ok then return false;

    right_absolute, right_ok := get_absolute_path(right);
    if !right_ok then return false;

    return left_absolute == right_absolute;
}

scene_stack_contains :: (stack: [] string, path: string) -> bool {
    for stack {
        if scene_instance_path_matches(it, path) then return true;
    }

    return false;
}

scene_write_header :: (builder: *String_Builder, scene: *Scene) {
    print_to_builder(builder, "version = 1\n");
    print_to_builder(builder, "name = ");
    scene_write_string(builder, scene.name);
    print_to_builder(builder, "\n\n");

    scene_write_environment(builder, scene);
}

scene_write_nodes :: (builder: *String_Builder, node: *Node) {
    if !node then return;

    for child: node.children {
        scene_write_node(builder, child);
    }
}

scene_write_node :: (builder: *String_Builder, node: *Node) {
    if !node then return;

    if node.inherited_from_instance {
        return;
    }

    if !node.scene_id {
        return;
    }

    print_to_builder(builder, "\n[[nodes]]\n");
    print_to_builder(builder, "id = ");
    scene_write_string(builder, node.scene_id);
    print_to_builder(builder, "\n");
    print_to_builder(builder, "name = ");
    scene_write_string(builder, node.name);
    print_to_builder(builder, "\n");
    print_to_builder(builder, "parent = ");
    if node.parent && node.parent.scene_id {
        scene_write_string(builder, node.parent.scene_id);
    } else {
        scene_write_string(builder, "root");
    }
    print_to_builder(builder, "\n");

    scene_write_vec3_assignment(builder, "position", node.local.position);
    scene_write_vec3_assignment(builder, "rotation", quaternion_to_euler_xyz(node.local.rotation));
    scene_write_vec3_assignment(builder, "scale", node.local.scale);

    if node.instance_path {
        print_to_builder(builder, "instance = ");
        scene_write_string(builder, node.instance_path);
        print_to_builder(builder, "\n");
    } else {
        for component: node.components {
            scene_write_component(builder, component);
        }

        for child: node.children {
            scene_write_node(builder, child);
        }
    }
}

scene_write_component :: (builder: *String_Builder, component: *Component) {
    if !component then return;

    if component.type == Camera_Component {
        camera_component := cast(*Camera_Component) component;
        print_to_builder(builder, "\n[[nodes.components]]\n");
        print_to_builder(builder, "type = \"camera\"\n");
        print_to_builder(builder, "active = %\n", scene_component_camera_is_active(camera_component));
        print_to_builder(builder, "yaw = %\n", camera_component.camera.yaw);
        print_to_builder(builder, "pitch = %\n", camera_component.camera.pitch);
        print_to_builder(builder, "near = %\n", camera_component.camera.near);
        print_to_builder(builder, "far = %\n", camera_component.camera.far);
        print_to_builder(builder, "fov = %\n", camera_component.camera.fov);
        return;
    }

    if component.type == Light_Component {
        light_component := cast(*Light_Component) component;
        print_to_builder(builder, "\n[[nodes.components]]\n");
        print_to_builder(builder, "type = \"light\"\n");
        print_to_builder(builder, "kind = ");
        scene_write_string(builder, scene_light_type_to_string(light_component.light.type));
        print_to_builder(builder, "\n");
        scene_write_vec3_assignment(builder, "color", light_component.light.color);
        print_to_builder(builder, "intensity = %\n", light_component.light.intensity);
        if light_component.light.type != .Directional {
            print_to_builder(builder, "range = %\n", light_component.light.range);
        }
        if light_component.light.type == .Spot {
            print_to_builder(builder, "inner_degrees = %\n", radians_to_degrees(acos(light_component.light.inner_cos)));
            print_to_builder(builder, "outer_degrees = %\n", radians_to_degrees(acos(light_component.light.outer_cos)));
        }
        return;
    }

    if component.type == Model_Component {
        model_component := cast(*Model_Component) component;
        print_to_builder(builder, "\n[[nodes.components]]\n");
        print_to_builder(builder, "type = \"model\"\n");
        print_to_builder(builder, "model = ");
        scene_write_string(builder, model_component.model_path);
        print_to_builder(builder, "\n");
        model_guid := ifx model_component.model_guid then model_component.model_guid else model_component.model_ref.guid;
        if model_guid {
            print_to_builder(builder, "model_guid = ");
            scene_write_string(builder, model_guid);
            print_to_builder(builder, "\n");
        }
        scene_write_model_material_overrides(builder, model_component);
        return;
    }

    if component.type == Animated_Sprite_Component {
        animated_sprite := cast(*Animated_Sprite_Component) component;
        scene_write_sprite_base(builder, cast(*Sprite_Component) animated_sprite, "animated_sprite");
        print_to_builder(builder, "columns = %\n", animated_sprite.columns);
        print_to_builder(builder, "rows = %\n", animated_sprite.rows);
        print_to_builder(builder, "frame_count = %\n", animated_sprite.frame_count);
        print_to_builder(builder, "fps = %\n", animated_sprite.fps);
        print_to_builder(builder, "playing = %\n", animated_sprite.playing);
        print_to_builder(builder, "loop = %\n", animated_sprite.loop);
        return;
    }

    if component.type == Sprite_Component {
        sprite := cast(*Sprite_Component) component;
        scene_write_sprite_base(builder, sprite, "sprite");
        return;
    }

    if component.type == Static_Mesh_Component {
        log_warning("Skipping Static_Mesh_Component on saved node %. Use Model_Component for authored mesh asset serialization.", component.node.name);
        return;
    }

    log_warning("Skipping unsupported component type on saved node %", component.node.name);
}

scene_write_sprite_base :: (builder: *String_Builder, sprite: *Sprite_Component, component_type: string) {
    print_to_builder(builder, "\n[[nodes.components]]\n");
    print_to_builder(builder, "type = ");
    scene_write_string(builder, component_type);
    print_to_builder(builder, "\n");

    print_to_builder(builder, "texture = ");
    scene_write_string(builder, sprite.texture_path);
    print_to_builder(builder, "\n");
    texture_guid := ifx sprite.texture_guid then sprite.texture_guid else sprite.texture_ref.guid;
    if texture_guid {
        print_to_builder(builder, "texture_guid = ");
        scene_write_string(builder, texture_guid);
        print_to_builder(builder, "\n");
    }

    print_to_builder(builder, "texture_filter = ");
    if sprite.texture_filter {
        scene_write_string(builder, sprite.texture_filter);
    } else {
        scene_write_string(builder, "linear");
    }
    print_to_builder(builder, "\n");

    scene_write_vec3_assignment(builder, "tint_color", sprite.tint_color);
    print_to_builder(builder, "alpha = %\n", sprite.alpha);
    print_to_builder(builder, "alpha_cutoff = %\n", sprite.alpha_cutoff);
    scene_write_vec2_assignment(builder, "size", sprite.size);
    print_to_builder(builder, "pivot = ");
    scene_write_string(builder, scene_sprite_pivot_to_string(sprite.pivot));
    print_to_builder(builder, "\n");
    print_to_builder(builder, "custom_pivot_enabled = %\n", sprite.custom_pivot_enabled);
    scene_write_vec2_assignment(builder, "custom_pivot", sprite.custom_pivot);
    print_to_builder(builder, "billboard_mode = ");
    scene_write_string(builder, scene_billboard_mode_to_string(sprite.billboard_mode));
    print_to_builder(builder, "\n");
    print_to_builder(builder, "transparency = ");
    scene_write_string(builder, scene_transparency_to_string(sprite.transparency));
    print_to_builder(builder, "\n");
}

scene_component_camera_is_active :: (camera_component: *Camera_Component) -> bool {
    if !camera_component || !camera_component.node then return false;

    scene := scene_find_owner(camera_component.node);
    if !scene || !scene.camera then return false;
    return scene.camera == *camera_component.camera;
}

scene_find_owner :: (node: *Node) -> *Scene {
    root := node;
    while root && root.parent {
        root = root.parent;
    }

    if engine_state.current_scene && engine_state.current_scene.root == root {
        return engine_state.current_scene;
    }

    return null;
}

scene_write_vec2_assignment :: (builder: *String_Builder, name: string, value: Vector2) {
    print_to_builder(builder, "% = [%, %]\n", name, value.x, value.y);
}

scene_write_vec3_assignment :: (builder: *String_Builder, name: string, value: Vector3) {
    print_to_builder(builder, "% = [%, %, %]\n", name, value.x, value.y, value.z);
}

scene_write_vec4_assignment :: (builder: *String_Builder, name: string, value: Vector4) {
    print_to_builder(builder, "% = [%, %, %, %]\n", name, value.x, value.y, value.z, value.w);
}

scene_write_string :: (builder: *String_Builder, value: string) {
    append(builder, "\"");
    for value {
        if it == #char "\"" {
            append(builder, "\\\"");
        } else if it == #char "\\" {
            append(builder, "\\\\");
        } else if it == #char "\n" {
            append(builder, "\\n");
        } else if it == #char "\r" {
            append(builder, "\\r");
        } else if it == #char "\t" {
            append(builder, "\\t");
        } else {
            append(builder, it);
        }
    }
    append(builder, "\"");
}

scene_write_model_material_overrides :: (
    builder: *String_Builder,
    model_component: *Model_Component
) {
    if !model_component then return;

    for override: model_component.material_overrides {
        print_to_builder(builder, "\n[[nodes.components.materials]]\n");
        print_to_builder(builder, "index = %\n", override.material_index);
        print_to_builder(builder, "enabled = %\n", override.enabled);
        scene_write_vec3_assignment(builder, "diffuse_color", override.diffuse_color);
        if override.diffuse_texture_path {
            print_to_builder(builder, "diffuse_texture = ");
            scene_write_string(builder, override.diffuse_texture_path);
            print_to_builder(builder, "\n");
            if override.diffuse_texture_guid {
                print_to_builder(builder, "diffuse_texture_guid = ");
                scene_write_string(builder, override.diffuse_texture_guid);
                print_to_builder(builder, "\n");
            }
        }
        scene_write_vec3_assignment(builder, "specular_color", override.specular_color);
        if override.specular_texture_path {
            print_to_builder(builder, "specular_texture = ");
            scene_write_string(builder, override.specular_texture_path);
            print_to_builder(builder, "\n");
            if override.specular_texture_guid {
                print_to_builder(builder, "specular_texture_guid = ");
                scene_write_string(builder, override.specular_texture_guid);
                print_to_builder(builder, "\n");
            }
        }
        scene_write_vec3_assignment(builder, "tint_color", override.tint_color);
        print_to_builder(builder, "shininess = %\n", override.shininess);
        print_to_builder(builder, "alpha = %\n", override.alpha);
        print_to_builder(builder, "alpha_cutoff = %\n", override.alpha_cutoff);
        print_to_builder(builder, "transparency = ");
        scene_write_string(builder, scene_transparency_to_string(override.transparency));
        print_to_builder(builder, "\n");
        print_to_builder(builder, "double_sided = %\n", override.double_sided);
    }
}

scene_light_type_to_string :: (value: Light_Type) -> string {
    if value == .Directional then return "directional";
    if value == .Spot then return "spot";
    return "point";
}

scene_sprite_pivot_to_string :: (value: Sprite_Pivot) -> string {
    if value == .TOP_LEFT then return "top_left";
    if value == .TOP_CENTER then return "top_center";
    if value == .TOP_RIGHT then return "top_right";
    if value == .CENTER_LEFT then return "center_left";
    if value == .CENTER then return "center";
    if value == .CENTER_RIGHT then return "center_right";
    if value == .BOTTOM_LEFT then return "bottom_left";
    if value == .BOTTOM_RIGHT then return "bottom_right";
    return "bottom_center";
}

scene_billboard_mode_to_string :: (value: Sprite_Billboard_Mode) -> string {
    if value == .NONE then return "none";
    if value == .FULL then return "full";
    return "y_axis";
}

scene_transparency_to_string :: (value: Transparency_Mode) -> string {
    if value == .DISABLED then return "disabled";
    if value == .ALPHA_SCISSOR then return "alpha_scissor";
    return "alpha_blend";
}

// keep component loading centralized here so save/load stays symmetric across
// every supported component type.
scene_load_component :: (scene: *Scene, node: *Node, component_value: Toml.Value) -> bool {
    component_type := scene_toml_get_string(component_value, "type", "");

    if component_type == "camera" {
        camera_component := node_add_component(node, Camera_Component);
        camera_component.camera = camera_create(node.local.position);
        camera_component.camera.yaw   = scene_toml_get_float(component_value, "yaw", -90.0);
        camera_component.camera.pitch = scene_toml_get_float(component_value, "pitch", 0.0);
        camera_component.camera.near  = scene_toml_get_float(component_value, "near", 0.1);
        camera_component.camera.far   = scene_toml_get_float(component_value, "far", 1000.0);
        camera_component.camera.fov   = scene_toml_get_float(component_value, "fov", 45.0);
        camera_update_vectors(*camera_component.camera);

        if scene_toml_get_bool(component_value, "active", false) {
            scene_set_active_camera(scene, camera_component);
        }
        return true;
    }

    if component_type == "light" {
        light_component := node_add_component(node, Light_Component);
        light_component.light.type = scene_parse_light_type(scene_toml_get_string(component_value, "kind", "point"));
        light_component.light.color = scene_toml_get_vec3(component_value, "color", .{1.0, 1.0, 1.0});
        light_component.light.intensity = scene_toml_get_float(component_value, "intensity", 1.0);
        light_component.light.range = scene_toml_get_float(component_value, "range", 10.0);
        light_component.light.inner_cos = cast(float) cos(degrees_to_radians(scene_toml_get_float(component_value, "inner_degrees", 16.0)));
        light_component.light.outer_cos = cast(float) cos(degrees_to_radians(scene_toml_get_float(component_value, "outer_degrees", 28.0)));
        return true;
    }

    if component_type == "animated_sprite" {
        sprite_component := node_add_component(node, Animated_Sprite_Component);
        scene_load_sprite_base(cast(*Sprite_Component) sprite_component, component_value);
        sprite_component.columns = scene_toml_get_int(component_value, "columns", 1);
        sprite_component.rows = scene_toml_get_int(component_value, "rows", 1);
        sprite_component.frame_count = scene_toml_get_int(component_value, "frame_count", sprite_component.columns * sprite_component.rows);
        sprite_component.fps = scene_toml_get_float(component_value, "fps", 8.0);
        sprite_component.playing = scene_toml_get_bool(component_value, "playing", true);
        sprite_component.loop = scene_toml_get_bool(component_value, "loop", true);
        return true;
    }

    if component_type == "sprite" {
        sprite_component := node_add_component(node, Sprite_Component);
        scene_load_sprite_base(sprite_component, component_value);
        return true;
    }

    if component_type == "model" {
        path := scene_toml_get_string(component_value, "model", "");
        if !path then return false;

        guid := scene_toml_get_string(component_value, "model_guid", "");
        model_component := node_add_component(node, Model_Component);
        ok := scene_set_model_component_model(model_component, path, guid);
        if ok {
            scene_load_model_material_overrides(model_component, component_value);
        }
        return ok;
    }

    log_error("Unknown scene component type: %", component_type);
    return false;
}

scene_load_sprite_base :: (sprite_component: *Sprite_Component, component_value: Toml.Value) {
    texture_path := scene_toml_get_string(component_value, "texture", "");
    texture_guid := scene_toml_get_string(component_value, "texture_guid", "");
    texture_filter := scene_toml_get_string(component_value, "texture_filter", "linear");
    texture_spec := scene_parse_texture_spec(texture_filter);
    if texture_path {
        sprite_component.texture_path = copy_string(texture_path);
        sprite_component.texture_guid = copy_string(texture_guid);
        sprite_component.texture_filter = copy_string(texture_filter);
        sprite_component.texture = asset_ref_acquire_texture(
            *sprite_component.texture_ref,
            texture_path,
            texture_guid,
            texture_spec,
            false
        );
        if sprite_component.texture_ref.guid && sprite_component.texture_guid != sprite_component.texture_ref.guid {
            free(sprite_component.texture_guid);
            sprite_component.texture_guid = copy_string(sprite_component.texture_ref.guid);
        }
    }

    sprite_component.tint_color = scene_toml_get_vec3(component_value, "tint_color", .{1.0, 1.0, 1.0});
    sprite_component.alpha = scene_toml_get_float(component_value, "alpha", 1.0);
    sprite_component.alpha_cutoff = scene_toml_get_float(component_value, "alpha_cutoff", 0.1);
    sprite_component.size = scene_toml_get_vec2(component_value, "size", .{1.0, 1.0});
    sprite_component.pivot = scene_parse_sprite_pivot(scene_toml_get_string(component_value, "pivot", "center"));
    sprite_component.custom_pivot_enabled = scene_toml_get_bool(component_value, "custom_pivot_enabled", false);
    sprite_component.custom_pivot = scene_toml_get_vec2(component_value, "custom_pivot", .{0.5, 0.5});
    sprite_component.billboard_mode = scene_parse_billboard_mode(scene_toml_get_string(component_value, "billboard_mode", "none"));
    sprite_component.transparency = scene_toml_get_transparency(
        component_value,
        sprite_component.transparency
    );
}

scene_resolve_model_component :: (model_component: *Model_Component) -> bool {
    if !model_component || !model_component.model_path then return false;
    return scene_set_model_component_model(
        model_component,
        model_component.model_path,
        model_component.model_guid,
        preserve_material_overrides = true
    );
}

scene_load_model_material_overrides :: (
    model_component: *Model_Component,
    component_value: Toml.Value
) {
    if !model_component then return;

    found, materials_value := scene_toml_find(component_value, "materials");
    if !found || materials_value.kind != .ARRAY then return;

    for material_value: materials_value.array {
        if material_value.kind != .TABLE {
            log_warning("Skipping malformed model material override");
            continue;
        }

        material_index := scene_toml_get_int(material_value, "index", -1);
        if material_index < 0 {
            log_warning("Skipping model material override without index");
            continue;
        }

        source_material: *Material = null;
        if model_component.model_resource && material_index < cast(s32) model_component.model_resource.materials.count {
            source_material = model_component.model_resource.materials[material_index];
        }

        override := model_component_ensure_material_override(model_component, material_index, source_material);
        if !override then continue;

        override.enabled = scene_toml_get_bool(material_value, "enabled", override.enabled);
        override.diffuse_color = scene_toml_get_vec3(material_value, "diffuse_color", override.diffuse_color);
        scene_load_material_override_texture(
            override,
            material_value,
            "diffuse_texture",
            "diffuse_texture_guid",
            true
        );
        override.specular_color = scene_toml_get_vec3(material_value, "specular_color", override.specular_color);
        scene_load_material_override_texture(
            override,
            material_value,
            "specular_texture",
            "specular_texture_guid",
            false
        );
        override.tint_color = scene_toml_get_vec3(material_value, "tint_color", override.tint_color);
        override.shininess = scene_toml_get_float(material_value, "shininess", override.shininess);
        override.alpha = scene_toml_get_float(material_value, "alpha", override.alpha);
        override.alpha_cutoff = scene_toml_get_float(material_value, "alpha_cutoff", override.alpha_cutoff);
        override.transparency = scene_toml_get_transparency(
            material_value,
            override.transparency
        );
        override.double_sided = scene_toml_get_bool(material_value, "double_sided", override.double_sided);
    }
}

scene_load_material_override_texture :: (
    override: *Model_Material_Override,
    material_value: Toml.Value,
    path_key: string,
    guid_key: string,
    srgb: bool
) {
    if !override then return;

    texture_path := scene_toml_get_string(material_value, path_key, "");
    if !texture_path then return;

    texture_guid := scene_toml_get_string(material_value, guid_key, "");
    spec := DEFAULT_TEXTURE_SPEC;
    spec.srgb = srgb;

    if srgb {
        texture := asset_ref_acquire_texture(
            *override.diffuse_texture_ref,
            texture_path,
            texture_guid,
            spec,
            false
        );
        if !texture then return;

        free(override.diffuse_texture_path);
        free(override.diffuse_texture_guid);
        override.diffuse_texture_path = copy_string(texture_path);
        override.diffuse_texture_guid = copy_string(ifx override.diffuse_texture_ref.guid then override.diffuse_texture_ref.guid else texture_guid);
        override.diffuse_map = texture;
    } else {
        texture := asset_ref_acquire_texture(
            *override.specular_texture_ref,
            texture_path,
            texture_guid,
            spec,
            false
        );
        if !texture then return;

        free(override.specular_texture_path);
        free(override.specular_texture_guid);
        override.specular_texture_path = copy_string(texture_path);
        override.specular_texture_guid = copy_string(ifx override.specular_texture_ref.guid then override.specular_texture_ref.guid else texture_guid);
        override.specular_map = texture;
    }
}

scene_write_environment :: (builder: *String_Builder, scene: *Scene) {
    env := scene.environment;
    print_to_builder(builder, "[environment]\n");
    scene_write_vec4_assignment(builder, "clear_color", env.clear_color);
    scene_write_vec3_assignment(builder, "ambient_color", env.ambient_color);
    print_to_builder(builder, "skybox_enabled = %\n", env.skybox_enabled);
    if env.skybox_cubemap_path {
        print_to_builder(builder, "skybox_cubemap = ");
        scene_write_string(builder, env.skybox_cubemap_path);
        print_to_builder(builder, "\n");
    }
    if env.skybox_cubemap_guid {
        print_to_builder(builder, "skybox_cubemap_guid = ");
        scene_write_string(builder, env.skybox_cubemap_guid);
        print_to_builder(builder, "\n");
    }
    print_to_builder(builder, "fog_resolve_enabled = %\n", env.fog_resolve_enabled);
    print_to_builder(builder, "fog_enabled = %\n", env.fog_enabled);
    scene_write_vec4_assignment(builder, "fog_color", env.fog_color);
    print_to_builder(builder, "fog_near = %\n", env.fog_near);
    print_to_builder(builder, "fog_far = %\n", env.fog_far);
}

scene_load_environment :: (scene: *Scene, value: Toml.Value) {
    if !scene || value.kind != .TABLE then return;

    env := *scene.environment;
    env.clear_color = scene_toml_get_vec4(value, "clear_color", env.clear_color);
    env.ambient_color = scene_toml_get_vec3(value, "ambient_color", env.ambient_color);
    env.skybox_enabled = scene_toml_get_bool(value, "skybox_enabled", env.skybox_enabled);
    cubemap_path := scene_toml_get_string(value, "skybox_cubemap", "");
    cubemap_guid := scene_toml_get_string(value, "skybox_cubemap_guid", "");
    if cubemap_path {
        free(env.skybox_cubemap_path);
        env.skybox_cubemap_path = copy_string(cubemap_path);
    }
    if cubemap_guid {
        free(env.skybox_cubemap_guid);
        env.skybox_cubemap_guid = copy_string(cubemap_guid);
    }
    env.fog_resolve_enabled = scene_toml_get_bool(value, "fog_resolve_enabled", env.fog_resolve_enabled);
    env.fog_enabled = scene_toml_get_bool(value, "fog_enabled", env.fog_enabled);
    env.fog_color = scene_toml_get_vec4(value, "fog_color", env.fog_color);
    env.fog_near = scene_toml_get_float(value, "fog_near", env.fog_near);
    env.fog_far = scene_toml_get_float(value, "fog_far", env.fog_far);
    scene.ambient_color = env.ambient_color;
}

#scope_export

scene_apply_environment_settings :: (scene: *Scene) {
    if !scene then return;

    scene_apply_environment_settings(scene, scene.environment);
}

scene_apply_environment_settings :: (scene: *Scene, environment: Scene_Environment) {
    if !scene then return;

    state := fog_resolve_get_state();
    state.enabled = environment.fog_resolve_enabled;
    state.fog_enabled = environment.fog_enabled;
    state.fog_color = environment.fog_color;
    state.fog_near = environment.fog_near;
    state.fog_far = environment.fog_far;
    scene.ambient_color = environment.ambient_color;
}

#scope_file

scene_parse_texture_spec :: (filter: string) -> Texture_Spec {
    spec := UI_TEXTURE_SPEC;

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

scene_parse_light_type :: (value: string) -> Light_Type {
    if value == "directional" then return .Directional;
    if value == "spot" then return .Spot;
    return .Point;
}

scene_parse_sprite_pivot :: (value: string) -> Sprite_Pivot {
    if value == "top_left" then return .TOP_LEFT;
    if value == "top_center" then return .TOP_CENTER;
    if value == "top_right" then return .TOP_RIGHT;
    if value == "center_left" then return .CENTER_LEFT;
    if value == "center" then return .CENTER;
    if value == "center_right" then return .CENTER_RIGHT;
    if value == "bottom_left" then return .BOTTOM_LEFT;
    if value == "bottom_center" then return .BOTTOM_CENTER;
    if value == "bottom_right" then return .BOTTOM_RIGHT;
    return .CENTER;
}

scene_parse_billboard_mode :: (value: string) -> Sprite_Billboard_Mode {
    if value == "none" then return .NONE;
    if value == "full" then return .FULL;
    if value == "y_axis" then return .Y_AXIS;
    return .NONE;
}

scene_parse_transparency :: (
    value: string,
    default: Transparency_Mode = .ALPHA_BLEND
) -> Transparency_Mode {
    if value == "disabled" then return .DISABLED;
    if value == "alpha_scissor" then return .ALPHA_SCISSOR;
    if value == "alpha_blend" then return .ALPHA_BLEND;
    log_warning("Unknown transparency mode '%', keeping previous value", value);
    return default;
}

scene_toml_get_transparency :: (
    table: Toml.Value,
    default: Transparency_Mode
) -> Transparency_Mode {
    value := scene_toml_get_string(table, "transparency", "");
    if value then return scene_parse_transparency(value, default);

    return default;
}

scene_toml_find :: (table: Toml.Value, key: string) -> bool, Toml.Value {
    if table.kind != .TABLE then return false, .{};

    for entry: table.table {
        if entry.key == key {
            return true, entry.value;
        }
    }

    return false, .{};
}

scene_toml_get_string :: (table: Toml.Value, key: string, default: string) -> string {
    found, value := scene_toml_find(table, key);
    if !found || value.kind != .STRING then return default;
    return value.string_value;
}

scene_toml_get_bool :: (table: Toml.Value, key: string, default: bool) -> bool {
    found, value := scene_toml_find(table, key);
    if !found || value.kind != .BOOL then return default;
    return value.bool_value;
}

scene_toml_get_int :: (table: Toml.Value, key: string, default: s32) -> s32 {
    found, value := scene_toml_find(table, key);
    if !found then return default;
    if value.kind == .INT then return cast(s32) value.int_value;
    if value.kind == .FLOAT then return cast(s32) value.float_value;
    return default;
}

scene_toml_get_float :: (table: Toml.Value, key: string, default: float) -> float {
    found, value := scene_toml_find(table, key);
    if !found then return default;
    return scene_toml_number(value, default);
}

scene_toml_get_vec2 :: (table: Toml.Value, key: string, default: Vector2) -> Vector2 {
    found, value := scene_toml_find(table, key);
    if !found || value.kind != .ARRAY || value.array.count < 2 then return default;

    return .{
        scene_toml_number(value.array[0], default.x),
        scene_toml_number(value.array[1], default.y)
    };
}

scene_toml_get_vec3 :: (table: Toml.Value, key: string, default: Vector3) -> Vector3 {
    found, value := scene_toml_find(table, key);
    if !found || value.kind != .ARRAY || value.array.count < 3 then return default;

    return .{
        scene_toml_number(value.array[0], default.x),
        scene_toml_number(value.array[1], default.y),
        scene_toml_number(value.array[2], default.z)
    };
}

scene_toml_get_vec4 :: (table: Toml.Value, key: string, default: Vector4) -> Vector4 {
    found, value := scene_toml_find(table, key);
    if !found || value.kind != .ARRAY || value.array.count < 4 then return default;

    return .{
        scene_toml_number(value.array[0], default.x),
        scene_toml_number(value.array[1], default.y),
        scene_toml_number(value.array[2], default.z),
        scene_toml_number(value.array[3], default.w)
    };
}

scene_toml_number :: (value: Toml.Value, default: float) -> float {
    if value.kind == .FLOAT then return cast(float) value.float_value;
    if value.kind == .INT then return cast(float) value.int_value;
    return default;
}
