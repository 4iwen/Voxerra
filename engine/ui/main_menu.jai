#scope_file

#import "Basic";
#import "jai-imgui";

#scope_export

main_menu_draw :: () {
    if BeginMainMenuBar() {
        if BeginMenu("File") {
            if MenuItem("New Scene", "Ctrl+N") {
                // @ToDo: clear scene, prompt to save a scene or discard
            }
            if MenuItem("Load Scene...", "Ctrl+O") {
                // @ToDo: load TOML
            }
            if MenuItem("Save Scene...", "Ctrl+S") {
                // @ToDo: save TOML
            }
            Separator();
            if MenuItem("Exit", "Alt+F4") {
                window_set_should_close(engine_state.window, true);
            }
            EndMenu();
        }
        
        if BeginMenu("Edit") {
            if MenuItem("Add Node", "", enabled = cast(bool) selected_node) {
                new_node := node_add_node(selected_node);
                // mesh_component := node_add_component(new_node, Static_Mesh_Component);
            }
            EndMenu();
        }

        if BeginMenu("View") {
            MenuItem("ImGui Demo", "", *ui_state.draw_demo);
            EndMenu();
        }

        EndMainMenuBar();
    }
} @UI_Window
