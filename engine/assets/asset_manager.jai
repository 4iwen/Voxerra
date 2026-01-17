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

Font_Asset :: struct {
    font: *Font;
    path: string;
    pixel_size: u32;
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
    fonts: Table(string, Font_Asset);
    models: Table(string, Model_Asset);
    
    hot_reload_textures: Table(string, bool);
    hot_reload_shaders: Table(string, bool);
    hot_reload_fonts: Table(string, bool);
    hot_reload_models: Table(string, bool);
    
    watcher: *File_Watcher(void);
}

asset_manager_init :: () {
    // initialize tables
    init(*manager.textures);
    init(*manager.shaders);
    init(*manager.fonts);
    init(*manager.models);
    init(*manager.hot_reload_textures);
    init(*manager.hot_reload_shaders);
    init(*manager.hot_reload_fonts);
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
        return;
    }

    log("Initialized asset manager");
}

asset_manager_shutdown :: () {
    // unload assets
    for asset: manager.textures {
        asset_manager_unload_texture(asset.path);
    }
    for asset: manager.shaders {
        asset_manager_unload_shader(asset.vertex_path, asset.fragment_path);
    }
    for asset: manager.fonts {
        asset_manager_unload_font(asset.path, asset.pixel_size);
    }
    for asset: manager.models {
        asset_manager_unload_model(asset.path);
    }
    
    // deinit tables
    deinit(*manager.textures);
    deinit(*manager.shaders);
    deinit(*manager.fonts);
    deinit(*manager.models);
    deinit(*manager.hot_reload_textures);
    deinit(*manager.hot_reload_shaders);
    deinit(*manager.hot_reload_fonts);
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

    log("Unloaded shader: %", key);
}

asset_manager_load_font :: (
    path: string,
    pixel_size: u32,
    hot_reload := false
) -> *Font {
    absolute_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute path for font: %", path);
    
    key := tprint("%%", absolute_path, pixel_size);

    // check if already present
    found, existing_asset := table_find(*manager.fonts, key);
    if found {
        return existing_asset.font;
    }

    // load new
    font := font_create_from_file(path, pixel_size);
    if !font {
        log_error("Failed to load font: %", path);
        return null;
    }

    asset: Font_Asset;
    asset.font = font;
    asset.path = copy_string(absolute_path);
    asset.pixel_size = pixel_size;
    asset.key = copy_string(key);

    // add to manager
    table_add(*manager.fonts, asset.key, asset);

    if hot_reload {
        table_add(*manager.hot_reload_fonts, asset.key, true);
        if manager.watcher {
            add_directories(manager.watcher, path_strip_filename(absolute_path));
        }
    }

    log("Loaded font: %", absolute_path);
    return font;
}

asset_manager_unload_font :: (path: string, pixel_size: u32) {
    absolute_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute path for font: %", path);

    key := tprint("%%", absolute_path, pixel_size);
    
    found, asset := table_find(*manager.fonts, key);
    if !found {
        return;
    }
    
    font_destroy(asset.font);
    free(asset.path);
    table_remove(*manager.fonts, key);
    table_remove(*manager.hot_reload_fonts, key);
    free(asset.key);
    
    log("Unloaded font: %", path);
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
    free(asset.path);

    log("Unloaded model: %", path);
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
    
    for * asset, key: manager.fonts {
        if asset.path != path {
            continue;
        }
        
        found, enabled := table_find(*manager.hot_reload_fonts, key);
        if !found || !enabled {
            continue;
        }
        
        if font_reload_from_file(asset.font, path, asset.pixel_size) {
            log("Hot reloaded font: %", path);
        } else {
            log_error("Hot reload failed: %", path);
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
