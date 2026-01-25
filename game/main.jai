#import "Basic"()(MEMORY_DEBUGGER = false); // @ToDo: should be only imported in debug builds
#import "Math";
#import "engine";

#load "imgui_glfw_opengl3.jai";

#load "camera_controller.jai";
#load "skybox.jai";

main :: () {
    if !engine_init() {
        log_error("Failed to init engine");
        return;
    }
    defer engine_shutdown();

    window := window_init(1280, 800, "Voxerra");
    if !window {
        log_error("Failed to init window");
        engine_shutdown();  
        return;
    }
    window_set_vsync(true);

    // load shader from files
    vertex_path := "assets/shaders/pbr.vert";
    fragment_path := "assets/shaders/pbr.frag";
    shader := asset_manager_load_shader(vertex_path, fragment_path, true);

    skybox := skybox_init();
    defer skybox_shutdown(skybox);

    lights := light_system_create(.{0.1, 0.1, 0.1});
    defer light_system_destroy(*lights);

    // sun
    sun_direction := Vector3.{-0.2, -1.0, -0.3}; 
    sun_color := Vector3.{1.0, 0.95, 0.9};
    sun_intensity := 2.0;
    light_add_directional(*lights, sun_direction, sun_color, sun_intensity);
    // point light
    // light_add_point(*lights, .{3, 3, 0}, .{1, 1, 1});

    model := asset_manager_load_model(
        "assets/models/glTF-Sample-Assets/Models/Sponza/glTF/Sponza.gltf"
    );
    
    controller := camera_controller_create(.{0.0, 1.5, 0.0});

    queue := render_queue_create();
    defer render_queue_destroy(*queue);

    font := font_get_default();

    imgui_context := ImGui.CreateContext();
    defer ImGui.DestroyContext(imgui_context);
    
    io := ImGui.GetIO();
    io.ConfigFlags_ |= .NavEnableKeyboard;
    io.ConfigFlags_ |= .DockingEnable;
    io.ConfigFlags_ |= .ViewportsEnable;
    ImGui.StyleColorsDark();

    style := ImGui.GetStyle();
    if (io.ConfigFlags_ & .ViewportsEnable)
    {
        style.WindowRounding = 0.0;
        style.Colors[ImGui.Col.WindowBg].w = 1.0;
    }

    ImGui_ImplGlfw_InitForOpenGL(window.handle, true);
    defer ImGui_ImplGlfw_Shutdown();
    ImGui_ImplOpenGL3_Init("#version 330");
    defer ImGui_ImplOpenGL3_Shutdown();

    while !window_should_close(window) {
        // memory_visualizer_per_frame_update(); // @ToDo: should only be called in debug builds

        delta_time := engine_update();
        camera_controller_update(*controller, window, delta_time);

        renderer_begin_frame(.{0.0, 0.0, 0.0, 1.0});
        
        render_queue_clear(*queue);

        xf: Transform;
        xf.position = .{0.5, 0, 0};
        xf.rotation = quaternion_from_euler_xyz(.{0, PI / 2, 0});
        render_queue_submit(*queue, model, shader, xf);

        view := camera_get_view_matrix(controller.camera);
        projection := camera_get_projection_matrix(
            controller.camera,
            cast(float32) window.width / window.height
        );
        render_queue_flush(
            *queue,
            view,
            projection,
            controller.camera.position,
            *lights
        );

        skybox_draw(
            skybox,
            view,
            projection,
            sun_direction,
            sun_color
        );

        text: string;
        if controller.active {
            text = "[ESC]: CC active: true";
        } else {
            text = "[RMB]: CC active: false";
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
        pos := controller.camera.position;
        text = tprint("[POS]: %, %, %", pos.x, pos.y, pos.z);
        text_draw(
            font,
            text,
            16,
            cast(float) (window.framebuffer_height - 64 - font_size),
            font_size,
            .{1.0, 1.0, 1.0, 1.0}
        );
        fps_counter_draw();

        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui.NewFrame();
        ImGui.ShowDemoWindow();
        ImGui.Render();
        ImGui_ImplOpenGL3_RenderDrawData(ImGui.GetDrawData());

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
