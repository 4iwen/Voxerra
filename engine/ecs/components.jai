// File:        components.jai
// Author:      Lukáš Bien
// Description: Defines the ECS component types used by scenes, rendering, and the editor.

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
    
    mesh: *Mesh; @"Tooltip(\"The 3D mesh to render for this object\")"
    material: *Material; @"Tooltip(\"The material used to render the mesh\")"
}

Model_Material_Override :: struct {
    material_index: s32;
    enabled: bool = true;
    diffuse_color: Vector3 = .{1.0, 1.0, 1.0}; @Color
    specular_color: Vector3 = .{1.0, 1.0, 1.0}; @Color
    tint_color: Vector3 = .{1.0, 1.0, 1.0}; @Color
    diffuse_map: *Texture; @Hidden
    diffuse_texture_path: string; @Hidden
    diffuse_texture_guid: string; @Hidden
    diffuse_texture_ref: Asset_Ref; @Hidden
    specular_map: *Texture; @Hidden
    specular_texture_path: string; @Hidden
    specular_texture_guid: string; @Hidden
    specular_texture_ref: Asset_Ref; @Hidden
    shininess: float = 32.0; @"Speed(1)"
    alpha: float = 1.0; @"Range(0, 1)" @"Speed(0.01)"
    alpha_cutoff: float = 0.5; @"Range(0, 1)" @"Speed(0.01)"
    uv_transform: Matrix3;
    transparency: Transparency_Mode = .DISABLED;
    double_sided: bool;
}

Model_Component :: struct @Component {
    #as using base: Component;
    base.type = Model_Component;

    model_path: string; @"Tooltip(\"Source model asset path\")"
    model_guid: string; @Hidden

    model_ref: Asset_Ref; @Hidden
    model_resource: *Model; @Hidden
    model_local_matrix: Matrix4; @Hidden
    material_overrides: [..] Model_Material_Override; @Hidden
}

model_material_override_from_material :: (material_index: s32, material: *Material) -> Model_Material_Override {
    override: Model_Material_Override;
    override.material_index = material_index;
    override.enabled = true;

    if material {
        override.diffuse_color = material.diffuse_color;
        override.specular_color = material.specular_color;
        override.tint_color = material.tint_color;
        override.diffuse_map = material.diffuse_map;
        override.specular_map = material.specular_map;
        override.shininess = material.shininess;
        override.alpha = material.alpha;
        override.alpha_cutoff = material.alpha_cutoff;
        override.uv_transform = material.uv_transform;
        override.transparency = material.transparency;
        override.double_sided = material.double_sided;
    } else {
        override.uv_transform = Matrix3_Identity;
    }

    return override;
}

model_component_find_material_override :: (
    model_component: *Model_Component,
    material_index: s32
) -> *Model_Material_Override {
    if !model_component || material_index < 0 then return null;

    for * override: model_component.material_overrides {
        if override.material_index == material_index {
            return override;
        }
    }

    return null;
}

model_component_ensure_material_override :: (
    model_component: *Model_Component,
    material_index: s32,
    material: *Material
) -> *Model_Material_Override {
    if !model_component || material_index < 0 then return null;

    existing := model_component_find_material_override(model_component, material_index);
    if existing then return existing;

    override := model_material_override_from_material(material_index, material);
    array_add(*model_component.material_overrides, override);
    return *model_component.material_overrides[model_component.material_overrides.count - 1];
}

model_component_remove_material_override :: (
    model_component: *Model_Component,
    material_index: s32
) -> bool {
    if !model_component || material_index < 0 then return false;

    for override: model_component.material_overrides {
        if override.material_index == material_index {
            model_material_override_destroy(*model_component.material_overrides[it_index]);
            array_ordered_remove_by_index(*model_component.material_overrides, it_index);
            return true;
        }
    }

    return false;
}

model_component_clear_material_overrides :: (model_component: *Model_Component) {
    if !model_component then return;
    for * override: model_component.material_overrides {
        model_material_override_destroy(override);
    }
    array_reset(*model_component.material_overrides);
}

model_material_override_destroy :: (override: *Model_Material_Override) {
    if !override then return;

    asset_ref_release(*override.diffuse_texture_ref);
    free(override.diffuse_texture_path);
    free(override.diffuse_texture_guid);

    asset_ref_release(*override.specular_texture_ref);
    free(override.specular_texture_path);
    free(override.specular_texture_guid);
}

Light_Component :: struct @Component {
    #as using base: Component;
    base.type = Light_Component;
    
    light: Light; @Inline
}

Camera_Component :: struct @Component {
    #as using base: Component;
    base.type = Camera_Component;

    camera: Camera; @Inline
}

Curve_Component :: struct @Component {
    #as using base: Component;
    base.type = Curve_Component;

    closed: bool;
    points: [..] Vector3; @Hidden
}

Curve_Follower_Orientation :: enum {
    NONE;
    Y_AXIS;
    FULL;
}

Curve_Follower_Component :: struct @Component {
    #as using base: Component;
    base.type = Curve_Follower_Component;

    enabled: bool = true;
    curve_node_scene_id: string; @Hidden
    curve_node_runtime_id: u64; @Hidden
    speed: float = 0.025; @"Speed(0.001)"
    loop: bool = true;
    start_offset: float; @"Range(0, 1)" @"Speed(0.01)"
    orientation: Curve_Follower_Orientation = .Y_AXIS;
    yaw_offset: float; @"Speed(0.01)"

    progress: float64; @Hidden
}

Sprite_Pivot :: enum {
    TOP_LEFT;
    TOP_CENTER;
    TOP_RIGHT;
    CENTER_LEFT;
    CENTER;
    CENTER_RIGHT;
    BOTTOM_LEFT;
    BOTTOM_CENTER;
    BOTTOM_RIGHT;
}

Sprite_Billboard_Mode :: enum {
    NONE;
    Y_AXIS;
    FULL;
}

Sprite_Component :: struct @Component {
    #as using component: Component;
    component.type = Sprite_Component;

    texture: *Texture; @"Tooltip(\"Texture used by this sprite\")"
    texture_path: string; @"Tooltip(\"Source texture asset path\")"
    texture_guid: string; @"Tooltip(\"Stable texture asset GUID\")"
    texture_filter: string; @"Tooltip(\"Texture filtering mode used when resolving the texture\")"
    texture_ref: Asset_Ref; @Hidden
    shader: *Shader; @"Tooltip(\"Optional override shader. Uses engine sprite shader when empty\")"
    tint_color: Vector3 = .{1, 1, 1}; @Color @"Tooltip(\"Tint multiplied into sprite color\")"
    alpha: float = 1.0; @"Tooltip(\"Overall sprite alpha\")"
    alpha_cutoff: float = 0.1; @"Tooltip(\"Alpha threshold used for cutout and picking\")"
    size: Vector2 = .{1.0, 1.0}; @"Tooltip(\"Sprite width and height in world units\")"
    pivot: Sprite_Pivot = .CENTER; @"Tooltip(\"How sprite quad is anchored to node origin\")"
    custom_pivot_enabled: bool = false; @"Tooltip(\"Use custom normalized pivot instead of the preset\")"
    custom_pivot: Vector2 = .{0.5, 0.5}; @"Tooltip(\"Custom normalized pivot, where 0,0 is bottom-left and 1,1 is top-right\")"
    billboard_mode: Sprite_Billboard_Mode = .NONE; @"Tooltip(\"How sprite rotates to face camera\")"
    transparency: Transparency_Mode = .ALPHA_BLEND; @"Tooltip(\"Sprite transparency mode\")"
    uv_transform: Matrix3;

    render_matrix: Matrix4;
}

Animated_Sprite_Component :: struct @Component {
    #as using base: Sprite_Component;
    base.component.type = Animated_Sprite_Component;

    columns: s32 = 1; @"Tooltip(\"Number of columns in sprite sheet\")"
    rows: s32 = 1; @"Tooltip(\"Number of rows in sprite sheet\")"
    frame_count: s32 = 1; @"Tooltip(\"Total frames used from sheet\")"
    fps: float = 8.0; @"Tooltip(\"Playback speed in frames per second\")"
    playing: bool = true; @"Tooltip(\"Whether animation is advancing\")"
    loop: bool = true; @"Tooltip(\"Whether animation restarts after last frame\")"
    current_frame: s32; @"Tooltip(\"Current frame index\")"

    frame_accumulator: float64;
}

component_clone :: (
    component: *Component,
    node: *Node,
    active_camera_source: *Camera = null,
    active_camera_result: **Camera = null
) -> *Component {
    if !component || !node then return null;

    if component.type == Static_Mesh_Component {
        source := cast(*Static_Mesh_Component) component;
        clone := node_add_component(node, Static_Mesh_Component);
        clone.mesh = source.mesh;
        clone.material = source.material;
        return cast(*Component) clone;
    }

    if component.type == Model_Component {
        source := cast(*Model_Component) component;
        clone := node_add_component(node, Model_Component);
        clone.model_path = copy_string(source.model_path);
        clone.model_guid = copy_string(source.model_guid);
        asset_ref_clone(*source.model_ref, *clone.model_ref);
        clone.model_resource = source.model_resource;
        clone.model_local_matrix = source.model_local_matrix;
        for source.material_overrides {
            override := it;
            override.diffuse_texture_path = copy_string(it.diffuse_texture_path);
            override.diffuse_texture_guid = copy_string(it.diffuse_texture_guid);
            asset_ref_clone(*it.diffuse_texture_ref, *override.diffuse_texture_ref);
            override.specular_texture_path = copy_string(it.specular_texture_path);
            override.specular_texture_guid = copy_string(it.specular_texture_guid);
            asset_ref_clone(*it.specular_texture_ref, *override.specular_texture_ref);
            array_add(*clone.material_overrides, override);
        }
        return cast(*Component) clone;
    }

    if component.type == Light_Component {
        source := cast(*Light_Component) component;
        clone := node_add_component(node, Light_Component);
        clone.light = source.light;
        return cast(*Component) clone;
    }

    if component.type == Camera_Component {
        source := cast(*Camera_Component) component;
        clone := node_add_component(node, Camera_Component);
        clone.camera = source.camera;
        if active_camera_source && active_camera_result && active_camera_source == *source.camera {
            active_camera_result.* = *clone.camera;
        }
        return cast(*Component) clone;
    }

    if component.type == Curve_Component {
        source := cast(*Curve_Component) component;
        clone := node_add_component(node, Curve_Component);
        clone.closed = source.closed;
        for source.points {
            array_add(*clone.points, it);
        }
        return cast(*Component) clone;
    }

    if component.type == Curve_Follower_Component {
        source := cast(*Curve_Follower_Component) component;
        clone := node_add_component(node, Curve_Follower_Component);
        clone.enabled = source.enabled;
        clone.curve_node_scene_id = copy_string(source.curve_node_scene_id);
        clone.speed = source.speed;
        clone.loop = source.loop;
        clone.start_offset = source.start_offset;
        clone.orientation = source.orientation;
        clone.yaw_offset = source.yaw_offset;
        return cast(*Component) clone;
    }

    if component.type == Sprite_Component {
        source := cast(*Sprite_Component) component;
        clone := node_add_component(node, Sprite_Component);
        clone.texture = source.texture;
        clone.texture_path = copy_string(source.texture_path);
        clone.texture_guid = copy_string(source.texture_guid);
        clone.texture_filter = copy_string(source.texture_filter);
        asset_ref_clone(*source.texture_ref, *clone.texture_ref);
        clone.shader = source.shader;
        clone.tint_color = source.tint_color;
        clone.alpha = source.alpha;
        clone.alpha_cutoff = source.alpha_cutoff;
        clone.size = source.size;
        clone.pivot = source.pivot;
        clone.custom_pivot_enabled = source.custom_pivot_enabled;
        clone.custom_pivot = source.custom_pivot;
        clone.billboard_mode = source.billboard_mode;
        clone.transparency = source.transparency;
        clone.uv_transform = source.uv_transform;
        clone.render_matrix = source.render_matrix;
        return cast(*Component) clone;
    }

    if component.type == Animated_Sprite_Component {
        source := cast(*Animated_Sprite_Component) component;
        clone := node_add_component(node, Animated_Sprite_Component);
        clone.texture = source.texture;
        clone.texture_path = copy_string(source.texture_path);
        clone.texture_guid = copy_string(source.texture_guid);
        clone.texture_filter = copy_string(source.texture_filter);
        asset_ref_clone(*source.texture_ref, *clone.texture_ref);
        clone.shader = source.shader;
        clone.tint_color = source.tint_color;
        clone.alpha = source.alpha;
        clone.alpha_cutoff = source.alpha_cutoff;
        clone.size = source.size;
        clone.pivot = source.pivot;
        clone.custom_pivot_enabled = source.custom_pivot_enabled;
        clone.custom_pivot = source.custom_pivot;
        clone.billboard_mode = source.billboard_mode;
        clone.transparency = source.transparency;
        clone.uv_transform = source.uv_transform;
        clone.render_matrix = source.render_matrix;
        clone.columns = source.columns;
        clone.rows = source.rows;
        clone.frame_count = source.frame_count;
        clone.fps = source.fps;
        clone.playing = source.playing;
        clone.loop = source.loop;
        clone.current_frame = source.current_frame;
        clone.frame_accumulator = source.frame_accumulator;
        return cast(*Component) clone;
    }

    return null;
}

component_destroy :: (component: *Component) {
    if !component then return;

    if component.type == Model_Component {
        source := cast(*Model_Component) component;
        model_component_clear_material_overrides(source);
        asset_ref_release(*source.model_ref);
        free(source.model_path);
        free(source.model_guid);
        array_free(source.material_overrides);
    } else if component.type == Sprite_Component {
        source := cast(*Sprite_Component) component;
        asset_ref_release(*source.texture_ref);
        free(source.texture_path);
        free(source.texture_guid);
        free(source.texture_filter);
    } else if component.type == Animated_Sprite_Component {
        source := cast(*Animated_Sprite_Component) component;
        asset_ref_release(*source.texture_ref);
        free(source.texture_path);
        free(source.texture_guid);
        free(source.texture_filter);
    } else if component.type == Curve_Component {
        source := cast(*Curve_Component) component;
        array_free(source.points);
    } else if component.type == Curve_Follower_Component {
        source := cast(*Curve_Follower_Component) component;
        free(source.curve_node_scene_id);
    }

    free(component);
}

node_get_sprite_component :: (node: *Node) -> *Sprite_Component {
    if !node then return null;

    animated_sprite := node_get_component(node, Animated_Sprite_Component);
    if animated_sprite {
        return cast(*Sprite_Component) animated_sprite;
    }

    return node_get_component(node, Sprite_Component);
}

node_get_animated_sprite_component :: (node: *Node) -> *Animated_Sprite_Component {
    if !node then return null;
    return node_get_component(node, Animated_Sprite_Component);
}

curve_component_add_point :: (curve: *Curve_Component, point: Vector3) -> s32 {
    if !curve then return -1;
    array_add(*curve.points, point);
    return cast(s32) curve.points.count - 1;
}

curve_component_insert_point :: (curve: *Curve_Component, index: s32, point: Vector3) -> s32 {
    if !curve then return -1;

    insert_index := clamp(index, 0, cast(s32) curve.points.count);
    array_insert_at(*curve.points, point, insert_index);
    return insert_index;
}

curve_component_remove_point :: (curve: *Curve_Component, index: s32) -> bool {
    if !curve then return false;
    if index < 0 || index >= cast(s32) curve.points.count then return false;

    array_ordered_remove_by_index(*curve.points, index);
    return true;
}

// move points through remove+insert so the serialized order always matches
// what the inspector shows.
curve_component_move_point :: (curve: *Curve_Component, index: s32, offset: s32) -> s32 {
    if !curve then return -1;
    if index < 0 || index >= cast(s32) curve.points.count then return -1;

    new_index := clamp(index + offset, 0, cast(s32) curve.points.count - 1);
    if new_index == index then return index;

    point := curve.points[index];
    array_ordered_remove_by_index(*curve.points, index);
    array_insert_at(*curve.points, point, new_index);
    return new_index;
}

node_get_curve_component :: (node: *Node) -> *Curve_Component {
    if !node then return null;
    return node_get_component(node, Curve_Component);
}

node_get_curve_follower_component :: (node: *Node) -> *Curve_Follower_Component {
    if !node then return null;
    return node_get_component(node, Curve_Follower_Component);
}
