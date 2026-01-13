#scope_file

#import "Basic";
#import "Math";
#import "Sort";
#import "GL";

#scope_export

Render_Item :: struct {
    model: *Model;
    mesh: *Mesh;
    shader: *Shader;
    texture: *Texture;
    transform: Transform;
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

render_queue_submit :: (
    queue: *Render_Queue,
    model: *Model,
    shader: *Shader,
    transform := Transform.{}
) {
    item: Render_Item;
    item.model = model;
    item.shader = shader;
    item.transform = transform;
    array_add(*queue.items, item);
}

render_queue_submit :: (
    queue: *Render_Queue,
    mesh: *Mesh,
    shader: *Shader,
    texture: *Texture = null,
    transform := Transform.{}
) {
    item: Render_Item;
    item.mesh = mesh;
    item.shader = shader;
    item.texture = texture;
    item.transform = transform;
    array_add(*queue.items, item);
}

render_queue_flush :: (
    queue: *Render_Queue,
    view: Matrix4,
    projection: Matrix4,
    camera_pos: Vector3,
    lights: *Light_System = null
) {
    // temporary storage for sorting
    opaque_cmds: [..] Draw_Command;
    transparent_cmds: [..] Draw_Command;
    opaque_cmds.allocator = temp;
    transparent_cmds.allocator = temp;

    for item: queue.items {
        process_render_item(item, camera_pos, *opaque_cmds, *transparent_cmds);
    }

    // pass 1: opaque objects 
    glDisable(GL_BLEND);
    glDepthMask(GL_TRUE);
    
    for cmd: opaque_cmds {
        draw_command_execute(cmd, view, projection, camera_pos, lights);
    }

    // pass 2: transparent objects
    // sort back to front
    quick_sort(transparent_cmds, (a, b) => b.dist_sq - a.dist_sq);

    glEnable(GL_BLEND);
    glDepthMask(GL_FALSE);
    
    for cmd: transparent_cmds {
        draw_command_execute(cmd, view, projection, camera_pos, lights);
    }
    
    glDepthMask(GL_TRUE);
}

#scope_file

Draw_Command :: struct {
    mesh: *Mesh;
    shader: *Shader;
    transform: Matrix4;
    
    // material props
    albedo_texture: *Texture;
    normal_texture: *Texture;
    metallic_roughness_texture: *Texture;
    occlusion_texture: *Texture;
    emissive_texture: *Texture;

    color: Vector4;
    metallic: float;
    roughness: float;
    alpha_cutoff: float;
    
    // sorting
    dist_sq: float;
}

process_render_item :: (
    item: Render_Item, 
    camera_pos: Vector3, 
    opaque_cmds: *[..] Draw_Command, 
    transparent_cmds: *[..] Draw_Command
) {
    model_matrix := transform_to_matrix(item.transform);
    dist_sq := length_squared(item.transform.position - camera_pos);

    if item.model {
        for sm: item.model.submeshes {
            cmd: Draw_Command;
            cmd.mesh = sm.mesh;
            cmd.shader = item.shader;
            cmd.transform = model_matrix;
            cmd.dist_sq = dist_sq;

            is_transparent := false;

            if sm.material {
                cmd.albedo_texture = sm.material.albedo_texture;
                cmd.normal_texture = sm.material.normal_texture;
                cmd.metallic_roughness_texture = sm.material.metallic_roughness_texture;
                cmd.occlusion_texture = sm.material.occlusion_texture;
                cmd.emissive_texture = sm.material.emissive_texture;
                
                cmd.color = sm.material.color;
                cmd.metallic = sm.material.metallic;
                cmd.roughness = sm.material.roughness;
                cmd.alpha_cutoff = sm.material.alpha_cutoff;
                is_transparent = sm.material.is_transparent;
            } else {
                populate_default_material_props(*cmd);
            }

            if cmd.color.w < 1.0 is_transparent = true;

            if is_transparent {
                array_add(transparent_cmds, cmd);
            } else {
                array_add(opaque_cmds, cmd);
            }
        }
    } else {
        cmd: Draw_Command;
        cmd.mesh = item.mesh;
        cmd.shader = item.shader;
        cmd.transform = model_matrix;
        cmd.dist_sq = dist_sq;
        cmd.albedo_texture = item.texture;
        
        populate_default_material_props(*cmd);
        
        // single mesh items are currently always treated as opaque unless we add logic here
        array_add(opaque_cmds, cmd);
    }
}

populate_default_material_props :: (cmd: *Draw_Command) {
    cmd.color = .{1,1,1,1};
    cmd.metallic = 0.0;
    cmd.roughness = 0.5;
    cmd.alpha_cutoff = 0.01;
}

draw_command_execute :: (cmd: Draw_Command, view: Matrix4, projection: Matrix4, camera_pos: Vector3, lights: *Light_System) {
    shader_use(cmd.shader);
    shader_set_mat4(cmd.shader, "u_projection", projection);
    shader_set_mat4(cmd.shader, "u_view", view);
    shader_set_vec3(cmd.shader, "u_camera_position", camera_pos);
    shader_set_mat4(cmd.shader, "u_model", cmd.transform);

    // calculate normal matrix
    success, inv := inverse(cmd.transform);
    if !success {
        inv = Matrix4_Identity;
    }
    nm_4 := transpose(inv);
    
    // extract 3x3
    nm: Matrix3;
    nm._11 = nm_4._11; nm._12 = nm_4._12; nm._13 = nm_4._13;
    nm._21 = nm_4._21; nm._22 = nm_4._22; nm._23 = nm_4._23;
    nm._31 = nm_4._31; nm._32 = nm_4._32; nm._33 = nm_4._33;
    
    shader_set_mat3(cmd.shader, "u_normal_matrix", nm);

    if lights {
        light_upload_to_shader(cmd.shader, lights);
    }

    albedo := Vector3.{cmd.color.x, cmd.color.y, cmd.color.z};
    
    shader_set_vec3(cmd.shader, "u_albedo", albedo);
    shader_set_float(cmd.shader, "u_metallic", cmd.metallic);
    shader_set_float(cmd.shader, "u_roughness", cmd.roughness);
    shader_set_float(cmd.shader, "u_ambient_occlusion", 1.0); 
    
    // Bind textures
    shader_set_texture(cmd.shader, "u_albedo_map", cmd.albedo_texture, 0);
    shader_set_texture(cmd.shader, "u_normal_map", cmd.normal_texture, 1);
    shader_set_texture(cmd.shader, "u_metallic_roughness_map", cmd.metallic_roughness_texture, 2);
    shader_set_texture(cmd.shader, "u_occlusion_map", cmd.occlusion_texture, 3);
    shader_set_texture(cmd.shader, "u_emissive_map", cmd.emissive_texture, 4);

    shader_set_int(cmd.shader, "u_has_albedo_map", cast(s32) ifx cmd.albedo_texture then 1 else 0);
    shader_set_int(cmd.shader, "u_has_normal_map", cast(s32) ifx cmd.normal_texture then 1 else 0);
    shader_set_int(cmd.shader, "u_has_metallic_roughness_map", cast(s32) ifx cmd.metallic_roughness_texture then 1 else 0);
    shader_set_int(cmd.shader, "u_has_occlusion_map", cast(s32) ifx cmd.occlusion_texture then 1 else 0);
    shader_set_int(cmd.shader, "u_has_emissive_map", cast(s32) ifx cmd.emissive_texture then 1 else 0);
    
    mesh_draw(cmd.mesh);
}
