#import "Basic"()(MEMORY_DEBUGGER = false); // @ToDo: should be only imported in debug builds
#import "Math";
#import "engine";

// @ToDo: move elsewhere, temporary
#import "glfw";
#import "jai-imgui";
#load "../modules/jai-imgui/backends/glfw_opengl3.jai";

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

    imgui_context := CreateContext();
    
    io := GetIO();
    io.ConfigFlags_ |= .NavEnableKeyboard;
    io.ConfigFlags_ |= .DockingEnable;
    io.ConfigFlags_ |= .ViewportsEnable;
    set_imgui_theme();

    style := GetStyle();
    if io.ConfigFlags_ & .ViewportsEnable {
        style.WindowRounding = 0.0;
        style.Colors[Col.WindowBg].w = 1.0;
    }

    ImplGlfw_InitForOpenGL(window.handle, true);
    ImplOpenGL3_Init("#version 330");

    frame: u64 = 0;
    FRAME_TIME_PLOT_COUNT :: 120;
    frame_time_values: [FRAME_TIME_PLOT_COUNT] float;

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

        ImplOpenGL3_NewFrame();
        ImplGlfw_NewFrame();
        NewFrame();
        ShowDemoWindow();
        {
            Begin("Metrics");
            
            fps_text := tprint("FPS: %", formatFloat(
                io.Framerate,
                trailing_width = 1,
                zero_removal = .NO
            ));
            Text(fps_text);

            last_frame_time := 1000 / io.Framerate;
            frame_time_text := tprint("Frame time: %ms", formatFloat(
                last_frame_time,
                trailing_width = 3,
                zero_removal = .NO
            ));
            Text(frame_time_text);

            frame_time_values[frame % FRAME_TIME_PLOT_COUNT] = last_frame_time;
            frame_time_avg := 0.0;
            for frame_time_values {
                frame_time_avg += it;
            }
            frame_time_avg /= frame_time_values.count;
            plot_overlay := tprint("Frame time avg: %", formatFloat(
                frame_time_avg,
                trailing_width = 3,
                zero_removal = .NO
            ));
            plot_width := GetContentRegionAvail().x;
            plot_scale_min := 0.0;
            plot_scale_max := 250.0;
            PlotHistogram(
                "##Frame time plot",
                frame_time_values.data,
                cast(s32) frame_time_values.count,
                cast(s32) frame, // set this offset later
                temp_c_string(plot_overlay),
                scale_min = plot_scale_min,
                scale_max = plot_scale_max,
                graph_size = ImVec2.{plot_width, 120}
            );

            End();
        }
        Render();
        if io.ConfigFlags_ & .ViewportsEnable {
            backup_current_context := glfwGetCurrentContext();
            UpdatePlatformWindows();
            RenderPlatformWindowsDefault();
            glfwMakeContextCurrent(backup_current_context);
        }
        ImplOpenGL3_RenderDrawData(GetDrawData());

        renderer_end_frame();
        window_swap_buffers(window);

        frame += 1;
    }

    ImplOpenGL3_Shutdown();
    ImplGlfw_Shutdown();
    DestroyContext(imgui_context);
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

set_imgui_theme :: () {
    style := GetStyle();
	
	style.Alpha = 1.0;
	style.DisabledAlpha = 0.6;
	style.WindowPadding = .{8.0, 8.0};
	style.WindowRounding = 4.0;
	style.WindowBorderSize = 1.0;
	style.WindowMinSize = .{32.0, 32.0};
	style.WindowTitleAlign = .{0.0, 0.5};
	style.WindowMenuButtonPosition = Dir.None;
	style.ChildRounding = 4.0;
	style.ChildBorderSize = 1.0;
	style.PopupRounding = 4.0;
	style.PopupBorderSize = 1.0;
	style.FramePadding = .{4.0, 3.0};
	style.FrameRounding = 4.0;
	style.FrameBorderSize = 1.0;
	style.ItemSpacing = .{8.0, 4.0};
	style.ItemInnerSpacing = .{4.0, 4.0};
	style.CellPadding = .{4.0, 2.0};
	style.IndentSpacing = 21.0;
	style.ColumnsMinSpacing = 6.0;
	style.ScrollbarSize = 14.0;
	style.ScrollbarRounding = 4.0;
	style.GrabMinSize = 10.0;
	style.GrabRounding = 20.0;
	style.TabRounding = 4.0;
	style.TabBorderSize = 1.0;
	style.TabCloseButtonMinWidthSelected = 0.0;
	style.TabCloseButtonMinWidthUnselected = 0.0;
	style.ColorButtonPosition = Dir.Right;
	style.ButtonTextAlign = .{0.5, 0.5};
	style.SelectableTextAlign = .{0.0, 0.0};
	
	style.Colors[Col.ImGuiCol_Text] = .{1.0, 1.0, 1.0, 1.0};
	style.Colors[Col.ImGuiCol_TextDisabled] = .{0.49803922, 0.49803922, 0.49803922, 1.0};
	style.Colors[Col.ImGuiCol_WindowBg] = .{0.11372549, 0.11372549, 0.11372549, 1.0};
	style.Colors[Col.ImGuiCol_ChildBg] = .{0.0, 0.0, 0.0, 0.0};
	style.Colors[Col.ImGuiCol_PopupBg] = .{0.078431375, 0.078431375, 0.078431375, 0.94};
	style.Colors[Col.ImGuiCol_Border] = .{1.0, 1.0, 1.0, 0.16309011};
	style.Colors[Col.ImGuiCol_BorderShadow] = .{0.0, 0.0, 0.0, 0.0};
	style.Colors[Col.ImGuiCol_FrameBg] = .{0.08627451, 0.08627451, 0.08627451, 1.0};
	style.Colors[Col.ImGuiCol_FrameBgHovered] = .{0.15294118, 0.15294118, 0.15294118, 1.0};
	style.Colors[Col.ImGuiCol_FrameBgActive] = .{0.1882353, 0.1882353, 0.1882353, 1.0};
	style.Colors[Col.ImGuiCol_TitleBg] = .{0.11372549, 0.11372549, 0.11372549, 1.0};
	style.Colors[Col.ImGuiCol_TitleBgActive] = .{0.10588235, 0.10588235, 0.10588235, 1.0};
	style.Colors[Col.ImGuiCol_TitleBgCollapsed] = .{0.0, 0.0, 0.0, 0.51};
	style.Colors[Col.ImGuiCol_MenuBarBg] = .{0.11372549, 0.11372549, 0.11372549, 1.0};
	style.Colors[Col.ImGuiCol_ScrollbarBg] = .{0.019607844, 0.019607844, 0.019607844, 0.53};
	style.Colors[Col.ImGuiCol_ScrollbarGrab] = .{0.30980393, 0.30980393, 0.30980393, 1.0};
	style.Colors[Col.ImGuiCol_ScrollbarGrabHovered] = .{0.40784314, 0.40784314, 0.40784314, 1.0};
	style.Colors[Col.ImGuiCol_ScrollbarGrabActive] = .{0.50980395, 0.50980395, 0.50980395, 1.0};
	style.Colors[Col.ImGuiCol_Button] = .{0.14901961, 0.14901961, 0.14901961, 1.0};
	style.Colors[Col.ImGuiCol_ButtonHovered] = .{0.24705882, 0.24705882, 0.24705882, 1.0};
	style.Colors[Col.ImGuiCol_ButtonActive] = .{0.32941177, 0.32941177, 0.32941177, 1.0};
	style.Colors[Col.ImGuiCol_Header] = .{0.9764706, 0.9764706, 0.9764706, 0.30980393};
	style.Colors[Col.ImGuiCol_HeaderHovered] = .{0.9764706, 0.9764706, 0.9764706, 0.8};
	style.Colors[Col.ImGuiCol_HeaderActive] = .{0.9764706, 0.9764706, 0.9764706, 1.0};
	style.Colors[Col.ImGuiCol_Separator] = .{0.42745098, 0.42745098, 0.49803922, 0.5};
	style.Colors[Col.ImGuiCol_SeparatorHovered] = .{0.7490196, 0.7490196, 0.7490196, 0.78039217};
	style.Colors[Col.ImGuiCol_SeparatorActive] = .{0.7490196, 0.7490196, 0.7490196, 1.0};
	style.Colors[Col.ImGuiCol_ResizeGrip] = .{0.9764706, 0.9764706, 0.9764706, 0.2};
	style.Colors[Col.ImGuiCol_ResizeGripHovered] = .{0.9372549, 0.9372549, 0.9372549, 0.67058825};
	style.Colors[Col.ImGuiCol_ResizeGripActive] = .{0.9764706, 0.9764706, 0.9764706, 0.9490196};
	style.Colors[Col.ImGuiCol_Tab] = .{0.22352941, 0.22352941, 0.22352941, 0.8627451};
	style.Colors[Col.ImGuiCol_TabHovered] = .{0.32156864, 0.32156864, 0.32156864, 0.8};
	style.Colors[Col.ImGuiCol_TabActive] = .{0.27450982, 0.27450982, 0.27450982, 1.0};
	style.Colors[Col.ImGuiCol_TabUnfocused] = .{0.14509805, 0.14509805, 0.14509805, 0.972549};
	style.Colors[Col.ImGuiCol_TabUnfocusedActive] = .{0.42352942, 0.42352942, 0.42352942, 1.0};
	style.Colors[Col.ImGuiCol_PlotLines] = .{0.60784316, 0.60784316, 0.60784316, 1.0};
	style.Colors[Col.ImGuiCol_PlotHistogram] = .{0.8980392, 0.69803923, 0.0, 1.0};
	style.Colors[Col.ImGuiCol_PlotHistogramHovered] = .{1.0, 0.6, 0.0, 1.0};
	style.Colors[Col.ImGuiCol_TableHeaderBg] = .{0.1882353, 0.1882353, 0.2, 1.0};
	style.Colors[Col.ImGuiCol_TableBorderStrong] = .{0.30980393, 0.30980393, 0.34901962, 1.0};
	style.Colors[Col.ImGuiCol_TableBorderLight] = .{0.22745098, 0.22745098, 0.24705882, 1.0};
	style.Colors[Col.ImGuiCol_TableRowBg] = .{0.0, 0.0, 0.0, 0.0};
	style.Colors[Col.ImGuiCol_TableRowBgAlt] = .{1.0, 1.0, 1.0, 0.06};
	style.Colors[Col.ImGuiCol_DragDropTarget] = .{1.0, 1.0, 0.0, 0.9};
	style.Colors[Col.ImGuiCol_NavHighlight] = .{0.25882354, 0.5882353, 0.9764706, 1.0};
	style.Colors[Col.ImGuiCol_NavWindowingHighlight] = .{1.0, 1.0, 1.0, 0.7};
	style.Colors[Col.ImGuiCol_NavWindowingDimBg] = .{0.8, 0.8, 0.8, 0.2};
	style.Colors[Col.ImGuiCol_ModalWindowDimBg] = .{0.8, 0.8, 0.8, 0.35};
    style.Colors[Col.ImGuiCol_CheckMark] = .{0.90, 0.70, 0.00, 1.00};
    style.Colors[Col.ImGuiCol_SliderGrab] = .{0.90, 0.70, 0.00, 1.00};
    style.Colors[Col.ImGuiCol_SliderGrabActive] = .{1.00, 0.60, 0.00, 1.00};
    style.Colors[Col.ImGuiCol_TabSelectedOverline] = .{0.90, 0.70, 0.00, 1.00};
    style.Colors[Col.ImGuiCol_DockingPreview] = .{0.90, 0.70, 0.00, 0.70};
    style.Colors[Col.ImGuiCol_PlotLinesHovered] = .{1.00, 0.60, 0.00, 1.00};
    style.Colors[Col.ImGuiCol_TextLink] = .{0.90, 0.70, 0.00, 1.00};
    style.Colors[Col.ImGuiCol_TextSelectedBg] = .{0.90, 0.70, 0.00, 0.35};
    style.Colors[Col.ImGuiCol_NavCursor] = .{0.90, 0.70, 0.00, 1.00};
}
