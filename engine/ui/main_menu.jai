#scope_file

#import "Basic";
#import "jai-imgui";

#scope_export

main_menu_draw :: () {
    main_menu_handle_shortcuts();

    if BeginMainMenuBar() {
        if BeginMenu("File") {
            if MenuItem(UI_Icon_Label(ICON_FA_FILE_CIRCLE_PLUS, "New Scene"), "Ctrl+N", enabled = false) {
            }
            if MenuItem(UI_Icon_Label(ICON_FA_FOLDER_OPEN, "Open Scene..."), "Ctrl+O", enabled = !editor_is_playing()) {
                main_menu_request_open_scene_modal();
            }
            can_save_scene := cast(bool) engine_state.current_scene && !editor_is_playing();
            if MenuItem(UI_Icon_Label(ICON_FA_FLOPPY_DISK, "Save Scene"), "Ctrl/Cmd+S", enabled = can_save_scene) {
                editor_save_active_scene();
            }
            can_close_scene := editor_context.active_tab_index >= 0 && !editor_is_playing();
            if MenuItem(UI_Icon_Label(ICON_FA_XMARK, "Close Scene"), "", enabled = can_close_scene) {
                editor_request_close_scene_tab(editor_context.active_tab_index);
            }
            Separator();
            if MenuItem(UI_Icon_Label(ICON_FA_RIGHT_FROM_BRACKET, "Exit"), "Alt+F4") {
                window_set_should_close(engine_state.window, true);
            }
            EndMenu();
        }

        if BeginMenu("Run") {
            if MenuItem(UI_Icon_Label(ICON_FA_PLAY, "Play"), "F5", enabled = cast(bool) engine_state.current_scene && !editor_is_playing()) {
                editor_play();
            }
            if MenuItem(UI_Icon_Label(ICON_FA_STOP, "Stop"), "Shift+F5", enabled = editor_is_playing()) {
                editor_stop();
            }
            EndMenu();
        }
        
        if BeginMenu("Edit") {
            scene := editor_get_active_scene();
            node_parent := selected_node;
            if !editor_node_can_add_child(node_parent) && scene {
                node_parent = scene.root;
            }

            can_add_node := editor_node_can_add_child(node_parent);
            if MenuItem(UI_Icon_Label(ICON_FA_CIRCLE_PLUS, "Add Node"), "", enabled = can_add_node) {
                editor_add_child_node(node_parent);
            }
            if MenuItem(UI_Icon_Label(ICON_FA_CUBES, "Add Component..."), "", enabled = editor_node_can_edit_components(selected_node)) {
                properties_request_add_component_modal();
            }
            if MenuItem(UI_Icon_Label(ICON_FA_TRASH, "Delete Node"), "Del", enabled = editor_node_can_delete(selected_node)) {
                editor_delete_node(selected_node);
            }
            EndMenu();
        }

        if BeginMenu("View") {
            MenuItem(UI_Icon_Label(ICON_FA_WINDOW_MAXIMIZE, "ImGui Demo"), "", *ui_state.draw_demo);

            if BeginMenu(UI_Icon_Label(ICON_FA_EYE, "Render Mode"), enabled = !editor_is_playing()) {
                main_menu_draw_render_mode_items();
                EndMenu();
            }

            if engine_state.window {
                vsync_enabled := window_get_vsync(engine_state.window);
                if MenuItem(UI_Icon_Label(ICON_FA_ARROWS_ROTATE, "VSync"), "", selected = vsync_enabled) {
                    window_set_vsync(engine_state.window, !vsync_enabled);
                }
            }
            EndMenu();
        }

        EndMainMenuBar();
    }

    main_menu_draw_open_scene_modal();
} @UI_Window

#scope_file

main_menu_open_scene_requested: bool;
main_menu_open_scene_buffer: [512] u8;

main_menu_handle_shortcuts :: () {
    if input_editor_shortcuts_blocked() then return;

    if input_primary_modifier_down() && input_key_pressed(.O) && !editor_is_playing() {
        main_menu_request_open_scene_modal();
        return;
    }

    if input_key_pressed(.F5) {
        if editor_is_playing() {
            editor_stop();
        } else if engine_state.current_scene {
            editor_play();
        }
        return;
    }

    if input_key_pressed(.DELETE) && editor_node_can_delete(selected_node) {
        editor_delete_node(selected_node);
        return;
    }
}

main_menu_request_open_scene_modal :: () {
    if editor_is_playing() then return;

    path := "game/scenes/main.toml";
    tab := editor_get_active_tab();
    if tab && tab.path {
        path = tab.path;
    }

    ui_copy_string_to_buffer(path, main_menu_open_scene_buffer.data, main_menu_open_scene_buffer.count);
    main_menu_open_scene_requested = true;
}

main_menu_draw_open_scene_modal :: () {
    if main_menu_open_scene_requested {
        OpenPopup(UI_Icon_Window_Title(ICON_FA_FOLDER_OPEN, "Open Scene", "Open Scene"));
        main_menu_open_scene_requested = false;
    }

    if BeginPopupModal(UI_Icon_Window_Title(ICON_FA_FOLDER_OPEN, "Open Scene", "Open Scene"), null, .AlwaysAutoResize) {
        TextUnformatted("Scene path");
        SetNextItemWidth(420.0);
        InputText("##open_scene_path", main_menu_open_scene_buffer.data, main_menu_open_scene_buffer.count);

        Separator();

        path := to_string(main_menu_open_scene_buffer.data);
        can_open := path.count > 0 && !editor_is_playing();
        BeginDisabled(!can_open);
        if Button(UI_Icon_Label(ICON_FA_FOLDER_OPEN, "Open"), ImVec2.{100, 0}) {
            if editor_open_scene(path) {
                CloseCurrentPopup();
            }
        }
        EndDisabled();

        SameLine();
        if Button(UI_Icon_Label(ICON_FA_XMARK, "Cancel"), ImVec2.{100, 0}) {
            CloseCurrentPopup();
        }

        EndPopup();
    }
}

main_menu_draw_render_mode_items :: () {
    if MenuItem(UI_Icon_Label(ICON_FA_SUN, "Lit"), "", selected = editor_context.render_mode == .LIT) {
        editor_context.render_mode = .LIT;
    }
    if MenuItem(UI_Icon_Label(ICON_FA_MOON, "Unlit"), "", selected = editor_context.render_mode == .UNLIT) {
        editor_context.render_mode = .UNLIT;
    }
    if MenuItem(UI_Icon_Label(ICON_FA_CUBE, "Wireframe"), "", selected = editor_context.render_mode == .WIREFRAME) {
        editor_context.render_mode = .WIREFRAME;
    }
    if MenuItem(UI_Icon_Label(ICON_FA_LIGHTBULB, "Lighting Only"), "", selected = editor_context.render_mode == .LIGHTING_ONLY) {
        editor_context.render_mode = .LIGHTING_ONLY;
    }
    if MenuItem(UI_Icon_Label(ICON_FA_PALETTE, "Albedo"), "", selected = editor_context.render_mode == .ALBEDO) {
        editor_context.render_mode = .ALBEDO;
    }
}
