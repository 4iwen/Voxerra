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

    while !window_should_close(window) {
        input_poll();

        window_poll_events();

        renderer_begin_frame(.{ 0.0, 0.0, 0.2, 1.0 });

        shader_use(shader);
        
        view := camera_get_view_matrix(camera);
        projection := camera_get_projection_matrix(camera, cast(float32) window.width / window.height);
        model := Matrix4_Identity;
        shader_set_mat4(shader, "projection", projection);
        shader_set_mat4(shader, "view", view);
        shader_set_mat4(shader, "model", model);

        mesh_draw(triangle_mesh);
        
        renderer_end_frame();

        window_swap_buffers(window);
    }
}
