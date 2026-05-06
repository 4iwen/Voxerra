// File:        fog.jai
// Author:      Lukáš Bien
// Description: Draws the editor fog controls for scene environment settings.

#scope_file

#import "Basic";
#import "jai-imgui";

#scope_export

fog_draw :: () {
    SetNextWindowSize(ImVec2.{320, 0}, Cond.FirstUseEver);
    if Begin(UI_Icon_Window_Title(ICON_FA_WAND_MAGIC_SPARKLES, "Fog", "Fog")) {
        scene := engine_state.current_scene;
        if !scene {
            TextDisabled("No scene loaded");
            End();
            return;
        }

        env := *scene.environment;

        TextUnformatted("Environment");
        if ColorEdit4("Clear Color", cast(*[4] float) *env.clear_color.x) {
            editor_mark_current_scene_dirty();
        }
        if ColorEdit3("Ambient", cast(*[3] float) *env.ambient_color.x) {
            scene_apply_environment_settings(scene);
            editor_mark_current_scene_dirty();
        }
        if Checkbox("Skybox", *env.skybox_enabled) {
            editor_mark_current_scene_dirty();
        }

        Separator();
        TextUnformatted("Fog Resolve");

        if Checkbox("Resolve Opaque Fog", *env.fog_resolve_enabled) {
            scene_apply_environment_settings(scene);
            editor_mark_current_scene_dirty();
        }
        if Checkbox("Fog", *env.fog_enabled) {
            scene_apply_environment_settings(scene);
            editor_mark_current_scene_dirty();
        }

        Separator();

        BeginDisabled(!env.fog_enabled);
        if ColorEdit4("Fog Color", cast(*[4] float) *env.fog_color.x) {
            scene_apply_environment_settings(scene);
            editor_mark_current_scene_dirty();
        }
        if DragFloat("Fog Near", *env.fog_near, 0.1, 0.0, 1000.0) {
            scene_apply_environment_settings(scene);
            editor_mark_current_scene_dirty();
        }
        if DragFloat("Fog Far", *env.fog_far, 0.1, 0.0, 1000.0) {
            scene_apply_environment_settings(scene);
            editor_mark_current_scene_dirty();
        }
        EndDisabled();
    }
    End();
} @UI_Window
