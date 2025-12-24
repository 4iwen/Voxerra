#import "Basic";
#import "Math";
#import "engine";

main :: () {
    platform_init();
    defer platform_shutdown();

    window := window_create(960, 600, "Voxerra");
    defer window_destroy(window);

    window_set_vsync(true);

    renderer_init();
    defer renderer_shutdown();

    VERTEX_SRC :: #string DONE
    #version 330 core

    layout (location = 0) in vec3 pos;

    uniform mat4 projection;
    uniform mat4 view;
    uniform mat4 model;

    void main() {
        gl_Position = projection * view * model * vec4(pos, 1.0);
    }
    DONE

    FRAGMENT_SRC :: #string DONE
    #version 330 core

    out vec4 color;

    void main() {
        color = vec4(1.0f, 0.5f, 0.2f, 1.0f);
    }
    DONE

    vertices: [9] float = .[
        -0.5, -0.5, 0.0,
        0.5, -0.5, 0.0,
        0.0, 0.5, 0.0
    ];  

    indices: [3] u32 = .[
        0, 1, 2
    ];

    shader := shader_create(VERTEX_SRC, FRAGMENT_SRC);
    defer shader_destroy(shader);
    
    triangle_mesh := mesh_create(vertices, indices);
    defer mesh_destroy(triangle_mesh);
    
    camera := camera_create(.{0.0, 0.0, 3.0});
    movement_speed: float = 2.0;
    sensitivity: float = 0.1;
    camera_active := false;

    last_time := time_get();

    while !window_should_close(window) {
        current_time := time_get();
        delta_time := current_time - last_time;
        last_time = current_time;

        input_poll();
        window_poll_events();

        {
            if input_mouse_pressed(.RIGHT) {
                window_set_cursor_mode(window, .DISABLED);
                camera_active = true;
            }

            if input_key_pressed(.ESCAPE) {
                window_set_cursor_mode(window, .NORMAL);
                camera_active = false;
            }

            if camera_active {
                cam_process_keyboard(*camera, delta_time);
                cam_process_mouse(*camera);
            }
        }

        renderer_begin_frame(.{ 0.0, 0.0, 0.2, 1.0 });

        {
            shader_use(shader);
            view := camera_get_view_matrix(camera);
            projection := camera_get_projection_matrix(camera, cast(float32) window.width / window.height);
            model := Matrix4_Identity;
            shader_set_mat4(shader, "projection", projection);
            shader_set_mat4(shader, "view", view);
            shader_set_mat4(shader, "model", model);
            mesh_draw(triangle_mesh);
        }

        renderer_end_frame();
        window_swap_buffers(window);
    }
}

cam_process_keyboard :: (camera: *Camera, delta_time: float64) {
    velocity := 2 * delta_time;
    
    if input_key_down(.W) {
        camera.position = camera.position + camera.front * velocity;
    }
    if input_key_down(.S) {
        camera.position = camera.position - camera.front * velocity;
    }
    if input_key_down(.A) {
        camera.position = camera.position - camera.right * velocity;
    }
    if input_key_down(.D) {
        camera.position = camera.position + camera.right * velocity;
    }
    if input_key_down(.SPACE) || input_key_down(.E) {
        camera.position = camera.position + camera.world_up * velocity;
    }
    if input_key_down(.LEFT_SHIFT) || input_key_down(.Q) {
        camera.position = camera.position - camera.world_up * velocity;
    }
}

cam_process_mouse :: (camera: *Camera) {
    dx, dy := input_mouse_delta();

    camera.yaw   += cast(float32) dx * 0.2;
    camera.pitch -= cast(float32) dy * 0.2;

    if camera.pitch > 89.0  then camera.pitch = 89.0;
    if camera.pitch < -89.0 then camera.pitch = -89.0;

    camera_update_vectors(camera);
}
