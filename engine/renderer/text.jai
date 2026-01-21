#scope_file

#import "Basic";
#import "Math";
#import "Hash_Table";
#import "File";
#import "GL";
#import "freetype";

Text_State :: struct {
    library: FT_Library;
    vao_id: u32;
    vbo_id: u32;
    shader: *Shader;
    vertices: [..] float;
}

text_state: Text_State;

MAX_BATCH_CHARS :: 2048;

#scope_module

default_font: *Font;

#scope_export

Glyph :: struct {
    uv: Vector4;
    width: s32;
    height: s32;
    bearing_x: s32;
    bearing_y: s32;
    advance: s32;
}

Font :: struct {
    face: FT_Face;
    size: u32;
    glyphs: [128] Glyph;
    atlas_texture_id: u32;
    atlas_width: s32;
    atlas_height: s32;
    line_height: s32;
    path: string;
}

text_init :: () {
    error := FT_Init_FreeType(*text_state.library);
    if error != 0 {
        log_error("Failed to initialize freetype");
        return;
    }

    // setup rendering
    glGenVertexArrays(1, *text_state.vao_id);
    glGenBuffers(1, *text_state.vbo_id);
    
    glBindVertexArray(text_state.vao_id);
    glBindBuffer(GL_ARRAY_BUFFER, text_state.vbo_id);
    glBufferData(
        GL_ARRAY_BUFFER,
        size_of(float) * 6 * 4 * MAX_BATCH_CHARS,
        null,
        GL_DYNAMIC_DRAW
    );
    
    glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, 4 * size_of(float), null);
    glEnableVertexAttribArray(0);
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);

    text_state.shader = shader_create_from_file(
        "assets/shaders/text.vert",
        "assets/shaders/text.frag"
    );
    
    array_reserve(*text_state.vertices, MAX_BATCH_CHARS * 6 * 4);

    default_font = font_create_from_file(
        "assets/fonts/natural_mono_2/NaturalMono-Regular.ttf",
        48
    );

    log("Initialized text");
}

text_shutdown :: () {
    if default_font {
        font_destroy(default_font);
        default_font = null;
    }

    FT_Done_FreeType(text_state.library);
    
    if text_state.vao_id != 0 {
        glDeleteVertexArrays(1, *text_state.vao_id);
    }
    if text_state.vbo_id != 0 {
        glDeleteBuffers(1, *text_state.vbo_id);
    }
    
    text_state.vao_id = 0;
    text_state.vbo_id = 0;
    
    array_free(text_state.vertices);
    text_state.vertices.data = null;
    text_state.vertices.count = 0;
    text_state.vertices.allocated = 0;
    
    if text_state.shader {
        shader_destroy(text_state.shader);
        text_state.shader = null;
    }

    log("Shutdown text");
}

font_get_default :: () -> *Font {
    return default_font;
}

font_create_from_file :: (path: string, pixel_size: u32) -> *Font {
    font := New(Font);
    font.size = pixel_size;
    font.path = copy_string(path);

    path_c_string := to_c_string(path);
    defer free(path_c_string);
    error := FT_New_Face(text_state.library, path_c_string, 0, *font.face);
    if error != 0 {
        log_error("Failed to load font: %", path);
        free(font.path.data);
        free(font);
        return null;
    }

    load_glyphs(font);
    return font;
}

font_destroy :: (font: *Font) {
    if !font {
        return;
    }

    if font.atlas_texture_id != 0 {
        glDeleteTextures(1, *font.atlas_texture_id);
    }

    FT_Done_Face(font.face);
    if font.path.data {
        free(font.path.data);
    }
    free(font);
}

font_reload_from_file :: (font: *Font, path: string, pixel_size: u32) -> bool {
    if !font return false;
    
    new_face: FT_Face;
    path_c_string := to_c_string(path);
    defer free(path_c_string);
    error := FT_New_Face(text_state.library, path_c_string, 0, *new_face);
    if error != 0 {
        log_error("Failed to reload font: %", path);
        return false;
    }
    
    if font.atlas_texture_id != 0 {
        glDeleteTextures(1, *font.atlas_texture_id);
        font.atlas_texture_id = 0;
    }
    
    FT_Done_Face(font.face);
    font.face = new_face;
    
    font.size = pixel_size;
    load_glyphs(font);
    return true;
}

text_draw :: (
    font: *Font,
    text: string,
    x: float,
    y: float,
    font_size: float,
    color := Vector4.{1.0, 1.0, 1.0, 1.0}
) -> width: float {
    // ascii only for now, utf-8 glyphs are ignored
    scale := font_size / cast(float) font.size;

    viewport: [4] s32;
    glGetIntegerv(GL_VIEWPORT, viewport.data);
    screen_width := viewport[2];
    screen_height := viewport[3];

    // save blend state
    blend_enabled := glIsEnabled(GL_BLEND);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    // disable depth test for 2D text
    depth_enabled := glIsEnabled(GL_DEPTH_TEST);
    glDisable(GL_DEPTH_TEST);

    shader_use(text_state.shader);
    
    projection := orthographic_projection_matrix(
        0, cast(float) screen_width,
        0, cast(float) screen_height,
        -1, 1
    );
    shader_set_mat4(text_state.shader, "u_projection", projection);
    
    color_location := glGetUniformLocation(text_state.shader.id, "u_text_color");
    glUniform4f(color_location, color.x, color.y, color.z, color.w);
    
    sampler_location := glGetUniformLocation(text_state.shader.id, "u_text");
    glUniform1i(sampler_location, 0);
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, font.atlas_texture_id);
    glBindVertexArray(text_state.vao_id);

    // clear previous batch
    text_state.vertices.count = 0;

    cursor_x := x;
    chars_to_draw := 0;

    for i: 0..text.count - 1 {
        c := text[i];
        if c >= 128 continue;

        glyph := font.glyphs[c];
        
        defer cursor_x += cast(float) glyph.advance * scale;
        
        if glyph.width == 0 || glyph.height == 0 {
            continue;
        }

        xpos := cursor_x + cast(float) glyph.bearing_x * scale;
        ypos := y - cast(float) (glyph.height - glyph.bearing_y) * scale;

        w := cast(float) glyph.width * scale;
        h := cast(float) glyph.height * scale;

        // append 6 vertices to batch
    
        // triangle 1
        array_add(*text_state.vertices, xpos); // x
        array_add(*text_state.vertices, ypos + h); // y
        array_add(*text_state.vertices, glyph.uv.x); // u
        array_add(*text_state.vertices, glyph.uv.y); // v

        array_add(*text_state.vertices, xpos); // x
        array_add(*text_state.vertices, ypos); // y
        array_add(*text_state.vertices, glyph.uv.x); // u
        array_add(*text_state.vertices, glyph.uv.w); // v

        array_add(*text_state.vertices, xpos + w); // x
        array_add(*text_state.vertices, ypos); // y
        array_add(*text_state.vertices, glyph.uv.z); // u
        array_add(*text_state.vertices, glyph.uv.w); // v

        // triangle 2
        array_add(*text_state.vertices, xpos); // x
        array_add(*text_state.vertices, ypos + h); // y
        array_add(*text_state.vertices, glyph.uv.x); // u
        array_add(*text_state.vertices, glyph.uv.y); // v

        array_add(*text_state.vertices, xpos + w); // x
        array_add(*text_state.vertices, ypos); // y
        array_add(*text_state.vertices, glyph.uv.z); // u
        array_add(*text_state.vertices, glyph.uv.w); // v

        array_add(*text_state.vertices, xpos + w); // x
        array_add(*text_state.vertices, ypos + h); // y
        array_add(*text_state.vertices, glyph.uv.z); // u
        array_add(*text_state.vertices, glyph.uv.y); // v

        chars_to_draw += 1;
        
        if chars_to_draw >= MAX_BATCH_CHARS {
            glBindBuffer(GL_ARRAY_BUFFER, text_state.vbo_id);
            glBufferData(GL_ARRAY_BUFFER, size_of(float) * text_state.vertices.count, text_state.vertices.data, GL_DYNAMIC_DRAW);
            glDrawArrays(GL_TRIANGLES, 0, cast(u32) (chars_to_draw * 6));
            
            text_state.vertices.count = 0;
            chars_to_draw = 0;
        }
    }

    if chars_to_draw > 0 {
        glBindBuffer(GL_ARRAY_BUFFER, text_state.vbo_id);
        glBufferData(GL_ARRAY_BUFFER, size_of(float) * text_state.vertices.count, text_state.vertices.data, GL_DYNAMIC_DRAW);
        glDrawArrays(GL_TRIANGLES, 0, cast(u32) (chars_to_draw * 6));
    }

    glBindVertexArray(0);
    glBindTexture(GL_TEXTURE_2D, 0);
    
    // restore state
    if !blend_enabled {
        glDisable(GL_BLEND);
    }
    if depth_enabled {
        glEnable(GL_DEPTH_TEST);
    }

    return cursor_x - x;
}

text_get_width :: (font: *Font, text: string, font_size: float) -> float {
    if !font return 0;

    scale := font_size / cast(float) font.size;
    width: float = 0;
    for i: 0..text.count - 1 {
        c := text[i];
        if c >= 128 continue;
        width += cast(float) font.glyphs[c].advance * scale;
    }
    return width;
}

text_get_height :: (font: *Font, font_size: float) -> float {
    if !font return 0;
    scale := font_size / cast(float) font.size;
    return cast(float) font.line_height * scale;
}

font_get_line_height :: (font: *Font, font_size: float) -> float {
    if !font return 0;
    scale := font_size / cast(float) font.size;
    return cast(float) font.line_height * scale;
}

font_get_baseline :: (font: *Font, font_size: float) -> float {
    if !font return 0;
    scale := font_size / cast(float) font.size;
    return cast(float) (font.size / 4) * scale;
}

#scope_file

load_glyphs :: (font: *Font) {
    FT_Set_Pixel_Sizes(font.face, 0, font.size);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    ATLAS_WIDTH :: 1024;
    ATLAS_HEIGHT :: 1024;

    font.atlas_width = ATLAS_WIDTH;
    font.atlas_height = ATLAS_HEIGHT;
    
    atlas_data := cast(*u8) alloc(ATLAS_WIDTH * ATLAS_HEIGHT);
    defer free(atlas_data);
    memset(atlas_data, 0, ATLAS_WIDTH * ATLAS_HEIGHT);

    current_x := 0;
    current_y := 0;
    row_height := 0;
    padding :: 1;

    for c: 0..127 {
        error := FT_Load_Char(font.face, cast(FT_ULong) c, FT_LOAD_RENDER);
        if error != 0 continue;

        glyph := font.face.glyph;
        bmp := glyph.bitmap;
        
        font.glyphs[c].width = cast(s32) bmp.width;
        font.glyphs[c].height = cast(s32) bmp.rows;
        font.glyphs[c].bearing_x = glyph.bitmap_left;
        font.glyphs[c].bearing_y = glyph.bitmap_top;
        font.glyphs[c].advance = cast(s32) (glyph.advance.x >> 6);

        if bmp.width == 0 || bmp.rows == 0 {
            continue;
        }

        // check if we need to move to next row
        if current_x + cast(s32) bmp.width + padding >= ATLAS_WIDTH {
            current_x = 0;
            current_y += row_height + padding;
            row_height = 0;
        }
        
        if cast(s32) bmp.rows > row_height {
            row_height = cast(s32) bmp.rows;
        }

        // copy bitmap to atlas
        for src_y: 0..bmp.rows - 1 {
            for src_x: 0..bmp.width - 1 {
                src_index := src_y * bmp.width + src_x;
                dst_index := (current_y + src_y) * ATLAS_WIDTH + (current_x + src_x);
                atlas_data[dst_index] = bmp.buffer[src_index];
            }
        }

        // calculate uvs
        u0 := cast(float) current_x / cast(float) ATLAS_WIDTH;
        v0 := cast(float) current_y / cast(float) ATLAS_HEIGHT;
        u1 := cast(float) (current_x + bmp.width) / cast(float) ATLAS_WIDTH;
        v1 := cast(float) (current_y + bmp.rows) / cast(float) ATLAS_HEIGHT;
        
        font.glyphs[c].uv.x = u0;
        font.glyphs[c].uv.y = v0;
        font.glyphs[c].uv.z = u1;
        font.glyphs[c].uv.w = v1;

        current_x += cast(s32) bmp.width + padding;
    }

    // create single atlas texture
    glGenTextures(1, *font.atlas_texture_id);
    glBindTexture(GL_TEXTURE_2D, font.atlas_texture_id);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_R8,
        ATLAS_WIDTH,
        ATLAS_HEIGHT,
        0, 
        GL_RED,
        GL_UNSIGNED_BYTE,
        atlas_data
    );

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    font.line_height = cast(s32) (font.face.size.metrics.height >> 6);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
}
