#scope_file

#import "Basic";
#import "String";
#import "Hash_Table";
#import "File";
#import "File_Watcher";

manager: Asset_Manager;

#scope_export

Texture_Asset :: struct {
    texture: *Texture;
    path: string;
    spec: Texture_Spec;
}

Shader_Asset :: struct {
    shader: *Shader;
    vertex_path: string;
    fragment_path: string;
    key: string;
}

Model_Asset :: struct {
    model: *Model;
    path: string;
    options: Model_Load_Options;
}

Asset_Manager :: struct {
    textures: Table(string, Texture_Asset);
    shaders: Table(string, Shader_Asset);
    models: Table(string, Model_Asset);
    
    hot_reload_textures: Table(string, bool);
    hot_reload_shaders: Table(string, bool);
    hot_reload_models: Table(string, bool);
    
    watcher: *File_Watcher(void);

    default_shader: *Shader;
    default_texture: *Texture;
}

asset_manager_set_default_shader :: (shader: *Shader) {
    manager.default_shader = shader;
}

asset_manager_get_default_texture :: () -> *Texture {
    return manager.default_texture;
}

asset_manager_init :: () {
    // initialize tables
    init(*manager.textures);
    init(*manager.shaders);
    init(*manager.models);
    init(*manager.hot_reload_textures);
    init(*manager.hot_reload_shaders);
    init(*manager.hot_reload_models);

    // initialize file watcher
    manager.watcher = New(File_Watcher(void));
    watcher_ok := init(
        manager.watcher,
        file_change_callback,
        null,
        events_to_watch = .MODIFIED,
        merge_window_seconds = 0.5
    );
    if !watcher_ok {
        log_error("Failed to initialize file watcher");
        log_warning("Initialized asset manager (file watcher disabled)");

        deinit(manager.watcher);
        free(manager.watcher);
        manager.watcher = null;
    }

    // initialize default texture
    manager.default_texture = create_white_1x1_texture();

    log("Initialized asset manager");
}

asset_manager_shutdown :: () {
    texture_destroy(manager.default_texture);

    // unload assets
    for asset: manager.textures {
        texture_destroy(asset.texture);
        log("Unloaded texture: %", asset.path);
        free(asset.path);
    }
    for asset: manager.shaders {
        shader_destroy(asset.shader);
        log("Unloaded shader: %, %", asset.vertex_path, asset.fragment_path);
        free(asset.vertex_path);
        free(asset.fragment_path);
        free(asset.key);
    }
    for asset: manager.models {
        model_destroy(asset.model);
        log("Unloaded model: %", asset.path);
        free(asset.path);
    }
    
    // deinit tables
    deinit(*manager.textures);
    deinit(*manager.shaders);
    deinit(*manager.models);
    deinit(*manager.hot_reload_textures);
    deinit(*manager.hot_reload_shaders);
    deinit(*manager.hot_reload_models);
    
    // deinit file watcher
    if manager.watcher {
        deinit(manager.watcher);
        free(manager.watcher);
        manager.watcher = null;
    }

    log("Shutdown asset manager");
}

asset_manager_update :: () {
    if !manager.watcher {
        return;
    }
    process_changes(manager.watcher);
}

asset_manager_load_texture :: (
    path: string,
    spec := DEFAULT_TEXTURE_SPEC,
    hot_reload := false
) -> *Texture {
    absolute_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute path for texture: %", path);

    // check if already present
    found, existing_asset := table_find(*manager.textures, absolute_path);
    if found {
        return existing_asset.texture;
    }

    // load new
    texture := texture_create_from_file(path, spec);
    if !texture {
        texture = manager.default_texture;
    }
    
    asset: Texture_Asset;
    asset.texture = texture;
    asset.path = copy_string(absolute_path);
    asset.spec = spec;
    
    // add to manager
    table_add(*manager.textures, asset.path, asset);

    if hot_reload {
        table_add(
            *manager.hot_reload_textures,
            asset.path,
            true
        );
        if manager.watcher {
            add_directories(manager.watcher, path_strip_filename(asset.path));
        }
    }

    log("Loaded texture: %", asset.path);
    return texture;
}

asset_manager_unload_texture :: (path: string) {
    absolute_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute path for texture: %", path);

    found, asset := table_find(*manager.textures, absolute_path);
    if !found {
        return;
    }
    
    texture_destroy(asset.texture);
    table_remove(*manager.textures, absolute_path);
    table_remove(*manager.hot_reload_textures, absolute_path);
    
    log("Unloaded texture: %", asset.path);
    free(asset.path);
}

asset_manager_load_shader :: (
    vertex_path: string,
    fragment_path: string,
    hot_reload := false
) -> *Shader {
    vertex_absolute, vert_success := get_absolute_path(vertex_path);
    assert(
        vert_success,
        "Failed to get absolute path for vertex shader: %",
        vertex_path
    );
    fragment_absolute, frag_success := get_absolute_path(fragment_path);
    assert(
        frag_success,
        "Failed to get absolute path for fragment shader: %",
        fragment_path
    );
    
    key := tprint("%%", vertex_absolute, fragment_absolute);

    // check if already present
    found, existing_asset := table_find(*manager.shaders, key);
    if found {
        return existing_asset.shader;
    }

    // load new
    shader := shader_create_from_file(vertex_absolute, fragment_absolute);

    asset: Shader_Asset;
    asset.shader = shader;
    asset.vertex_path = copy_string(vertex_absolute);
    asset.fragment_path = copy_string(fragment_absolute);
    asset.key = copy_string(key);

    // add to manager
    table_add(*manager.shaders, asset.key, asset);

    if hot_reload {
        table_add(*manager.hot_reload_shaders, asset.key, true);
        if manager.watcher {
            add_directories(
                manager.watcher,
                path_strip_filename(vertex_absolute)
            );
            add_directories(
                manager.watcher,
                path_strip_filename(fragment_absolute)
            );
        }
    }

    log("Loaded shader: %, %", vertex_absolute, fragment_absolute);
    return shader;
}

asset_manager_unload_shader :: (vertex_path: string, fragment_path: string) {
    vertex_absolute, vert_success := get_absolute_path(vertex_path);
    assert(
        vert_success,
        "Failed to get absolute path for vertex shader: %",
        vertex_path
    );
    fragment_absolute, frag_success := get_absolute_path(fragment_path);
    assert(
        frag_success,
        "Failed to get absolute path for fragment shader: %",
        fragment_path
    );

    key := tprint("%%", vertex_absolute, fragment_absolute);
    
    found, asset := table_find(*manager.shaders, key);
    if !found {
        return;
    }
    
    shader_destroy(asset.shader);
    free(asset.vertex_path);
    free(asset.fragment_path);
    table_remove(*manager.shaders, key);
    table_remove(*manager.hot_reload_shaders, key);
    free(asset.key);

    log("Unloaded shader: %, %", vertex_absolute, fragment_absolute);
}

asset_manager_load_model :: (
    path: string,
    options: Model_Load_Options = DEFAULT_MODEL_LOAD_OPTIONS,
    hot_reload := false
) -> *Model {
    absolute_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute path for model: %", path);

    found, existing_asset := table_find(*manager.models, absolute_path);
    if found {
        return existing_asset.model;
    }

    model := model_create_from_file(path, options);
    if !model {
        log_error("Failed to load mesh from file: %", path);
        return null;
    }
    
    if manager.default_shader {
        for material: model.materials {
            if !material.shader {
                material.shader = manager.default_shader;
            }
        }
    }

    asset: Model_Asset;
    asset.model = model;
    asset.path = copy_string(absolute_path);
    asset.options = options;

    table_add(*manager.models, asset.path, asset);

    if hot_reload {
        table_add(*manager.hot_reload_models, asset.path, true);
        if manager.watcher {
            add_directories(manager.watcher, path_strip_filename(absolute_path));
        }
    }

    log("Loaded model: %", absolute_path);
    return model;
}

asset_manager_unload_model :: (path: string) {
    absolute_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute path for model: %", path);

    found, asset := table_find(*manager.models, absolute_path);
    if !found {
        return;
    }

    model_destroy(asset.model);
    table_remove(*manager.models, absolute_path);
    table_remove(*manager.hot_reload_models, absolute_path);

    log("Unloaded model: %", asset.path);
    free(asset.path);
}

#scope_file

file_change_callback :: (
    watcher: *File_Watcher(void),
    change: *File_Change,
    user_data: *void
) {
    path := change.full_path;
    
    for * asset, key: manager.textures {
        if asset.path != path {
            continue;
        }
        
        found, enabled := table_find(*manager.hot_reload_textures, path);
        if !found || !enabled {
            continue;
        }

        if texture_reload_from_file(asset.texture, path, asset.spec) {
            log("Hot reloaded texture: %", path);
        } else {
            log_error("Hot reload failed: %", path);
        }
        return;
    }
    
    for * asset, key: manager.shaders {
        found, enabled := table_find(*manager.hot_reload_shaders, key);
        if !found || !enabled {
            continue;
        }
        
        if asset.vertex_path != path && asset.fragment_path != path {
            continue;
        }
        
        if shader_reload_from_file(
            asset.shader,
            asset.vertex_path,
            asset.fragment_path
        ) {
            log(
                "Hot reloaded shader: %, %",
                asset.vertex_path,
                asset.fragment_path
            );
        } else {
            log_error(
                "Hot reload failed: %, %",
                asset.vertex_path,
                asset.fragment_path
            );
        }
        return;
    }
    
    for * asset, key: manager.models {
        if asset.path != path {
            continue;
        }

        found, enabled := table_find(*manager.hot_reload_models, path);
        if !found || !enabled {
            continue;
        }

        if model_reload_from_file(asset.model, path, asset.options) {
            log("Hot reloaded model: %", path);
        } else {
            log_error("Hot reload failed: %", path);
        }
        return;
    }
}

create_white_1x1_texture :: () -> *Texture {
    pixel: [4] u8 = .[255, 255, 255, 255];
    texture := texture_create_from_data(
        1,
        1,
        pixel.data,
        .{
            min_filter = .LINEAR,
            mag_filter = .NEAREST,
            wrap_s = .REPEAT,
            wrap_t = .REPEAT,
            generate_mipmaps = false,
        }
    );

    return texture;
}

create_checker_texture :: () -> *Texture {
    width :: 8;
    height :: 8;

    data := cast(*u8) alloc(width * height * 4);

    for y: 0..height-1 {
        for x: 0..width-1 {
            index := (y * width + x) * 4;
            
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

    texture := texture_create_from_data(
        width,
        height,
        data,
        .{
            min_filter = .LINEAR_MIPMAP_LINEAR,
            mag_filter = .NEAREST,
            wrap_s = .REPEAT,
            wrap_t = .REPEAT,
            generate_mipmaps = true,
        }
    );
    free(data);
    return texture;
}
