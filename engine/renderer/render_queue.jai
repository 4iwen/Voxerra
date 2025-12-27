#scope_file

#import "Basic";

#scope_export

Render_Item :: struct {
    mesh: Mesh;
    shader: Shader;
    texture: Texture;
    transform: Matrix4;
}

Render_Queue :: struct {
    items: [..] Render_Item;
}

render_queue_create :: () -> Render_Queue {
    queue: Render_Queue;
    return queue;
}

render_queue_destroy :: (queue: *Render_Queue) {
    array_reset(*queue.items);
}

render_queue_clear :: (queue: *Render_Queue) {
    array_reset(*queue.items);
}

render_queue_submit :: (queue: *Render_Queue, mesh: Mesh, shader: Shader, texture: Texture, transform := Matrix4_Identity) {
    item: Render_Item;
    item.mesh = mesh;
    item.shader = shader;
    item.texture = texture;
    item.transform = transform;
    array_add(*queue.items, item);
}

render_queue_flush :: (queue: *Render_Queue, view: Matrix4, projection: Matrix4) {
    for item: queue.items {
        shader_use(item.shader);
        shader_set_texture(item.shader, "u_texture", item.texture);
        shader_set_mat4(item.shader, "projection", projection);
        shader_set_mat4(item.shader, "view", view);
        shader_set_mat4(item.shader, "model", item.transform);
        mesh_draw(item.mesh);
    }
}
