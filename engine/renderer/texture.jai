#scope_file

#import "Basic";
#import "GL";
#import "stb_image";

#scope_export

Texture :: struct {
    id: u32;
    width: s32;
    height: s32;
}

texture_create_from_file :: (path: string) -> Texture {
    texture: Texture;

    // flip texture
    stbi_set_flip_vertically_on_load(1);

    width: s32;
    height: s32;
    channels: s32;
    data := stbi_load(temp_c_string(path), *width, *height, *channels, 4);

    if !data {
        log_error("Failed to load texture: %", path);
        return texture;
    }

    defer stbi_image_free(data);

    texture.width = width;
    texture.height = height;

    glGenTextures(1, *texture.id);
    glBindTexture(GL_TEXTURE_2D, texture.id);

    // @Todo: texture specification should set this
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGBA,
        cast(u32) width,
        cast(u32) height,
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        data
    );
    glGenerateMipmap(GL_TEXTURE_2D);

    return texture;
}

texture_create_from_data :: (width: s32, height: s32, data: *u8) -> Texture {
    texture: Texture;
    texture.width = width;
    texture.height = height;

    glGenTextures(1, *texture.id);
    glBindTexture(GL_TEXTURE_2D, texture.id);
    
    // @Todo: texture specification should set this
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
    
    return texture;
}

texture_bind :: (texture: Texture, slot: u32 = 0) {
    glActiveTexture(GL_TEXTURE0 + slot);
    glBindTexture(GL_TEXTURE_2D, texture.id);
}

texture_destroy :: (texture: Texture) {
    glDeleteTextures(1, *texture.id);
}
