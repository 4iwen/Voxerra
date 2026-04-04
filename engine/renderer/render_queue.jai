#scope_file

#import "Basic";
#import "Math";
#import "Sort";

#scope_export

Render_Item :: struct {
    mesh: *Mesh;
    material: *Material;
    world_matrix: Matrix4;
    world_position: Vector3;
    is_transparent: bool;
    distance_squared_to_camera: float; // used for sorting
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
    world_position: Vector3
) {
    assert(queue != null, "render_queue_submit: queue is null");
    assert(mesh != null, "render_queue_submit: mesh is null");
    assert(material != null, "render_queue_submit: material is null");

    item: Render_Item;
    item.mesh = mesh;
    item.material = material;
    item.world_matrix = world_matrix;
    item.world_position = world_position;
    item.is_transparent = material.blend_mode != .OPAQUE;

    if item.is_transparent {
        array_add(*queue.transparent, item);
    } else {
        array_add(*queue.opaque, item);
    }
}

render_queue_submit :: (
    queue: *Render_Queue,
    scene: *Scene
) {
    assert(queue != null, "render_queue_submit: queue is null");
    assert(scene != null, "render_queue_submit: scene is null");
    assert(scene.root != null, "render_queue_submit: scene.root is null");
    
    submit_node(scene.root, queue);
}

render_queue_flush :: (
    queue: *Render_Queue,
    camera: *Camera
) {
    assert(queue != null, "render_queue_flush: queue is null");
    assert(camera != null, "render_queue_flush: camera is null");

    // sort transparent back-to-front
    for * queue.transparent {
        it.distance_squared_to_camera = length_squared(camera.position - it.world_position);
    }
    quick_sort(
        queue.transparent,
        (a, b) => b.distance_squared_to_camera - a.distance_squared_to_camera
    );

    // sort opaque front-to-back
    for * queue.opaque {
        it.distance_squared_to_camera = length_squared(camera.position - it.world_position);
    }
    quick_sort(
        queue.opaque,
        (a, b) => a.distance_squared_to_camera - b.distance_squared_to_camera
    );

    // draw opaque
    for queue.opaque {
        render_item_draw(*it, camera, *queue.light_system);
    }

    // draw transparent
    for queue.transparent {
        render_item_draw(*it, camera, *queue.light_system);
    }

    // clear stuff that has been drawn
    array_reset(*queue.opaque);
    array_reset(*queue.transparent);
    array_reset(*queue.light_system.lights);
}

#scope_file

submit_node :: (node: *Node, queue: *Render_Queue) {
    if !node.active then return;

    mesh_comp := node_get_component(node, Static_Mesh_Component);
    if mesh_comp != null && mesh_comp.mesh != null && mesh_comp.material != null {
        render_queue_submit(queue, mesh_comp.mesh, mesh_comp.material, node.world_matrix, node.world_position);
    }

    light_comp := node_get_component(node, Light_Component);
    if light_comp != null {
        light := light_comp.light;
        
        light.position = (node.world_matrix * Vector4.{0, 0, 0, 1}).xyz;
        
        // -z as front 
        forward := Vector4.{0, 0, -1, 0};
        world_dir := (node.world_matrix * forward).xyz;
        light.direction = normalize(world_dir);

        array_add(*queue.light_system.lights, light);
    }

    for node.children {
        submit_node(it, queue);
    }
}

render_item_draw :: (
    item: *Render_Item,
    camera: *Camera,
    lights: *Light_System
) {
    assert(item != null, "render_item_draw: item is null");
    assert(camera != null, "render_item_draw: camera is null");

    using engine_state;

    shader := item.material.shader;

    // bind shader
    shader_use(shader);

    // set camera properties
    shader_set_mat4(shader, "u_view", camera_get_view_matrix(camera));
    aspect := 1.0;
    if main_framebuffer {
        aspect = main_framebuffer.aspect;
    } else {
        aspect = cast(float) window.width / cast(float) window.height;
    }
    shader_set_mat4(shader, "u_projection", camera_get_projection_matrix(camera, aspect));

    // set item properties
    shader_set_mat4(shader, "u_model", item.world_matrix);
    
    material_use(item.material);

    shader_set_vec3(shader, "u_view_position", camera.position);

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
}
