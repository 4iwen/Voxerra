#scope_file

#import "Basic";
#import "GL";

#scope_export

Fog_Resolve_State :: struct {
    enabled: bool;
    fog_enabled: bool;
    fog_color: Vector4 = .{0.72, 0.78, 0.86, 1.0};
    fog_near: float = 12.0;
    fog_far: float = 40.0;

    shader: *Shader;
    fullscreen_vao: u32;
}

fog_resolve_state: Fog_Resolve_State;

fog_resolve_init :: () {
    fog_resolve_state = .{};
    fog_resolve_state.shader = asset_manager_load_shader(
        "engine/assets/shaders/fog_resolve.vert",
        "engine/assets/shaders/fog_resolve.frag",
        true
    );
    glGenVertexArrays(1, *fog_resolve_state.fullscreen_vao);
}

fog_resolve_shutdown :: () {
    if fog_resolve_state.fullscreen_vao != 0 {
        glDeleteVertexArrays(1, *fog_resolve_state.fullscreen_vao);
    }
    fog_resolve_state = .{};
}

fog_resolve_apply :: (
    input_framebuffer: *Framebuffer,
    output_framebuffer: *Framebuffer,
    camera: *Camera,
    output_width: s32,
    output_height: s32
) {
    assert(input_framebuffer != null, "fog_resolve_apply: input_framebuffer is null");
    assert(camera != null, "fog_resolve_apply: camera is null");
    assert(fog_resolve_state.shader != null, "fog_resolve_apply: shader is null");

    if output_framebuffer {
        framebuffer_bind(output_framebuffer);
    } else {
        framebuffer_unbind();
        renderer_set_viewport_size(output_width, output_height);
    }

    renderer_set_blending(false);
    renderer_set_depth_test(false);
    renderer_set_depth_write(false);
    renderer_set_culling(false);

    shader_use(fog_resolve_state.shader);
    shader_set_int(fog_resolve_state.shader, "u_scene_color", 0);
    shader_set_int(fog_resolve_state.shader, "u_scene_depth", 1);
    shader_set_int(fog_resolve_state.shader, "u_fog_enabled", cast(s32) fog_resolve_state.fog_enabled);
    shader_set_vec4(fog_resolve_state.shader, "u_fog_color", fog_resolve_state.fog_color);
    shader_set_float(fog_resolve_state.shader, "u_fog_near", fog_resolve_state.fog_near);
    shader_set_float(fog_resolve_state.shader, "u_fog_far", fog_resolve_state.fog_far);
    shader_set_float(fog_resolve_state.shader, "u_camera_near", camera.near);
    shader_set_float(fog_resolve_state.shader, "u_camera_far", camera.far);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, input_framebuffer.color_texture);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, input_framebuffer.depth_texture);

    glBindVertexArray(fog_resolve_state.fullscreen_vao);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glBindVertexArray(0);

    glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE0);

    renderer_set_culling(true);
    renderer_set_depth_write(true);
    renderer_set_depth_test(true);
    renderer_set_blending(true);
}

fog_resolve_get_enabled :: () -> bool {
    return fog_resolve_state.enabled;
}

fog_resolve_get_state :: () -> *Fog_Resolve_State {
    return *fog_resolve_state;
}

fog_upload_shader_uniforms :: (shader: *Shader, enabled: bool) {
    assert(shader != null, "fog_upload_shader_uniforms: shader is null");

    shader_set_int(shader, "u_fog_enabled", cast(s32) (fog_resolve_state.fog_enabled && enabled));
    shader_set_vec4(shader, "u_fog_color", fog_resolve_state.fog_color);
    shader_set_float(shader, "u_fog_near", fog_resolve_state.fog_near);
    shader_set_float(shader, "u_fog_far", fog_resolve_state.fog_far);
}
