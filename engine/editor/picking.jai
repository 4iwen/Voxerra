// File:        picking.jai
// Author:      Lukáš Bien
// Description: Renders and resolves editor picking IDs for viewport selection.

#scope_file

#import "Basic";
#import "GL";

#scope_export

Picking_Result :: struct {
    id: u32;
    node: *Node;
}

Editor_Picking_State :: struct {
    framebuffer: *Framebuffer;
    shader: *Shader;
    id_to_node: [..] *Node;
}

editor_picking_state: Editor_Picking_State;

editor_picking_init :: () {
    editor_picking_state = .{};
    editor_picking_state.shader = asset_manager_load_shader(
        "engine/assets/shaders/picking.vert",
        "engine/assets/shaders/picking.frag",
        true
    );
}

editor_picking_shutdown :: () {
    if editor_picking_state.framebuffer {
        framebuffer_destroy(editor_picking_state.framebuffer);
    }
    array_free(editor_picking_state.id_to_node);
    editor_picking_state = .{};
}

editor_picking_resize :: (width: s32, height: s32) {
    if width <= 0 || height <= 0 then return;

    if !editor_picking_state.framebuffer {
        editor_picking_state.framebuffer = framebuffer_create_with_color_format(
            width,
            height,
            GL_R32UI,
            GL_RED_INTEGER,
            GL_UNSIGNED_INT
        );
        return;
    }

    framebuffer_resize(editor_picking_state.framebuffer, width, height);
}

// rebuild the id buffer every frame so selection always matches the current
// scene graph and viewport size.
editor_picking_render :: (
    scene: *Scene,
    camera: *Camera,
    width: s32,
    height: s32
) {
    if !scene || !camera || !editor_picking_state.shader then return;
    if width <= 0 || height <= 0 then return;

    editor_picking_resize(width, height);
    framebuffer := editor_picking_state.framebuffer;
    if !framebuffer then return;

    framebuffer_bind(framebuffer);

    clear_id: [1] u32 = .[0];
    glClearBufferuiv(GL_COLOR, 0, clear_id.data);
    glClear(GL_DEPTH_BUFFER_BIT);

    renderer_set_depth_test(true);
    renderer_set_depth_write(true);
    renderer_set_blending(false);
    renderer_set_culling(true);

    array_reset(*editor_picking_state.id_to_node);
    array_add(*editor_picking_state.id_to_node, null);

    view := camera_get_view_matrix(camera.*);
    aspect := cast(float) width / cast(float) height;
    projection := camera_get_projection_matrix(camera.*, aspect);
    shader := editor_picking_state.shader;

    editor_picking_submit_node(scene.root, shader, view, projection);

    framebuffer_unbind();
    renderer_set_blending(true);
}

editor_pick_node_at_viewport_pixel :: (pixel_x: s32, pixel_y: s32) -> *Node {
    framebuffer := editor_picking_state.framebuffer;
    if !framebuffer then return null;

    if pixel_x < 0 || pixel_x >= framebuffer.pixel_width then return null;
    if pixel_y < 0 || pixel_y >= framebuffer.pixel_height then return null;

    picked_id: u32;
    glBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer.id);
    glReadPixels(
        pixel_x,
        pixel_y,
        1,
        1,
        GL_RED_INTEGER,
        GL_UNSIGNED_INT,
        *picked_id
    );
    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);

    if picked_id == 0 then return null;
    if picked_id >= cast(u32) editor_picking_state.id_to_node.count then return null;

    return editor_picking_state.id_to_node[picked_id];
}

editor_handle_viewport_selection :: () {
    if !ui_state.viewport_image_visible || !input_viewport_mouse_allowed() then return;
    if input_state.cursor_disabled then return;
    if editor_gizmo_is_over_or_using() then return;
    if !input_mouse_pressed(.LEFT) then return;

    mouse_x, mouse_y := input_mouse_position();
    if mouse_x < cast(float64) ui_state.viewport_screen_min.x ||
       mouse_x > cast(float64) ui_state.viewport_screen_max.x ||
       mouse_y < cast(float64) ui_state.viewport_screen_min.y ||
       mouse_y > cast(float64) ui_state.viewport_screen_max.y {
        return;
    }

    if editor_curve_handle_viewport_selection() {
        return;
    }

    framebuffer := editor_picking_state.framebuffer;
    if !framebuffer || ui_state.viewport_size.x <= 0 || ui_state.viewport_size.y <= 0 {
        return;
    }

    rel_x := (mouse_x - cast(float64) ui_state.viewport_screen_min.x) /
        cast(float64) ui_state.viewport_size.x;
    rel_y := (mouse_y - cast(float64) ui_state.viewport_screen_min.y) /
        cast(float64) ui_state.viewport_size.y;

    pixel_x := cast(s32) floor(rel_x * framebuffer.pixel_width);
    pixel_y := cast(s32) floor((1.0 - rel_y) * framebuffer.pixel_height);
    pixel_x = clamp(pixel_x, 0, framebuffer.pixel_width - 1);
    pixel_y = clamp(pixel_y, 0, framebuffer.pixel_height - 1);

    picked_node := editor_pick_node_at_viewport_pixel(pixel_x, pixel_y);
    if !picked_node {
        if selected_node {
            editor_gizmo_suppress_until_lmb_release();
            editor_select_node(null);
        }
        return;
    }

    if picked_node != selected_node {
        editor_gizmo_suppress_until_lmb_release();
    }
    editor_select_node(picked_node);
}

#scope_file

// assign one stable pick id per logical node, then draw every renderable
// representation that should resolve back to it.
editor_picking_submit_node :: (
    node: *Node,
    shader: *Shader,
    view: Matrix4,
    projection: Matrix4
) {
    if !node || !node.active then return;

    mesh_component := node_get_component(node, Static_Mesh_Component);
    if mesh_component && mesh_component.mesh && mesh_component.material {
        object_id := cast(s32) editor_picking_state.id_to_node.count;
        array_add(*editor_picking_state.id_to_node, editor_picking_get_selectable_node(node));
        editor_picking_draw_mesh(
            mesh_component.mesh,
            mesh_component.material,
            node.world_matrix,
            shader,
            view,
            projection,
            object_id
        );
    }

    model_component := node_get_component(node, Model_Component);
    if model_component && model_component.model_resource {
        object_id := cast(s32) editor_picking_state.id_to_node.count;
        array_add(*editor_picking_state.id_to_node, editor_picking_get_selectable_node(node));
        mesh_world_matrix := node.world_matrix * model_component.model_local_matrix;

        for submesh: model_component.model_resource.submeshes {
            if submesh.mesh && submesh.material {
                material_override := model_component_find_material_override(model_component, submesh.material_index);
                editor_picking_draw_mesh(
                    submesh.mesh,
                    submesh.material,
                    mesh_world_matrix,
                    shader,
                    view,
                    projection,
                    object_id,
                    material_override
                );
            }
        }
    }

    sprite_component := node_get_sprite_component(node);
    if sprite_component {
        object_id := cast(s32) editor_picking_state.id_to_node.count;
        array_add(*editor_picking_state.id_to_node, editor_picking_get_selectable_node(node));
        editor_picking_draw_sprite(
            sprite_component,
            shader,
            view,
            projection,
            object_id
        );
    }

    for node.children {
        editor_picking_submit_node(it, shader, view, projection);
    }
}

editor_picking_get_selectable_node :: (node: *Node) -> *Node {
    if !node then return null;

    current := node;
    while current.inherited_from_instance && current.parent {
        current = current.parent;
    }

    return current;
}

editor_picking_draw_mesh :: (
    mesh: *Mesh,
    material: *Material,
    world_matrix: Matrix4,
    shader: *Shader,
    view: Matrix4,
    projection: Matrix4,
    object_id: s32,
    material_override: *Model_Material_Override = null
) {
    shader_use(shader);
    shader_set_mat4(shader, "u_model", world_matrix);
    shader_set_mat4(shader, "u_view", view);
    shader_set_mat4(shader, "u_projection", projection);
    shader_set_int(shader, "u_object_id", object_id);

    material_resolved := material_resolve(material, material_override);
    use_alpha_test := material_uses_alpha_test(material_resolved);
    alpha_cutoff := material_pick_alpha_cutoff(material_resolved);
    material_alpha := material_pick_alpha(material_resolved);

    if material_resolved.diffuse_map {
        texture_bind(material_resolved.diffuse_map, 0);
    } else {
        texture_bind(asset_manager_get_default_texture(), 0);
    }

    shader_set_int(shader, "u_diffuse", 0);
    shader_set_int(shader, "u_use_alpha_test", cast(s32) use_alpha_test);
    shader_set_float(shader, "u_alpha_cutoff", alpha_cutoff);
    shader_set_float(shader, "u_material_alpha", material_alpha);
    shader_set_mat3(shader, "u_uv_transform", material_resolved.uv_transform);

    renderer_set_culling(!material_resolved.double_sided);
    mesh_draw(mesh);
    renderer_set_culling(true);
}

editor_picking_draw_sprite :: (
    sprite: *Sprite_Component,
    shader: *Shader,
    view: Matrix4,
    projection: Matrix4,
    object_id: s32
) {
    assert(sprite != null, "editor_picking_draw_sprite: sprite is null");

    shader_use(shader);
    shader_set_mat4(shader, "u_model", sprite.render_matrix);
    shader_set_mat4(shader, "u_view", view);
    shader_set_mat4(shader, "u_projection", projection);
    shader_set_int(shader, "u_object_id", object_id);

    texture_bind(sprite_system_resolve_texture(sprite), 0);

    use_alpha_test := sprite_uses_alpha_test(sprite);
    alpha_cutoff := sprite_pick_alpha_cutoff(sprite);
    material_alpha := sprite_pick_alpha(sprite);

    shader_set_int(shader, "u_diffuse", 0);
    shader_set_int(shader, "u_use_alpha_test", cast(s32) use_alpha_test);
    shader_set_float(shader, "u_alpha_cutoff", alpha_cutoff);
    shader_set_float(shader, "u_material_alpha", material_alpha);
    shader_set_mat3(shader, "u_uv_transform", sprite.uv_transform);

    renderer_set_culling(false);
    mesh_draw(sprite_system_get_quad_mesh());
    renderer_set_culling(true);
}
