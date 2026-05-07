// File:        viewport.jai
// Author:      Lukáš Bien
// Description: Draws the editor viewport window and coordinates viewport interaction state.

#scope_file

#import "Basic";
#import "jai-imgui";

#scope_export

viewport_draw :: () {
    using engine_state;

    Begin(UI_Icon_Window_Title(ICON_FA_DISPLAY, "Viewport", "Viewport"));

    ui_state.viewport_hovered = false;
    ui_state.viewport_image_visible = false;
    ui_state.viewport_screen_min = .{0, 0};
    ui_state.viewport_screen_max = .{0, 0};
    ui_state.viewport_size = .{0, 0};
    ui_state.viewport_pixel_width = 0;
    ui_state.viewport_pixel_height = 0;

    scene_tabs_draw();

    if BeginChild("viewport_scene_tab_content", ImVec2.{0, 0}, .None, .MenuBar) {
        if BeginMenuBar() {
            editor_gizmo_draw_viewport_menu_bar();
            EndMenuBar();
        }

        size := GetContentRegionAvail();

        if size.x > 0 && size.y > 0 {
            scale_x := window.content_scale_x;
            scale_y := window.content_scale_y;

            fb_width := cast(s32)(size.x * scale_x);
            fb_height := cast(s32)(size.y * scale_y);
            ui_state.viewport_pixel_width = max(fb_width, 1);
            ui_state.viewport_pixel_height = max(fb_height, 1);

            if main_framebuffer {
                tex_ref := ImTextureRef.{
                    _TexData = null,
                    _TexID = cast(ImTextureID) cast(u64) main_framebuffer.color_texture,
                };
                Image(
                    tex_ref,
                    size,
                    // flip uvs
                    .{0, 1},
                    .{1, 0}
                );

                ui_state.viewport_image_visible = true;
                ui_state.viewport_hovered = IsItemHovered();
                ui_state.viewport_screen_min = GetItemRectMin();
                ui_state.viewport_screen_max = GetItemRectMax();
                ui_state.viewport_size = ui_state.viewport_screen_max - ui_state.viewport_screen_min;

                dropped_asset := editor_accept_asset_drop();
                defer editor_asset_drop_destroy(*dropped_asset);
                if dropped_asset.path && current_scene && current_scene.root {
                    drop_position := editor_viewport_drop_position();
                    if dropped_asset.type == .MODEL {
                        editor_create_model_node_from_asset(
                            current_scene.root,
                            dropped_asset.path,
                            drop_position
                        );
                    } else if dropped_asset.type == .SCENE {
                        editor_create_scene_instance_from_asset(
                            current_scene.root,
                            dropped_asset.path,
                            drop_position
                        );
                    } else if dropped_asset.type == .TEXTURE {
                        editor_create_sprite_node_from_asset(
                            current_scene.root,
                            dropped_asset.path,
                            drop_position
                        );
                    }
                }

                editor_curve_draw_viewport_overlay();
                editor_gizmo_draw();
            }
        }
    }
    EndChild();

    End();

} @UI_Window
