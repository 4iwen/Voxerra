#scope_file

#import "Basic";
#import "Math";
#import "File";
#import "GL";

#scope_export

Shader :: struct {
    id: u32;
    vertex_id: u32;
    fragment_id: u32;
}

shader_create_from_file :: (vertex_path: string, fragment_path: string) -> *Shader {
    vertex_source := read_entire_file(vertex_path);
    fragment_source := read_entire_file(fragment_path);

    return shader_create(vertex_source, fragment_source);
} 

shader_create :: (vertex_source: string, fragment_source: string) -> *Shader {
    shader := New(Shader);

    // vertex shader
    vertex_id := glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertex_id, 1, *temp_c_string(vertex_source), null);
    glCompileShader(vertex_id);

    // check for errors
    check_for_shader_compilation_errors(vertex_id);
    
    // fragment shader
    fragment_id := glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragment_id, 1, *temp_c_string(fragment_source), null);
    glCompileShader(fragment_id);

    // check for errors
    check_for_shader_compilation_errors(fragment_id);

    program_id := glCreateProgram();
    glAttachShader(program_id, vertex_id);
    glAttachShader(program_id, fragment_id);
    glLinkProgram(program_id);

    // check for errors
    check_for_program_linking_errors(program_id);

    shader.id = program_id;
    shader.vertex_id = vertex_id;
    shader.fragment_id = fragment_id;
    return shader;
}

shader_destroy :: (shader: *Shader) {
    glDeleteShader(shader.vertex_id);
    glDeleteShader(shader.fragment_id);
    glDeleteProgram(shader.id);
    free(shader);
}

shader_use :: (shader: *Shader) {
    glUseProgram(shader.id);

    shader_set_default_matrices(shader);
}

shader_set_default_matrices :: (shader: *Shader) {
    projection_loc := glGetUniformLocation(shader.id, "projection");
    view_loc := glGetUniformLocation(shader.id, "view");
    model_loc := glGetUniformLocation(shader.id, "model");
    
    identity := Matrix4_Identity;
    
    if projection_loc != -1 {
        glUniformMatrix4fv(projection_loc, 1, GL_TRUE, *identity.coef[0][0]);
    }
    if view_loc != -1 {
        glUniformMatrix4fv(view_loc, 1, GL_TRUE, *identity.coef[0][0]);
    }
    if model_loc != -1 {
        glUniformMatrix4fv(model_loc, 1, GL_TRUE, *identity.coef[0][0]);
    }
}

shader_set_mat4 :: (shader: *Shader, name: string, matrix: Matrix4) {
    location := glGetUniformLocation(shader.id, temp_c_string(name));
    glUniformMatrix4fv(location, 1, GL_TRUE, *matrix.coef[0][0]);
}

shader_set_int :: (shader: *Shader, name: string, value: s32) {
    location := glGetUniformLocation(shader.id, temp_c_string(name));
    glUniform1i(location, value);
}

shader_set_texture :: (shader: *Shader, name: string, texture: *Texture, slot: u32 = 0) {
    texture_to_bind: *Texture;

    if texture == null || texture.id == 0 {
        texture_to_bind = texture_get_default();
    } else {
        texture_to_bind = texture;
    }

    texture_bind(texture_to_bind, slot);
    shader_set_int(shader, name, xx slot);
}

#scope_file

check_for_shader_compilation_errors :: (shader_id: u32) -> bool{
    LOG_BUFFER_SIZE :: 512;
    success: GLint;

    glGetShaderiv(shader_id, GL_COMPILE_STATUS, *success);
    if !success {
        log_data: [LOG_BUFFER_SIZE] u8;
        glGetShaderInfoLog(shader_id, log_data.count, null, log_data.data);
        log_error("Failed to compile shader: %", to_string(log_data.data));
        return false;
    }

    return true;
}

check_for_program_linking_errors :: (program_id: u32) -> bool {
    LOG_BUFFER_SIZE :: 512;
    success: GLint;

    glGetProgramiv(program_id, GL_LINK_STATUS, *success);
    if !success {
        log_data: [LOG_BUFFER_SIZE] u8;
        glGetProgramInfoLog(program_id, log_data.count, null, log_data.data);
        log_error("Failed to link shader program: %", to_string(log_data.data));
        return false;
    }

    return true;
}

#scope_module

shader_reload_from_file :: (shader: *Shader, vertex_path: string, fragment_path: string) -> bool {
    vertex_source := read_entire_file(vertex_path);
    if !vertex_source {
        log_error("Failed to read vertex shader: %", vertex_path);
        return false;
    }
    
    fragment_source := read_entire_file(fragment_path);
    if !fragment_source {
        log_error("Failed to read fragment shader: %", fragment_path);
        return false;
    }

    vertex_id := glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertex_id, 1, *temp_c_string(vertex_source), null);
    glCompileShader(vertex_id);

    if !check_for_shader_compilation_errors(vertex_id) {
        glDeleteShader(vertex_id);
        return false;
    }

    fragment_id := glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragment_id, 1, *temp_c_string(fragment_source), null);
    glCompileShader(fragment_id);

    if !check_for_shader_compilation_errors(fragment_id) {
        glDeleteShader(vertex_id);
        glDeleteShader(fragment_id);
        return false;
    }

    program_id := glCreateProgram();
    glAttachShader(program_id, vertex_id);
    glAttachShader(program_id, fragment_id);
    glLinkProgram(program_id);

    if !check_for_program_linking_errors(program_id) {
        glDeleteShader(vertex_id);
        glDeleteShader(fragment_id);
        glDeleteProgram(program_id);
        return false;
    }

    glDeleteShader(shader.vertex_id);
    glDeleteShader(shader.fragment_id);
    glDeleteProgram(shader.id);

    shader.id = program_id;
    shader.vertex_id = vertex_id;
    shader.fragment_id = fragment_id;

    return true;
}
