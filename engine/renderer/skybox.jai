#scope_export

Skybox :: struct {
    shader: *Shader;
    mesh: *Mesh;
    fallback_cubemap: *Cubemap;
}

skybox_init :: () -> *Skybox {
    skybox := New(Skybox);

    skybox_vertex := "engine/assets/shaders/skybox.vert";
    skybox_fragment := "engine/assets/shaders/skybox.frag";
    skybox.shader = asset_manager_load_shader(
        skybox_vertex,
        skybox_fragment,
        true
    );
    skybox.mesh = mesh_create_cube();
    skybox.fallback_cubemap = cubemap_create_solid_color(.{0.2, 0.4, 0.6, 1});

    return skybox;
}

skybox_shutdown :: (skybox: *Skybox) {
    assert(skybox != null, "skybox_shutdown: skybox is null");

    mesh_destroy(skybox.mesh);
    cubemap_destroy(skybox.fallback_cubemap);
    free(skybox);
}

skybox_draw :: (
    skybox: *Skybox,
    view: Matrix4,
    projection: Matrix4
) {
    assert(skybox != null, "skybox_draw: skybox is null");

    renderer_begin_far_depth_pass();
    shader_use(skybox.shader);

    // strip translation from view matrix so the skybox stays centered on the camera
    view_no_trans := view;
    view_no_trans._14 = 0;
    view_no_trans._24 = 0;
    view_no_trans._34 = 0;

    shader_set_mat4(skybox.shader, "u_projection", projection);
    shader_set_mat4(skybox.shader, "u_view", view_no_trans);

    shader_set_int(skybox.shader, "u_skybox", 0);

    cubemap_bind(skybox.fallback_cubemap, 0);

    renderer_set_culling(false);
    mesh_draw(skybox.mesh);
    renderer_set_culling(true);

    cubemap_unbind(0);

    renderer_end_far_depth_pass();
}
