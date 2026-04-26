#scope_file

#import "Basic";
#import "jai-imgui";

#scope_export

viewport_draw :: () {
    using engine_state;

    Begin("Viewport");
    
    ui_state.viewport_hovered = IsWindowHovered();
    ui_state.viewport_focused = IsWindowFocused();
    ui_state.viewport_image_visible = false;
    ui_state.viewport_screen_min = .{0, 0};
    ui_state.viewport_screen_max = .{0, 0};
    ui_state.viewport_size = .{0, 0};

    size := GetContentRegionAvail();
    
    if size.x > 0 && size.y > 0 {
        scale_x := window.content_scale_x;
        scale_y := window.content_scale_y;
        
        fb_width := cast(s32)(size.x * scale_x);
        fb_height := cast(s32)(size.y * scale_y);

        // resize framebuffer if needed
        if main_framebuffer &&
          (main_framebuffer.pixel_width != fb_width || main_framebuffer.pixel_height != fb_height) {
            framebuffer_resize(main_framebuffer, fb_width, fb_height);
            
            renderer_set_viewport_size(fb_width, fb_height);
        }

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
            ui_state.viewport_screen_min = GetItemRectMin();
            ui_state.viewport_screen_max = GetItemRectMax();
            ui_state.viewport_size = ui_state.viewport_screen_max - ui_state.viewport_screen_min;
        }
    }
    End();

} @UI_Window
