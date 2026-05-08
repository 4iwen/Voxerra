// File:        render_queue.jai
// Author:      Lukáš Bien
// Description: Builds render queues from scene nodes and submits opaque and transparent draw calls.

#scope_file

#import "Basic";
#import "Math";
#import "Sort";

#scope_export

Render_Item :: struct {
    kind: Render_Item_Kind;
    mesh: *Mesh;
    material: *Material;
    material_override: *Model_Material_Override;
    sprite: *Sprite_Component;
    world_matrix: Matrix4;
    world_position: Vector3;
    is_transparent: bool;
    transparency: Transparency_Mode;
    distance_squared_to_camera: float; // used for sorting
}

Render_Item_Kind :: enum {
    MESH;
    SPRITE;
}

Render_Queue :: struct {
    opaque: [..] Render_Item;
    transparent: [..] Render_Item;
    light_system: Light_System;
}

render_queue_create :: () -> *Render_Queue {
    queue := New(Render_Queue);
    return queue;
}

render_queue_destroy :: (queue: *Render_Queue) {
    assert(queue != null, "render_queue_destroy: queue is null");

    array_free(queue.opaque);
    array_free(queue.transparent);
    array_free(queue.light_system.lights);
    free(queue);
}

render_queue_clear :: (queue: *Render_Queue) {
    array_reset(*queue.opaque);
    array_reset(*queue.transparent);
    array_reset(*queue.light_system.lights);
}

render_queue_submit :: (
    queue: *Render_Queue,
    mesh: *Mesh,
    material: *Material,
    world_matrix: Matrix4,
    world_position: Vector3,
    material_override: *Model_Material_Override = null
) {
    assert(queue != null, "render_queue_submit: queue is null");
    assert(mesh != null, "render_queue_submit: mesh is null");
    assert(material != null, "render_queue_submit: material is null");

    item: Render_Item;
    item.kind = .MESH;
    item.mesh = mesh;
    item.material = material;
    item.material_override = material_override;
    item.sprite = null;
    item.world_matrix = world_matrix;
    item.world_position = world_position;
    resolved := material_resolve(material, material_override);
    item.transparency = resolved.transparency;
    item.is_transparent = material_is_alpha_blend(resolved);

    if item.is_transparent {
        array_add(*queue.transparent, item);
    } else {
        array_add(*queue.opaque, item);
    }
}

render_queue_submit :: (
    queue: *Render_Queue,
    sprite: *Sprite_Component,
    world_matrix: Matrix4,
    world_position: Vector3
) {
    assert(queue != null, "render_queue_submit: queue is null");
    assert(sprite != null, "render_queue_submit: sprite is null");

    item: Render_Item;
    item.kind = .SPRITE;
    item.mesh = sprite_system_get_quad_mesh();
    item.material = null;
    item.material_override = null;
    item.sprite = sprite;
    item.world_matrix = world_matrix;
    item.world_position = world_position;
    item.transparency = sprite.transparency;
    item.is_transparent = sprite_is_alpha_blend(sprite);

    if item.is_transparent {
        array_add(*queue.transparent, item);
    } else {
        array_add(*queue.opaque, item);
    }
}

render_queue_submit :: (
    queue: *Render_Queue,
    scene: *Scene,
    include_lights: bool = true
) {
    assert(queue != null, "render_queue_submit: queue is null");
    assert(scene != null, "render_queue_submit: scene is null");
    assert(scene.root != null, "render_queue_submit: scene.root is null");

    queue.light_system.ambient_color = scene.ambient_color;

    submit_node(scene.root, queue, include_lights);
}

#scope_file

submit_node :: (node: *Node, queue: *Render_Queue, include_lights: bool) {
    if !node.active then return;

    mesh_comp := node_get_component(node, Static_Mesh_Component);
    if mesh_comp != null && mesh_comp.mesh != null && mesh_comp.material != null {
        center := (mesh_comp.mesh.bounds_min + mesh_comp.mesh.bounds_max) * 0.5;
        world_center := (node.world_matrix * Vector4.{center.x, center.y, center.z, 1.0}).xyz;

        render_queue_submit(queue, mesh_comp.mesh, mesh_comp.material, node.world_matrix, world_center);
    }

    model_component := node_get_component(node, Model_Component);
    if model_component != null && model_component.model_resource != null {
        mesh_world_matrix := node.world_matrix * model_component.model_local_matrix;
        for submesh: model_component.model_resource.submeshes {
            if submesh.mesh && submesh.material {
                material_override := model_component_find_material_override(model_component, submesh.material_index);

                center := (submesh.mesh.bounds_min + submesh.mesh.bounds_max) * 0.5;
                world_center := (mesh_world_matrix * Vector4.{center.x, center.y, center.z, 1.0}).xyz;

                render_queue_submit(
                    queue,
                    submesh.mesh,
                    submesh.material,
                    mesh_world_matrix,
                    world_center,
                    material_override
                );
            }
        }
    }

    sprite_comp := node_get_sprite_component(node);
    if sprite_comp != null {
        render_queue_submit(
            queue,
            sprite_comp,
            sprite_comp.render_matrix,
            node.world_position
        );
    }

    light_comp := node_get_component(node, Light_Component);
    if include_lights && light_comp != null {
        light := light_comp.light;
        
        light.position = (node.world_matrix * Vector4.{0, 0, 0, 1}).xyz;
        
        // -z as front 
        forward := Vector4.{0, 0, -1, 0};
        world_dir := (node.world_matrix * forward).xyz;
        light.direction = normalize(world_dir);

        array_add(*queue.light_system.lights, light);
    }

    for node.children {
        submit_node(it, queue, include_lights);
    }
}

render_item_draw :: (
    item: *Render_Item,
    camera: *Camera,
    lights: *Light_System,
    aspect: float,
    shader_fog_enabled: bool
) {
    assert(item != null, "render_item_draw: item is null");
    assert(camera != null, "render_item_draw: camera is null");

    if item.kind == .SPRITE {
        render_sprite_item(item, camera, aspect, shader_fog_enabled);
        return;
    }

    material := material_resolve(item.material, item.material_override);
    shader := material.shader;
    is_alpha_blend := material_is_alpha_blend(material);

    renderer_set_blending(is_alpha_blend);
    renderer_set_depth_write(!is_alpha_blend);
    renderer_set_culling(!material.double_sided);

    // bind shader
    shader_use(shader);

    // set camera properties
    shader_set_mat4(shader, "u_view", camera_get_view_matrix(camera));
    shader_set_mat4(shader, "u_projection", camera_get_projection_matrix(camera, aspect));

    // set item properties
    shader_set_mat4(shader, "u_model", item.world_matrix);

    material_use_resolved(material);

    shader_set_vec3(shader, "u_view_position", camera.position);
    shader_set_int(shader, "u_render_mode", cast(s32) renderer_get_view_mode());
    fog_upload_shader_uniforms(shader, shader_fog_enabled);

    if lights {
        light_upload_to_shader(shader, lights);
    } else {
        // default if no light system provided
        shader_set_vec3(shader, "u_global_ambient", .{0.1, 0.1, 0.1});
        shader_set_int(shader, "u_point_light_count", 0);
        shader_set_int(shader, "u_spot_light_count", 0);
        shader_set_int(shader, "u_has_directional_light", 0);
    }

    // draw
    mesh_draw(item.mesh);

    renderer_set_culling(true);
    renderer_set_depth_write(true);
    renderer_set_blending(true);
}

render_sprite_item :: (
    item: *Render_Item,
    camera: *Camera,
    aspect: float,
    shader_fog_enabled: bool
) {
    assert(item != null, "render_sprite_item: item is null");
    assert(camera != null, "render_sprite_item: camera is null");
    assert(item.sprite != null, "render_sprite_item: sprite is null");

    sprite := item.sprite;
    shader := sprite_system_resolve_shader(sprite);
    texture := sprite_system_resolve_texture(sprite);
    is_alpha_blend := sprite_is_alpha_blend(sprite);

    renderer_set_blending(is_alpha_blend);
    renderer_set_depth_write(!is_alpha_blend);
    renderer_set_culling(false);

    shader_use(shader);
    shader_set_mat4(shader, "u_view", camera_get_view_matrix(camera));

    shader_set_mat4(shader, "u_projection", camera_get_projection_matrix(camera, aspect));
    shader_set_mat4(shader, "u_model", item.world_matrix);

    texture_bind(texture, 0);
    texture_bind(asset_manager_get_default_texture(), 1);

    shader_set_int(shader, "u_material.diffuse", 0);
    shader_set_int(shader, "u_material.specular", 1);
    shader_set_vec3(shader, "u_material.diffuse_color", .{1.0, 1.0, 1.0});
    shader_set_vec3(shader, "u_material.specular_color", .{1.0, 1.0, 1.0});
    shader_set_vec3(shader, "u_material.tint", sprite.tint_color);
    shader_set_float(shader, "u_material.shininess", 1.0);
    shader_set_float(shader, "u_material.alpha", sprite.alpha);
    shader_set_float(shader, "u_material.alpha_cutoff", sprite.alpha_cutoff);
    shader_set_mat3(shader, "u_material.uv_transform", sprite.uv_transform);
    shader_set_mat3(shader, "u_uv_transform", sprite.uv_transform);
    shader_set_int(shader, "u_material.transparency", cast(s32) sprite.transparency);

    shader_set_vec3(shader, "u_view_position", camera.position);
    shader_set_int(shader, "u_render_mode", cast(s32) renderer_get_view_mode());
    fog_upload_shader_uniforms(shader, shader_fog_enabled);

    mesh_draw(item.mesh);

    renderer_set_culling(true);
    renderer_set_depth_write(true);
    renderer_set_blending(true);
}

#scope_export

render_queue_flush_opaque :: (
    queue: *Render_Queue,
    camera: *Camera,
    aspect: float = 1.0,
    shader_fog_enabled: bool = true
) {
    assert(queue != null, "render_queue_flush_opaque: queue is null");
    assert(camera != null, "render_queue_flush_opaque: camera is null");

    for * queue.opaque {
        it.distance_squared_to_camera = length_squared(camera.position - it.world_position);
    }
    quick_sort(
        queue.opaque,
        (a, b) => a.distance_squared_to_camera - b.distance_squared_to_camera
    );

    for queue.opaque {
        render_item_draw(*it, camera, *queue.light_system, aspect, shader_fog_enabled);
    }
}

render_queue_flush_transparent :: (
    queue: *Render_Queue,
    camera: *Camera,
    aspect: float = 1.0,
    shader_fog_enabled: bool = true
) {
    assert(queue != null, "render_queue_flush_transparent: queue is null");
    assert(camera != null, "render_queue_flush_transparent: camera is null");

    for * queue.transparent {
        it.distance_squared_to_camera = length_squared(camera.position - it.world_position);
    }
    quick_sort(
        queue.transparent,
        (a, b) => b.distance_squared_to_camera - a.distance_squared_to_camera
    );

    for queue.transparent {
        render_item_draw(*it, camera, *queue.light_system, aspect, shader_fog_enabled);
    }
}
