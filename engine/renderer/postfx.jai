#scope_file

#import "Basic";
#import "GL";

#scope_export

PostFX_State :: struct {
    enabled: bool;
    fog_enabled: bool;
    fog_color: Vector4 = .{0.72, 0.78, 0.86, 1.0};
    fog_near: float = 12.0;
    fog_far: float = 40.0;

    shader: *Shader;
    fullscreen_vao: u32;
}

postfx_state: PostFX_State;

postfx_init :: () {
    postfx_state = .{};
    postfx_state.shader = asset_manager_load_shader(
        "engine/assets/shaders/postfx.vert",
        "engine/assets/shaders/postfx.frag",
        true
    );
    glGenVertexArrays(1, *postfx_state.fullscreen_vao);
}

postfx_shutdown :: () {
    if postfx_state.fullscreen_vao != 0 {
        glDeleteVertexArrays(1, *postfx_state.fullscreen_vao);
    }
    postfx_state = .{};
}

postfx_resize :: (width: s32, height: s32) {
    _ = width;
    _ = height;
}

postfx_apply :: (
    input_framebuffer: *Framebuffer,
    output_framebuffer: *Framebuffer,
    camera: *Camera,
    output_width: s32,
    output_height: s32
) {
    assert(input_framebuffer != null, "postfx_apply: input_framebuffer is null");
    assert(camera != null, "postfx_apply: camera is null");
    assert(postfx_state.shader != null, "postfx_apply: shader is null");

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

    shader_use(postfx_state.shader);
    shader_set_int(postfx_state.shader, "u_scene_color", 0);
    shader_set_int(postfx_state.shader, "u_scene_depth", 1);
    shader_set_int(postfx_state.shader, "u_postfx_enabled", cast(s32) postfx_state.enabled);
    shader_set_int(postfx_state.shader, "u_fog_enabled", cast(s32) postfx_state.fog_enabled);
    shader_set_vec4(postfx_state.shader, "u_fog_color", postfx_state.fog_color);
    shader_set_float(postfx_state.shader, "u_fog_near", postfx_state.fog_near);
    shader_set_float(postfx_state.shader, "u_fog_far", postfx_state.fog_far);
    shader_set_float(postfx_state.shader, "u_camera_near", camera.near);
    shader_set_float(postfx_state.shader, "u_camera_far", camera.far);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, input_framebuffer.color_texture);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, input_framebuffer.depth_texture);

    glBindVertexArray(postfx_state.fullscreen_vao);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glBindVertexArray(0);

    glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE0);

    renderer_set_culling(true);
    renderer_set_depth_write(true);
    renderer_set_depth_test(true);
    renderer_set_blending(true);
}

postfx_set_enabled :: (enabled: bool) {
    postfx_state.enabled = enabled;
}

postfx_get_enabled :: () -> bool {
    return postfx_state.enabled;
}

postfx_get_state :: () -> *PostFX_State {
    return *postfx_state;
}

postfx_apply_fog_uniforms :: (shader: *Shader) {
    assert(shader != null, "postfx_apply_fog_uniforms: shader is null");

    shader_set_int(shader, "u_fog_enabled", cast(s32) postfx_state.fog_enabled);
    shader_set_vec4(shader, "u_fog_color", postfx_state.fog_color);
    shader_set_float(shader, "u_fog_near", postfx_state.fog_near);
    shader_set_float(shader, "u_fog_far", postfx_state.fog_far);
}
