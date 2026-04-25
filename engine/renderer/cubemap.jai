#scope_file

#import "GL";
#import "stb_image";

#scope_export

Cubemap :: struct {
    id: u32;
    size: s32;
}

cubemap_create_from_files :: (
    right_path: string,
    left_path: string,
    top_path: string,
    bottom_path: string,
    front_path: string,
    back_path: string
) -> *Cubemap {
    cubemap := New(Cubemap);

    glGenTextures(1, *cubemap.id);
    glBindTexture(GL_TEXTURE_CUBE_MAP, cubemap.id);

    face_paths: [6] string = .[
        right_path,
        left_path,
        top_path,
        bottom_path,
        front_path,
        back_path
    ];
    face_targets: [6] u32 = .[
        GL_TEXTURE_CUBE_MAP_POSITIVE_X,
        GL_TEXTURE_CUBE_MAP_NEGATIVE_X,
        GL_TEXTURE_CUBE_MAP_POSITIVE_Y,
        GL_TEXTURE_CUBE_MAP_NEGATIVE_Y,
        GL_TEXTURE_CUBE_MAP_POSITIVE_Z,
        GL_TEXTURE_CUBE_MAP_NEGATIVE_Z
    ];

    for face_path, face_index: face_paths {
        face_target := face_targets[face_index];

        desired_channels: s32 = 4;
        width: s32;
        height: s32;
        channels: s32;
        face_path_c_str := to_c_string(face_path);
        defer free(face_path_c_str);
        data := stbi_load(
            face_path_c_str,
            *width,
            *height,
            *channels,
            desired_channels
        );

        if !data {
            log_error("Failed to load cubemap face: %", face_path);
            glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
            glDeleteTextures(1, *cubemap.id);
            free(cubemap);
            return null;
        }
        defer stbi_image_free(data);

        if width != height {
            log_error("Cubemap face is not square % (%x%)", face_path , width, height);
            glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
            glDeleteTextures(1, *cubemap.id);
            free(cubemap);
            return null;
        }

        if cubemap.size == 0 {
            cubemap.size = width;
        } else if width != cubemap.size || height != cubemap.size {
            log_error(
                "Cubemap face size mismatch: % (%x%), expected %x%",
                face_path,
                width,
                height,
                cubemap.size,
                cubemap.size
            );
            glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
            glDeleteTextures(1, *cubemap.id);
            free(cubemap);
            return null;
        }

        glTexImage2D(
            face_target,
            0,
            GL_RGBA8,
            cast(u32) width,
            cast(u32) height,
            0,
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            data
        );
    }

    set_default_cubemap_parameters();
    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);

    return cubemap;
}

cubemap_create_solid_color :: (color: Vector4 = .{0, 0, 0, 1}) -> *Cubemap {
    cubemap := New(Cubemap);
    cubemap.size = 1;

    glGenTextures(1, *cubemap.id);
    glBindTexture(GL_TEXTURE_CUBE_MAP, cubemap.id);

    face_targets: [6] u32 = .[
        GL_TEXTURE_CUBE_MAP_POSITIVE_X,
        GL_TEXTURE_CUBE_MAP_NEGATIVE_X,
        GL_TEXTURE_CUBE_MAP_POSITIVE_Y,
        GL_TEXTURE_CUBE_MAP_NEGATIVE_Y,
        GL_TEXTURE_CUBE_MAP_POSITIVE_Z,
        GL_TEXTURE_CUBE_MAP_NEGATIVE_Z
    ];

    rgba: [4]u8 = .[
        cast(u8) (clamp(color.x, 0, 1) * 255),
        cast(u8) (clamp(color.y, 0, 1) * 255),
        cast(u8) (clamp(color.z, 0, 1) * 255),
        cast(u8) (clamp(color.w, 0, 1) * 255),
    ];

    for face_targets {
        glTexImage2D(
            it,
            0,
            GL_RGBA8,
            1,
            1,
            0,
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            rgba.data
        );
    }

    set_default_cubemap_parameters();
    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);

    return cubemap;
}

cubemap_destroy :: (cubemap: *Cubemap) {
    assert(cubemap != null, "cubemap_destroy: cubemap is null");
    assert(cubemap.id != 0, "cubemap_destroy: cubemap.id is 0");

    glDeleteTextures(1, *cubemap.id);
    free(cubemap);
}

cubemap_bind :: (cubemap: *Cubemap, slot: u32 = 0) {
    assert(cubemap != null, "cubemap_bind: cubemap is null");

    glActiveTexture(GL_TEXTURE0 + slot);
    glBindTexture(GL_TEXTURE_CUBE_MAP, cubemap.id);
}

cubemap_unbind :: (slot: u32 = 0) {
    glActiveTexture(GL_TEXTURE0 + slot);
    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
}

#scope_file

set_default_cubemap_parameters :: () {
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
}
