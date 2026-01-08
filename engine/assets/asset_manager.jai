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
}

Font_Asset :: struct {
    font: *Font;
    path: string;
    pixel_size: u32;
}

Mesh_Asset :: struct {
    mesh: *Mesh;
    path: string;
    options: Mesh_Load_Options;
}

Asset_Manager :: struct {
    textures: Table(string, Texture_Asset);
    shaders: Table(string, Shader_Asset);
    fonts: Table(string, Font_Asset);
    meshes: Table(string, Mesh_Asset);
    
    hot_reload_textures: Table(string, bool);
    hot_reload_shaders: Table(string, bool);
    hot_reload_fonts: Table(string, bool);
    hot_reload_meshes: Table(string, bool);
    
    watcher: *File_Watcher(void);
}

asset_manager_init :: () {
    // initialize tables
    init(*manager.textures);
    init(*manager.shaders);
    init(*manager.fonts);
    init(*manager.meshes);
    init(*manager.hot_reload_textures);
    init(*manager.hot_reload_shaders);
    init(*manager.hot_reload_fonts);
    init(*manager.hot_reload_meshes);

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
        log("Unloading texture:\n%", asset.path);
        texture_destroy(asset.texture);
    }
    for asset: manager.shaders {
        log("Unloading shader:\n%\n%", asset.vertex_path, asset.fragment_path);
        shader_destroy(asset.shader);
    }
    for asset: manager.fonts {
        log("Unloading font:\n%", asset.path);
        font_destroy(asset.font);
    }
    for asset: manager.meshes {
        log("Unloading mesh:\n%", asset.path);
        mesh_destroy(asset.mesh);
    }
    
    // deinit tables
    deinit(*manager.textures);
    deinit(*manager.shaders);
    deinit(*manager.fonts);
    deinit(*manager.meshes);
    deinit(*manager.hot_reload_textures);
    deinit(*manager.hot_reload_shaders);
    deinit(*manager.hot_reload_fonts);
    deinit(*manager.hot_reload_meshes);
    
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
    absoulte_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute path for texture: %", path);

    // check if already present
    found, existing_asset := table_find(*manager.textures, absoulte_path);
    if found {
        return existing_asset.texture;
    }

    // load new
    texture := texture_create_from_file(path, spec);
    
    asset: Texture_Asset;
    asset.texture = texture;
    asset.path = copy_string(absoulte_path);
    asset.spec = spec;
    
    // add to manager
    table_add(*manager.textures, copy_string(absoulte_path), asset);

    if hot_reload {
        table_add(
            *manager.hot_reload_textures,
            copy_string(absoulte_path),
            true
        );
        if manager.watcher {
            add_directories(manager.watcher, absoulte_path);
        }
    }

    log("Loaded texture:\n%", absoulte_path);
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
    
    log("Unloaded texture:\n%", path);
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

    // add to manager
    table_add(*manager.shaders, copy_string(key), asset);

    if hot_reload {
        table_add(*manager.hot_reload_shaders, copy_string(key), true);
        if manager.watcher {
            add_directories(manager.watcher, vertex_absolute);
            add_directories(manager.watcher, fragment_absolute);
        }
    }

    log("Loaded shader:\n%\n%", vertex_absolute, fragment_absolute);
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
    table_remove(*manager.shaders, key);
    table_remove(*manager.hot_reload_shaders, key);
    
    log("Unloaded shader:\n%", key);
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

    // add to manager
    table_add(*manager.fonts, copy_string(key), asset);

    if hot_reload {
        table_add(*manager.hot_reload_fonts, copy_string(key), true);
        if manager.watcher {
            add_directories(manager.watcher, absolute_path);
        }
    }

    log("Loaded font:\n%", absolute_path);
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
    table_remove(*manager.fonts, key);
    table_remove(*manager.hot_reload_fonts, key);
    
    log("Unloaded font:\n%", path);
}

asset_manager_load_mesh :: (
    path: string,
    options: Mesh_Load_Options = DEFAULT_MESH_LOAD_OPTIONS,
    hot_reload := false
) -> *Mesh {
    absolute_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute path for mesh: %", path);

    found, existing_asset := table_find(*manager.meshes, absolute_path);
    if found {
        return existing_asset.mesh;
    }

    mesh := mesh_create_from_file(path, options);

    asset: Mesh_Asset;
    asset.mesh = mesh;
    asset.path = copy_string(absolute_path);
    asset.options = options;

    table_add(*manager.meshes, copy_string(absolute_path), asset);

    if hot_reload {
        table_add(*manager.hot_reload_meshes, copy_string(absolute_path), true);
        if manager.watcher {
            add_directories(manager.watcher, absolute_path);
        }
    }

    log("Loaded mesh:\n%", absolute_path);
    return mesh;
}

asset_manager_unload_mesh :: (path: string) {
    absolute_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute path for mesh: %", path);

    found, asset := table_find(*manager.meshes, absolute_path);
    if !found {
        return;
    }

    mesh_destroy(asset.mesh);
    table_remove(*manager.meshes, absolute_path);
    table_remove(*manager.hot_reload_meshes, absolute_path);

    log("Unloaded mesh:\n%", path);
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
            log("Hot reloaded texture:\n%", path);
        } else {
            log_error("Hot reload failed:\n%", path);
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
                "Hot reloaded shader:\n%\n%",
                asset.vertex_path,
                asset.fragment_path
            );
        } else {
            log_error(
                "Hot reload failed:\n%\n%",
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
            log("Hot reloaded font:\n%", path);
        } else {
            log_error("Hot reload failed:\n%", path);
        }
        return;
    }

    for * asset, key: manager.meshes {
        if asset.path != path {
            continue;
        }

        found, enabled := table_find(*manager.hot_reload_meshes, path);
        if !found || !enabled {
            continue;
        }

        if mesh_reload_from_file(asset.mesh, path, asset.options) {
            log("Hot reloaded mesh:\n%", path);
        } else {
            log_error("Hot reload failed:\n%", path);
        }
        return;
    }
}
