#scope_file

#import "Basic";
#import "GL";
#import "stb_image";

#scope_module

default_texture: Texture;

DEFAULT_TEXTURE_SPEC :: Texture_Spec.{
    min_filter = .LINEAR_MIPMAP_LINEAR,
    mag_filter = .NEAREST,
    wrap_s = .REPEAT,
    wrap_t = .REPEAT,
    generate_mipmaps = true,
};

texture_init_default :: () {
    width :: 8;
    height :: 8;

    data := cast(*u8) alloc(width * height * 4);

    for y: 0..height-1 {
        for x: 0..width-1 {
            index := (y * width + x) * 4;
            
            // checkerboard pattern
            is_purple := ((x / 2) + (y / 2)) % 2 == 0;
            
            if is_purple {
                data[index + 0] = 255; // r
                data[index + 1] = 0; // g
                data[index + 2] = 255; // b
                data[index + 3] = 255; // a
            } else {
                data[index + 0] = 0; // r
                data[index + 1] = 0; // g
                data[index + 2] = 0; // b
                data[index + 3] = 255; // a
            }
        }
    }

    default_texture = texture_create_from_data(width, height, data);
    free(data);
}

texture_cleanup_default :: () {
    if default_texture.id != 0 {
        texture_destroy(default_texture);
    }
}

texture_get_default :: () -> Texture {
    return default_texture;
}

#scope_export

Texture :: struct {
    id: u32;
    width: s32;
    height: s32;
}

Texture_Spec :: struct {
    min_filter: Texture_Filter = .LINEAR_MIPMAP_LINEAR;
    mag_filter: Texture_Filter = .NEAREST;
    wrap_s: Texture_Wrap = .REPEAT;
    wrap_t: Texture_Wrap = .REPEAT;
    generate_mipmaps: bool = true;
}

Texture_Filter :: enum {
    NEAREST;
    LINEAR;
    NEAREST_MIPMAP_NEAREST;
    LINEAR_MIPMAP_NEAREST;
    NEAREST_MIPMAP_LINEAR;
    LINEAR_MIPMAP_LINEAR;
}

Texture_Wrap :: enum {
    REPEAT;
    CLAMP_TO_EDGE;
    CLAMP_TO_BORDER;
    MIRRORED_REPEAT;
}

texture_create_from_file :: (path: string, spec := DEFAULT_TEXTURE_SPEC) -> Texture {
    texture: Texture;

    // flip texture
    stbi_set_flip_vertically_on_load(1);

    desired_channels: s32 = 4;
    width: s32;
    height: s32;
    channels: s32;
    data := stbi_load(temp_c_string(path), *width, *height, *channels, desired_channels);

    if !data {
        log_error("Failed to load texture: %, using default", path);
        return texture_get_default();
    }

    defer stbi_image_free(data);

    texture.width = width;
    texture.height = height;

    glGenTextures(1, *texture.id);
    glBindTexture(GL_TEXTURE_2D, texture.id);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, to_opengl_filter(spec.min_filter));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, to_opengl_filter(spec.mag_filter));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, to_opengl_wrap(spec.wrap_s));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, to_opengl_wrap(spec.wrap_t));

    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGBA8,
        cast(u32) width,
        cast(u32) height,
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        data
    );

    if spec.generate_mipmaps {
        glGenerateMipmap(GL_TEXTURE_2D);
    }

    if spec.generate_mipmaps && !is_mipmapped_filter(spec.min_filter) {
        log("Texture created with mipmaps but min_filter does not use them", flags = .WARNING);
    }
    if !spec.generate_mipmaps && is_mipmapped_filter(spec.min_filter) {
        log("Mipmapped min_filter used but mipmaps are not generated", flags = .WARNING);
    }

    return texture;
}

texture_create_from_data :: (width: s32, height: s32, data: *u8, spec := DEFAULT_TEXTURE_SPEC) -> Texture {
    texture: Texture;
    texture.width = width;
    texture.height = height;

    glGenTextures(1, *texture.id);
    glBindTexture(GL_TEXTURE_2D, texture.id);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, to_opengl_filter(spec.min_filter));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, to_opengl_filter(spec.mag_filter));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, to_opengl_wrap(spec.wrap_s));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, to_opengl_wrap(spec.wrap_t));
    
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGBA8,
        cast(u32) width,
        cast(u32) height,
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        data
    );

    if spec.generate_mipmaps {
        glGenerateMipmap(GL_TEXTURE_2D);
    }

    if spec.generate_mipmaps && !is_mipmapped_filter(spec.min_filter) {
        log("Texture created with mipmaps but min_filter does not use them", flags = .WARNING);
    }
    if !spec.generate_mipmaps && is_mipmapped_filter(spec.min_filter) {
        log("Mipmapped min_filter used but mipmaps are not generated", flags = .WARNING);
    }

    return texture;
}

texture_bind :: (texture: Texture, slot: u32 = 0) {
    glActiveTexture(GL_TEXTURE0 + slot);
    glBindTexture(GL_TEXTURE_2D, texture.id);
}

texture_destroy :: (texture: Texture) {
    glDeleteTextures(1, *texture.id);
}

#scope_file

to_opengl_filter :: (filter: Texture_Filter) -> GLint {
    if filter == {
        case .NEAREST; return GL_NEAREST;
        case .LINEAR; return GL_LINEAR;
        case .NEAREST_MIPMAP_NEAREST; return GL_NEAREST_MIPMAP_NEAREST;
        case .LINEAR_MIPMAP_NEAREST; return GL_LINEAR_MIPMAP_NEAREST;
        case .NEAREST_MIPMAP_LINEAR; return GL_NEAREST_MIPMAP_LINEAR;
        case .LINEAR_MIPMAP_LINEAR; return GL_LINEAR_MIPMAP_LINEAR;

        case; return GL_LINEAR;
    }
}

to_opengl_wrap :: (wrap: Texture_Wrap) -> GLint {
    if wrap == {
        case .REPEAT; return GL_REPEAT;
        case .CLAMP_TO_EDGE; return GL_CLAMP_TO_EDGE;
        case .CLAMP_TO_BORDER; return GL_CLAMP_TO_BORDER;
        case .MIRRORED_REPEAT; return GL_MIRRORED_REPEAT;
        case; return GL_REPEAT;
    }
}

is_mipmapped_filter :: (filter: Texture_Filter) -> bool {
    return filter == .NEAREST_MIPMAP_NEAREST ||
           filter == .LINEAR_MIPMAP_NEAREST ||
           filter == .NEAREST_MIPMAP_LINEAR ||
           filter == .LINEAR_MIPMAP_LINEAR;
}
