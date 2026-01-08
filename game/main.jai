#import "Basic";
#import "Math";
#import "engine";

#load "camera_controller.jai";

main :: () {
    if !engine_init() {
        log_error("Failed to init engine");
        return;
    }

    window := window_init(960, 600, "Voxerra");
    if !window {
        log_error("Failed to init window");
        engine_shutdown();
        return;
    }
    window_set_vsync(true);

    defer engine_shutdown();

    // load shader from files
    vertex_path := "assets/shaders/texture.vert";
    fragment_path := "assets/shaders/texture.frag";
    shader := asset_manager_load_shader(vertex_path, fragment_path, true);

    teapot_mesh := asset_manager_load_mesh(
        "assets/models/utah_teapot.obj",
        DEFAULT_MESH_LOAD_OPTIONS,
        true
    );
    suzanne_mesh := asset_manager_load_mesh(
        "assets/models/suzanne.obj",
        DEFAULT_MESH_LOAD_OPTIONS,
        true
    );

    quad_mesh := mesh_create_quad();

    texture := generate_worley_texture(512, 512);
    defer texture_destroy(texture);
    
    controller := camera_controller_create(.{0.0, 0.0, 5.0});

    queue := render_queue_create();
    defer render_queue_destroy(*queue);

    font := font_get_default();

    while !window_should_close(window) {
        delta_time := engine_update();
        camera_controller_update(*controller, window, delta_time);

        renderer_begin_frame(.{ 0.0, 0.0, 0.2, 1.0 });
        
        render_queue_clear(*queue);

        xform: Transform;
        xform.position = .{1.75, -0.75, 0};
        xform.rotation = quaternion_from_euler_xyz(
            .{0, cast(float32) time_get(), 0}
        );
        xform.scale = .{0.5, 0.5, 0.5};
        render_queue_submit(*queue, teapot_mesh, shader, null, xform);

        xform.position = .{-1.75, 0, 0};
        xform.rotation = quaternion_from_euler_xyz(
            .{0, cast(float32) time_get(), 0}
        );
        xform.scale = .{1, 1, 1};
        render_queue_submit(*queue, suzanne_mesh, shader, null, xform);

        xform.position = .{0, -2, 0};
        xform.rotation = quaternion_from_euler_xyz(
            .{degrees_to_radians(90), 0, 0}
        );
        xform.scale = .{5, 5, 5};
        render_queue_submit(*queue, quad_mesh, shader, texture, xform);

        view := camera_get_view_matrix(controller.camera);
        projection := camera_get_projection_matrix(
            controller.camera,
            cast(float32) window.width / window.height
        );
        render_queue_flush(*queue, view, projection);

        text: string;
        if controller.active {
            text = "[ESC] CC active: true";
        } else {
            text = "[ESC] CC active: false";
        }
        
        font_size := 24.0;
        text_draw(
            font,
            text,
            16,
            cast(float) (window.framebuffer_height - 16 - font_size),
            font_size,
            .{1.0, 1.0, 1.0, 1.0}
        );
        fps_counter_draw();

        renderer_end_frame();
        window_swap_buffers(window);
    }
}

generate_worley_texture :: (
    width: s32,
    height: s32,
    zoom: float = 32.0,
    seed: u64 = 157
) -> *Texture {
    pixel_count := width * height * 4;
    data := cast(*u8) alloc(pixel_count);
    
    for y: 0..height - 1 {
        for x: 0..width - 1 {
            spec := Worley_Noise_Spec.{
                seed = seed,
                zoom = zoom
            };
            d := worley_noise_2d(cast(float64) x, cast(float64) y, spec);
            
            d = clamp(d * 1.5, 0.0, 1.0);
            v := cast(u8)(d * 255.0);
            
            index := (y * width + x) * 4;
            data[index + 0] = v;
            data[index + 1] = v;
            data[index + 2] = v;
            data[index + 3] = 255;
        }
    }
    
    texture := texture_create_from_data(width, height, data);
    return texture;
}
