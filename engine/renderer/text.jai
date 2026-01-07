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
}

text_state: Text_State;

#scope_module

default_font: *Font;

#scope_export

Glyph :: struct {
    texture_id: u32;
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
    glBufferData(GL_ARRAY_BUFFER, size_of(float) * 6 * 4, null, GL_DYNAMIC_DRAW);
    
    glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, 4 * size_of(float), null);
    glEnableVertexAttribArray(0);
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);

    text_state.shader = shader_create_from_file(
        "assets/shaders/text.vert",
        "assets/shaders/text.frag"
    );

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
    
    glDeleteVertexArrays(1, *text_state.vao_id);
    glDeleteBuffers(1, *text_state.vbo_id);
    
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

    error := FT_New_Face(text_state.library, temp_c_string(path), 0, *font.face);
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
    if !font return;

    for c: 0..127 {
        if font.glyphs[c].texture_id != 0 {
            glDeleteTextures(1, *font.glyphs[c].texture_id);
        }
    }

    FT_Done_Face(font.face);
    if font.path.data free(font.path.data);
    free(font);
}

font_reload_from_file :: (font: *Font, path: string, pixel_size: u32) -> bool {
    if !font return false;
    
    new_face: FT_Face;
    error := FT_New_Face(text_state.library, temp_c_string(path), 0, *new_face);
    if error != 0 {
        log_error("Failed to reload font: %", path);
        return false;
    }
    
    for c: 0..127 {
        if font.glyphs[c].texture_id != 0 {
            glDeleteTextures(1, *font.glyphs[c].texture_id);
            font.glyphs[c].texture_id = 0;
        }
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
    color := Color.{ 1.0, 1.0, 1.0, 1.0 }
) -> width: float {
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
    glUniform4f(color_location, color.r, color.g, color.b, color.a);
    
    sampler_location := glGetUniformLocation(text_state.shader.id, "u_text");
    glUniform1i(sampler_location, 0);
    
    glActiveTexture(GL_TEXTURE0);
    glBindVertexArray(text_state.vao_id);

    cursor_x := x;

    for i: 0..text.count - 1 {
        c := text[i];
        if c >= 128 continue;

        glyph := font.glyphs[c];
        
        defer cursor_x += cast(float) glyph.advance * scale;
        
        if glyph.texture_id == 0 continue;

        xpos := cursor_x + cast(float) glyph.bearing_x * scale;
        ypos := y - cast(float) (glyph.height - glyph.bearing_y) * scale;

        w := cast(float) glyph.width * scale;
        h := cast(float) glyph.height * scale;

        vertices: [24] float = .[
            xpos, ypos + h, 0.0, 0.0,
            xpos, ypos, 0.0, 1.0,
            xpos + w, ypos, 1.0, 1.0,
            xpos, ypos + h, 0.0, 0.0,
            xpos + w, ypos, 1.0, 1.0,
            xpos + w, ypos + h, 1.0, 0.0,
        ];

        glBindTexture(GL_TEXTURE_2D, glyph.texture_id);
        
        glBindBuffer(GL_ARRAY_BUFFER, text_state.vbo_id);
        glBufferSubData(GL_ARRAY_BUFFER, 0, size_of(float) * 24, vertices.data);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        
        glDrawArrays(GL_TRIANGLES, 0, 6);
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
    for i: 0..text.count-1 {
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

    for c: 0..127 {
        error := FT_Load_Char(font.face, cast(u64) c, FT_LOAD_RENDER);
        if error != 0 continue;

        glyph := font.face.glyph;
        
        font.glyphs[c].width = cast(s32) glyph.bitmap.width;
        font.glyphs[c].height = cast(s32) glyph.bitmap.rows;
        font.glyphs[c].bearing_x = glyph.bitmap_left;
        font.glyphs[c].bearing_y = glyph.bitmap_top;
        font.glyphs[c].advance = cast(s32) (glyph.advance.x >> 6);
        
        if glyph.bitmap.width == 0 || glyph.bitmap.rows == 0 {
            font.glyphs[c].texture_id = 0;
            continue;
        }
        
        texture_id: u32;
        glGenTextures(1, *texture_id);
        glBindTexture(GL_TEXTURE_2D, texture_id);
        glTexImage2D(
            GL_TEXTURE_2D,
            0,
            GL_R8,
            cast(u32) glyph.bitmap.width,
            cast(u32) glyph.bitmap.rows,
            0, 
            GL_RED,
            GL_UNSIGNED_BYTE,
            glyph.bitmap.buffer
        );

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

        font.glyphs[c].texture_id = texture_id;
    }

    font.line_height = cast(s32) (font.face.size.metrics.height >> 6);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
}
