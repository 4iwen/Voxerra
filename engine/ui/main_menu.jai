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
            if MenuItem("Save Scene...", "Ctrl+S", enabled = false) {
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
            if MenuItem("Add Node", "", enabled = cast(bool) selected_node) {
                node_add_node(selected_node);
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
