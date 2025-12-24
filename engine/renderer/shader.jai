#scope_file

#import "Basic";
#import "Math";
#import "GL";

#scope_export

Shader :: struct {
    id: u32;
    vertex_id: u32;
    fragment_id: u32;
}

shader_create :: (vertex_source: string, fragment_source: string) -> Shader {
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

    return Shader.{
        id = program_id,
        vertex_id = vertex_id,
        fragment_id = fragment_id
    };
}

shader_destroy :: (shader: Shader) {
    glDeleteShader(shader.vertex_id);
    glDeleteShader(shader.fragment_id);
    glDeleteProgram(shader.id);
}

shader_use :: (shader: Shader) {
    glUseProgram(shader.id);
}

shader_set_mat4 :: (shader: Shader, name: string, matrix: Matrix4) {
    location := glGetUniformLocation(shader.id, temp_c_string(name));
    glUniformMatrix4fv(location, 1, GL_TRUE, *matrix.coef[0][0]);
}

#scope_file

check_for_shader_compilation_errors :: (shader_id: u32) {
    LOG_BUFFER_SIZE :: 512;
    success: GLint;

    glGetShaderiv(shader_id, GL_COMPILE_STATUS, *success);
    if !success {
        log_data: [LOG_BUFFER_SIZE] u8;
        glGetShaderInfoLog(shader_id, log_data.count, null, log_data.data);
        log("%", to_string(log_data.data), flags = .ERROR);
    }
}

check_for_program_linking_errors :: (program_id: u32) {
    LOG_BUFFER_SIZE :: 512;
    success: GLint;

    glGetProgramiv(program_id, GL_LINK_STATUS, *success);
    if !success {
        log_data: [LOG_BUFFER_SIZE] u8;
        glGetProgramInfoLog(program_id, log_data.count, null, log_data.data);
        log("%", to_string(log_data.data), flags = .ERROR);
    }
}
