#scope_file

#import "Basic";
#import "jai-imgui";

#scope_export

main_menu_draw :: () {
    if BeginMainMenuBar() {
        if BeginMenu("File") {
            if MenuItem("New Scene", "Ctrl+N", enabled = false) {
            }
            if MenuItem("Load Scene...", "Ctrl+O", enabled = false) {
            }
            can_save_scene := cast(bool) engine_state.current_scene && !editor_is_playing();
            if MenuItem("Save Scene", "Ctrl/Cmd+S", enabled = can_save_scene) {
                editor_save_active_scene();
            }
            Separator();
            if MenuItem("Exit", "Alt+F4") {
                window_set_should_close(engine_state.window, true);
            }
            EndMenu();
        }

        if BeginMenu("Run") {
            if MenuItem("Play", "F5", enabled = false) {
            }
            if MenuItem("Stop", "Shift+F5", enabled = false) {
            }
            EndMenu();
        }
        
        if BeginMenu("Edit") {
            can_add_node := cast(bool) selected_node && !selected_node.instance_path;
            if MenuItem("Add Node", "", enabled = can_add_node) {
                node_add_node(selected_node);
                editor_mark_current_scene_dirty();
            }
            EndMenu();
        }

        if BeginMenu("View") {
            MenuItem("ImGui Demo", "", *ui_state.draw_demo);

            if engine_state.window {
                vsync_enabled := window_get_vsync(engine_state.window);
                if MenuItem("VSync", "", selected = vsync_enabled) {
                    window_set_vsync(engine_state.window, !vsync_enabled);
                }
            }
            EndMenu();
        }

        EndMainMenuBar();
    }
} @UI_Window
