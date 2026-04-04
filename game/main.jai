#import "Basic"()(MEMORY_DEBUGGER = MEMORY_DEBUGGER_ENABLED);
#load "../engine/module.jai";
#load "camera_controller.jai";
#load "skybox.jai";

main :: () {
    if !engine_init() {
        log_error("Failed to init engine");
        return;
    }
    defer engine_shutdown();

    window := window_init(1280, 800, "Voxerra");
    if !window {
        log_error("Failed to init window");
        return;
    }
    window_set_vsync(true);

    // load shader from files
    vertex_path := "assets/shaders/blinn_phong.vert";
    fragment_path := "assets/shaders/blinn_phong.frag";
    blinn_phong_shader := asset_manager_load_shader(vertex_path, fragment_path, true);
    asset_manager_set_default_shader(blinn_phong_shader);

    // unlit shader 
    unlit_vertex := "assets/shaders/unlit.vert";
    unlit_fragment := "assets/shaders/unlit.frag";
    unlit_shader := asset_manager_load_shader(unlit_vertex, unlit_fragment, true);

    skybox := skybox_init();
    defer skybox_shutdown(skybox);

    sun_direction := Vector3.{-0.2, -1.0, -0.3}; 
    sun_color := Vector3.{1.0, 0.95, 0.9};
    sun_intensity := 2.0;

    model := asset_manager_load_model(
        "assets/models/utah_teapot.obj"
        // "assets/models/glTF-Sample-Assets/Models/Sponza/glTF/Sponza.gltf"
    );
    
    controller := camera_controller_create(.{0.0, 1.5, 0.0});

    queue := render_queue_create();
    defer render_queue_destroy(queue);

    engine_state.current_scene = New(Scene);
    scene := engine_state.current_scene;
    engine_state.current_scene.root = New(Node);
    engine_state.current_scene.root.name = "Root";
    engine_state.current_scene.root.active = true;

    teapot_node := make_node("Teapot", scene.root);

    teapot_node.local.position = .{0, 0, -10};

    for model.submeshes {
        sub_node := make_node("teapot_mesh", teapot_node);

        mesh_comp := node_add_component(sub_node, Static_Mesh_Component);
        mesh_comp.mesh = it.mesh;
        mesh_comp.material = it.material;
    }

    sun_node := make_node("Sun", scene.root);
    sun_light_comp := node_add_component(sun_node, Light_Component);
    sun_light_comp.light.type = .Directional;
    sun_light_comp.light.color = sun_color;
    sun_light_comp.light.intensity = sun_intensity;
    sun_node.local.rotation = quaternion_from_euler_xyz(.{-PI / 2 - 0.2, 0, 0});

    point_node := make_node("Point", scene.root);
    point_node.local.position = .{3, 3, -7.5};
    point_light_comp := node_add_component(point_node, Light_Component);
    point_light_comp.light.type = .Point;
    point_light_comp.light.color = .{1, 0, 0};
    point_light_comp.light.intensity = 2;
    point_light_comp.light.range = 20;

    spot_node := make_node("Spot", scene.root);
    spot_node.local.position = .{1, 1, -7};
    spot_node.local.rotation = quaternion_from_euler_xyz(.{0, 0.4, 0});
    spot_light_comp := node_add_component(spot_node, Light_Component);
    spot_light_comp.light.type = .Spot;
    spot_light_comp.light.color = .{0, 0, 1};
    spot_light_comp.light.direction = .{0, 0, -1};
    spot_light_comp.light.intensity = 2;
    spot_light_comp.light.range = 20;
    spot_light_comp.light.inner_cos = 0.9;
    spot_light_comp.light.outer_cos = 0.7;

    engine_state.main_framebuffer = framebuffer_create(
        window.framebuffer_width,
        window.framebuffer_height
    );
    defer framebuffer_destroy(engine_state.main_framebuffer);

    while !window_should_close(window) {
        delta_time := engine_begin_frame(.{0.114, 0.114, 0.114, 1});
        #if MEMORY_DEBUGGER_ENABLED then memory_visualizer_per_frame_update();
        camera_controller_update(*controller, window, delta_time);
        
        scene_update_transforms(scene);

        framebuffer_bind(engine_state.main_framebuffer);

        // called for the second time!, first time in renderer_begin_frame
        renderer_clear(.{0.114, 0.114, 0.114, 1.0}); 

        render_queue_submit(queue, scene);

        view := camera_get_view_matrix(controller.camera);
        
        projection := camera_get_projection_matrix(
            controller.camera,
            engine_state.main_framebuffer.aspect
        );
        render_queue_flush(
            queue,
            *controller.camera
        );

        skybox_draw(
            skybox,
            view,
            projection,
            sun_direction,
            sun_color
        );

        framebuffer_unbind();
        engine_end_frame();
    }
}

make_node :: (name: string, parent: *Node) -> *Node {
    n := New(Node);
    n.name = copy_string(name);
    n.active = true;
    n.parent = parent;
    array_add(*parent.children, n);

    return n;
}

generate_worley_texture :: (
    width: s32,
    height: s32,
    zoom: float = 32.0,
    seed: u64 = 157
) -> *Texture {
    pixel_count := width * height * 4;
    data := cast(*u8) alloc(pixel_count);
    
    for y: 0..height - 1 {
        for x: 0..width - 1 {
            spec := Worley_Noise_Spec.{
                seed = seed,
                zoom = zoom
            };
            d := worley_noise_2d(cast(float64) x, cast(float64) y, spec);
            
            d = clamp(d * 1.5, 0.0, 1.0);
            v := cast(u8)(d * 255.0);
            
            index := (y * width + x) * 4;
            data[index + 0] = v;
            data[index + 1] = v;
            data[index + 2] = v;
            data[index + 3] = 255;
        }
    }
    
    texture := texture_create_from_data(width, height, data);
    return texture;
}
