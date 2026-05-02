#scope_file

#import "Basic";
#import "GL";
#import "glfw";
#import "jai-imgui";
#load "../../modules/jai-imgui/backends/glfw_opengl3.jai";
#load "../assets/fonts/fontawesome/IconsFontAwesome7.jai";

#scope_module

UI_ICON_FONT_PATH :: "engine/assets/fonts/fontawesome/fa-solid-900.ttf";
UI_ICON_RANGES: [3] ImWchar : .[
    cast(ImWchar) ICON_MIN_FA,
    cast(ImWchar) ICON_MAX_FA,
    0,
];

UI_Icon_Label :: (icon: string, label: string) -> *u8 #expand {
	return temp_c_string(tprint("% %", icon, label));
}

UI_Icon_Window_Title :: (icon: string, label: string, id: string) -> *u8 #expand {
    return temp_c_string(tprint("% %###%", icon, label, id));
}

UI_State :: struct {
    imgui_context: *ImGuiContext;
    draw_demo: bool;
    rotation_state: Rotation_Edit_State;
    viewport_hovered: bool;
    viewport_image_visible: bool;
    viewport_screen_min: ImVec2;
    viewport_screen_max: ImVec2;
    viewport_size: ImVec2;
    viewport_pixel_width: s32;
    viewport_pixel_height: s32;
}

#scope_export

ui_state: UI_State;

#scope_module

COLLAPSING_HEADER_FLAGS: TreeNodeFlags : .DefaultOpen | .Framed | .SpanAvailWidth;
TABLE_FLAGS: TableFlags : .BordersInnerV | .SizingStretchProp | .NoBordersInBody;

ui_init :: (window: *Window) {
	ui_state.imgui_context = CreateContext();
    
    io := GetIO();
    io.ConfigFlags_ |= .NavEnableKeyboard;
    io.ConfigFlags_ |= .DockingEnable;
    // io.ConfigFlags_ |= .ViewportsEnable;

    ui_set_theme();

    style := GetStyle();
    if io.ConfigFlags_ & .ViewportsEnable {
        style.WindowRounding = 0.0;
        style.Colors[Col.WindowBg].w = 1.0;
    }

    io.ConfigDpiScaleFonts = true;

	base_font_size := 13.0;
	icon_font_size := 11.0;

	// main font config
	base_config: ImFontConfig;
	ImFontConfig.Constructor(*base_config);
	base_config.SizePixels = base_font_size;

	// main UI font
	ImFontAtlas.AddFontDefaultVector(io.Fonts, *base_config);

	// merge FontAwesome into previous font
	icons_config: ImFontConfig;
	ImFontConfig.Constructor(*icons_config);
	icons_config.MergeMode = true;
	icons_config.PixelSnapH = true;
	icons_config.GlyphMinAdvanceX = icon_font_size;
	icons_config.GlyphMaxAdvanceX = icon_font_size;
	icons_config.RasterizerDensity = 1.0;

	icon_font := ImFontAtlas.AddFontFromFileTTF(
        io.Fonts,
        UI_ICON_FONT_PATH,
        icon_font_size,
        *icons_config,
        UI_ICON_RANGES.data
    );
    if !icon_font {
        log_warning("Failed to load editor icon font: %", UI_ICON_FONT_PATH);
    }

    ImplGlfw_InitForOpenGL(window.handle, true);
    ImplOpenGL3_Init("#version 330");

    properties_init();
    asset_browser_init();
}

ui_shutdown :: () {
    asset_browser_shutdown();
    properties_shutdown();
	
    ImplOpenGL3_Shutdown();
    ImplGlfw_Shutdown();
	DestroyContext(ui_state.imgui_context);
}

ui_begin_frame :: () {
    io := GetIO();
    if input_state.cursor_disabled {
        io.ConfigFlags_ |= .NoMouse;
    } else {
        io.ConfigFlags_ &= ~.NoMouse;
    }

    ImplOpenGL3_NewFrame();
    ImplGlfw_NewFrame();
    NewFrame();
    
	// default dockspace
	DockSpaceOverViewport(
		0,
		GetMainViewport(),
		DockNodeFlags.PassthruCentralNode
	);

	if ui_state.draw_demo {
		ShowDemoWindow(*ui_state.draw_demo);
	}
}

ui_draw :: () {
	#insert #run generate_ui_window_procedure_calls();
}

ui_end_frame :: () {
    io := GetIO();
    input_set_capture_policy(
        io.WantCaptureMouse,
        io.WantCaptureKeyboard,
        io.WantTextInput,
        IsAnyItemActive(),
        IsPopupOpen(null, .AnyPopup),
        ui_state.viewport_hovered
    );

    Render();

    framebuffer_unbind();
    renderer_set_viewport_size(
        engine_state.window.framebuffer_width,
        engine_state.window.framebuffer_height
    );
    renderer_clear(.{0.08, 0.08, 0.09, 1.0});
    
    if io.ConfigFlags_ & .ViewportsEnable {
        backup_current_context := glfwGetCurrentContext();
        UpdatePlatformWindows();
        RenderPlatformWindowsDefault();
        glfwMakeContextCurrent(backup_current_context);
    }
    
    ImplOpenGL3_RenderDrawData(GetDrawData());
}

#scope_file

ui_set_theme :: () {
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
	style.GrabRounding = 2.0;
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
	style.Colors[Col.ImGuiCol_HeaderHovered] = .{0.9764706, 0.9764706, 0.9764706, 0.56862745};
	style.Colors[Col.ImGuiCol_HeaderActive] = .{0.9764706, 0.9764706, 0.9764706, 0.82745098};
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
	style.Colors[Col.ImGuiCol_PlotLines] = .{0.8980392, 0.69803923, 0.0, 1.0};
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

#scope_export

#placeholder ui_window_procedures; // gets filled in at compile-time

generate_ui_window_procedure_calls :: () -> string {
	builder: String_Builder;

	for ui_window_procedures {
		print_to_builder(*builder, "%();\n", it);
	}

	return builder_to_string(*builder);
}
