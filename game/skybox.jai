#scope_file

#import "Basic";
#import "engine";

#scope_export

Skybox :: struct {
    shader: *Shader;
    mesh: *Mesh;
}

skybox_init :: () -> *Skybox {
    skybox := New(Skybox);

    skybox.shader = asset_manager_load_shader(
        "assets/shaders/skybox.vert",
        "assets/shaders/skybox.frag",
        true
    );
    skybox.mesh = mesh_create_cube();

    return skybox;
}

skybox_shutdown :: (skybox: *Skybox) {
    free(skybox.mesh);
    free(skybox);
}

skybox_draw :: (
    skybox: *Skybox,
    view: Matrix4,
    projection: Matrix4,
    sun_direction: Vector3,
    sun_color: Vector3
) {
    renderer_begin_far_depth_pass();
    shader_use(skybox.shader);
    
    // remove translation from view matrix
    view_no_trans := view;
    view_no_trans._14 = 0;
    view_no_trans._24 = 0;
    view_no_trans._34 = 0;

    shader_set_mat4(skybox.shader, "u_projection", projection);
    shader_set_mat4(skybox.shader, "u_view", view_no_trans);
    
    shader_set_vec3(skybox.shader, "u_sun_direction", -sun_direction);
    shader_set_vec3(skybox.shader, "u_sun_color", sun_color);

    renderer_set_culling(false);
    mesh_draw(skybox.mesh);
    renderer_set_culling(true);
    
    renderer_end_far_depth_pass();
}
