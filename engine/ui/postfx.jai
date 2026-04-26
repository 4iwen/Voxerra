#scope_export

#import "Basic";
#import "jai-imgui";

postfx_draw :: () {
    if !ui_state.show_postfx_window then return;

    SetNextWindowSize(ImVec2.{320, 0}, Cond.FirstUseEver);
    if Begin("PostFX", *ui_state.show_postfx_window) {
        postfx_state := postfx_get_state();

        Checkbox("Enabled", *postfx_state.enabled);
        Checkbox("Fog", *postfx_state.fog_enabled);

        Separator();

        BeginDisabled(!postfx_state.enabled);
        ColorEdit4("Fog Color", cast(*[4] float) *postfx_state.fog_color.x);
        DragFloat("Fog Near", *postfx_state.fog_near, 0.1, 0.0, 1000.0);
        DragFloat("Fog Far", *postfx_state.fog_far, 0.1, 0.0, 1000.0);
        EndDisabled();
    }
    End();
} @UI_Window
