#scope_file

#import "Basic";
#import "GL";

#scope_export

Framebuffer :: struct {
    id: u32;
    pixel_width: s32;
    pixel_height: s32;
    width: float;
    height: float;
    aspect: float;
    color_texture: u32;
    depth_buffer: u32;
}

framebuffer_create :: (width: s32, height: s32) -> *Framebuffer {
    framebuffer := New(Framebuffer);
    framebuffer.pixel_width = width;
    framebuffer.pixel_height = height;
    framebuffer.width = cast(float) width;
    framebuffer.height = cast(float) height;
    framebuffer.aspect = cast(float) width / cast(float) height;

    // create framebuffer
    glGenFramebuffers(1, *framebuffer.id);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer.id);

    // create color attachment
    glGenTextures(1, *framebuffer.color_texture);
    glBindTexture(GL_TEXTURE_2D, framebuffer.color_texture);

    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGBA8, 
        cast(u32) width,
        cast(u32) height,
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        null
    );

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glFramebufferTexture2D(
        GL_FRAMEBUFFER,
        GL_COLOR_ATTACHMENT0,
        GL_TEXTURE_2D,
        framebuffer.color_texture,
        0
    );

    // create depth buffer
    glGenRenderbuffers(1, *framebuffer.depth_buffer);
    glBindRenderbuffer(GL_RENDERBUFFER, framebuffer.depth_buffer);

    glRenderbufferStorage(
        GL_RENDERBUFFER,
        GL_DEPTH24_STENCIL8,
        cast(u32) width,
        cast(u32) height
    );

    glFramebufferRenderbuffer(
        GL_FRAMEBUFFER,
        GL_DEPTH_STENCIL_ATTACHMENT,
        GL_RENDERBUFFER,
        framebuffer.depth_buffer
    );

    // check completeness
    if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE {
        log_error("Framebuffer % is not complete", framebuffer.id);
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    return framebuffer;
}

framebuffer_destroy :: (framebuffer: *Framebuffer) {
    assert(framebuffer != null, "framebuffer_destroy: framebuffer is null");

    glDeleteTextures(1, *framebuffer.color_texture);
    glDeleteRenderbuffers(1, *framebuffer.depth_buffer);
    glDeleteFramebuffers(1, *framebuffer.id);
    free(framebuffer);
}

framebuffer_bind :: (framebuffer: *Framebuffer) {
    assert(framebuffer != null, "framebuffer_bind: framebuffer is null");

    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer.id);
    glViewport(
        0,
        0,
        cast(u32) framebuffer.pixel_width,
        cast(u32) framebuffer.pixel_height
    );
}

framebuffer_resize :: (framebuffer: *Framebuffer, width: s32, height: s32) {
    assert(framebuffer != null, "framebuffer_resize: framebuffer is null");

    if framebuffer.pixel_width == width && framebuffer.pixel_height == height {
        return;
    }

    framebuffer.pixel_width = width;
    framebuffer.pixel_height = height;
    framebuffer.width = cast(float) width;
    framebuffer.height = cast(float) height;
    framebuffer.aspect = cast(float) width / cast(float) height;

    glBindTexture(GL_TEXTURE_2D, framebuffer.color_texture);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGBA8, 
        cast(u32) width,
        cast(u32) height,
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        null
    );

    glBindRenderbuffer(GL_RENDERBUFFER, framebuffer.depth_buffer);
    glRenderbufferStorage(
        GL_RENDERBUFFER,
        GL_DEPTH24_STENCIL8,
        cast(u32) width,
        cast(u32) height
    );

    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer.id);
    if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE {
        log_error("Framebuffer % is not complete after resize", framebuffer.id);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

framebuffer_unbind :: () {
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}
