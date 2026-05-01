#scope_file

#import "Basic";
#import "String";
#import "Hash_Table";
#import "File";
#import "File_Watcher";
#import "File_Utilities";

using Toml :: #import "toml-jai";

manager: Asset_Manager;

#scope_export

Asset_Type :: enum {
    UNKNOWN;
    SCENE;
    MODEL;
    TEXTURE;
    SHADER;
    CUBEMAP;
}

Asset_Metadata :: struct {
    guid: string;
    path: string;
    absolute_path: string;
    meta_path: string;
    type: Asset_Type;
}

Asset_Metadata_File :: struct {
    guid: string;
    type: string;
    path: string;
}

Asset_Ref :: struct {
    type: Asset_Type;
    guid: string;
    path: string;
    key: string;
    generation: u32;
    resource: *void;
}

Asset_Reference_Entry :: struct {
    key: string;
    guid: string;
    path: string;
    type: Asset_Type;
    ref_count: s32;
    generation: u32;
}

Texture_Asset :: struct {
    texture: *Texture;
    path: string;
    key: string;
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

    metadata_by_path: Table(string, Asset_Metadata);
    references: Table(string, Asset_Reference_Entry);
    
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

asset_manager_get_textures :: () -> *Table(string, Texture_Asset) {
    return *manager.textures;
}

asset_manager_get_shaders :: () -> *Table(string, Shader_Asset) {
    return *manager.shaders;
}

asset_manager_get_models :: () -> *Table(string, Model_Asset) {
    return *manager.models;
}

asset_manager_get_metadata :: () -> *Table(string, Asset_Metadata) {
    return *manager.metadata_by_path;
}

asset_manager_init :: () {
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

    for entry: manager.references {
        free(entry.key);
        free(entry.guid);
        free(entry.path);
    }
    for metadata: manager.metadata_by_path {
        free(metadata.guid);
        free(metadata.path);
        free(metadata.absolute_path);
        free(metadata.meta_path);
    }

    // unload assets
    for asset: manager.textures {
        texture_destroy(asset.texture);
        log("Unloaded texture: %", asset.path);
        free(asset.path);
        free(asset.key);
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
    deinit(*manager.metadata_by_path);
    deinit(*manager.references);
    
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

asset_ref_acquire_model :: (
    ref: *Asset_Ref,
    path: string,
    guid: string = "",
    options: Model_Load_Options = DEFAULT_MODEL_LOAD_OPTIONS,
    hot_reload := false
) -> *Model {
    if !ref || !path then return null;

    asset_ref_release(ref);

    metadata := asset_manager_ensure_metadata(path, .MODEL, guid);
    model := asset_manager_load_model(metadata.path, options, hot_reload);
    if !model then return null;

    asset_ref_set(ref, metadata, cast(*void) model);
    asset_manager_reference_increment(ref);
    return model;
}

asset_ref_acquire_texture :: (
    ref: *Asset_Ref,
    path: string,
    guid: string = "",
    spec := DEFAULT_TEXTURE_SPEC,
    hot_reload := false
) -> *Texture {
    if !ref || !path then return null;

    asset_ref_release(ref);

    metadata := asset_manager_ensure_metadata(path, .TEXTURE, guid);
    texture := asset_manager_load_texture(metadata.path, spec, hot_reload);
    if !texture then return null;

    asset_ref_set(ref, metadata, cast(*void) texture);
    asset_manager_reference_increment(ref);
    return texture;
}

asset_ref_acquire_scene :: (
    ref: *Asset_Ref,
    path: string,
    guid: string = ""
) -> bool {
    if !ref || !path then return false;

    asset_ref_release(ref);

    metadata := asset_manager_ensure_metadata(path, .SCENE, guid);
    asset_ref_set(ref, metadata, null);
    asset_manager_reference_increment(ref);
    return true;
}

asset_ref_release :: (ref: *Asset_Ref) {
    if !ref then return;

    if ref.key {
        found, entry := table_find(*manager.references, ref.key);
        if found {
            entry.ref_count -= 1;
            if entry.ref_count <= 0 {
                table_remove(*manager.references, ref.key);
                free(entry.key);
                free(entry.guid);
                free(entry.path);
            } else {
                table_set(*manager.references, entry.key, entry);
            }
        }
    }

    free(ref.guid);
    free(ref.path);
    free(ref.key);
    ref.* = .{};
}

asset_ref_clone :: (source: *Asset_Ref, destination: *Asset_Ref) {
    if !source || !destination then return;

    asset_ref_release(destination);
    if !source.key then return;

    destination.type = source.type;
    destination.guid = copy_string(source.guid);
    destination.path = copy_string(source.path);
    destination.key = copy_string(source.key);
    destination.generation = source.generation;
    destination.resource = source.resource;
    asset_manager_reference_increment(destination);
}

asset_ref_get_model :: (ref: *Asset_Ref) -> *Model {
    if !ref then return null;
    if ref.resource then return cast(*Model) ref.resource;
    if ref.path then return asset_ref_acquire_model(ref, ref.path, ref.guid);
    return null;
}

asset_ref_get_texture :: (ref: *Asset_Ref, spec := DEFAULT_TEXTURE_SPEC) -> *Texture {
    if !ref then return null;
    if ref.resource then return cast(*Texture) ref.resource;
    if ref.path then return asset_ref_acquire_texture(ref, ref.path, ref.guid, spec);
    return null;
}

asset_manager_ensure_metadata :: (
    path: string,
    type: Asset_Type,
    guid_hint: string = ""
) -> Asset_Metadata {
    absolute_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute asset path: %", path);

    found, metadata := table_find(*manager.metadata_by_path, absolute_path);
    if found {
        return metadata;
    }

    meta_path := asset_manager_meta_path(path);
    loaded, loaded_metadata, rewrite_metadata := asset_manager_load_metadata_file(meta_path, absolute_path, path, type);
    if loaded {
        if rewrite_metadata {
            asset_manager_write_metadata_file(loaded_metadata);
        }
        table_add(*manager.metadata_by_path, loaded_metadata.absolute_path, loaded_metadata);
        return loaded_metadata;
    }

    metadata = .{};
    if guid_hint && !asset_manager_guid_is_legacy(guid_hint) {
        metadata.guid = copy_string(guid_hint);
    } else {
        metadata.guid = asset_manager_generate_guid(absolute_path, type);
    }
    metadata.path = copy_string(path);
    metadata.absolute_path = copy_string(absolute_path);
    metadata.meta_path = copy_string(meta_path);
    metadata.type = type;

    asset_manager_write_metadata_file(metadata);
    table_add(*manager.metadata_by_path, metadata.absolute_path, metadata);

    return metadata;
}

asset_manager_load_texture :: (
    path: string,
    spec := DEFAULT_TEXTURE_SPEC,
    hot_reload := false
) -> *Texture {
    absolute_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute path for texture: %", path);

    key := asset_manager_texture_key(absolute_path, spec);

    // check if already present
    found, existing_asset := table_find(*manager.textures, key);
    if found {
        return existing_asset.texture;
    }

    // load new
    texture := texture_create_from_file(absolute_path, spec);
    if !texture {   
        return manager.default_texture;
    }
    
    asset: Texture_Asset;
    asset.texture = texture;
    asset.path = copy_string(absolute_path);
    asset.key = copy_string(key);
    asset.spec = spec;
    
    // add to manager
    table_add(*manager.textures, asset.key, asset);

    if hot_reload {
        table_add(
            *manager.hot_reload_textures,
            asset.key,
            true
        );
        if manager.watcher {
            add_directories(manager.watcher, path_strip_filename(asset.path));
        }
    }

    log("Loaded texture: %", asset.path);
    return texture;
}

asset_manager_unload_texture :: (
    path: string,
    spec := DEFAULT_TEXTURE_SPEC
) {
    absolute_path, success := get_absolute_path(path);
    assert(success, "Failed to get absolute path for texture: %", path);

    key := asset_manager_texture_key(absolute_path, spec);
    found, asset := table_find(*manager.textures, key);
    if !found {
        return;
    }
    
    texture_destroy(asset.texture);
    table_remove(*manager.textures, key);
    table_remove(*manager.hot_reload_textures, key);
    
    log("Unloaded texture: %", asset.path);
    free(asset.path);
    free(asset.key);
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
    
    key := tprint("%|%", vertex_absolute, fragment_absolute);

    // check if already present
    found, existing_asset := table_find(*manager.shaders, key);
    if found {
        return existing_asset.shader;
    }

    // load new
    shader := shader_create_from_file(vertex_absolute, fragment_absolute);
    if !shader {
        log_error("Failed to load shader: %, %", vertex_absolute, fragment_absolute);
        return null;
    }

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

    key := tprint("%|%", vertex_absolute, fragment_absolute);
    
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

    model := model_create_from_file(absolute_path, options);
    if !model {
        log_error("Failed to load mesh from file: %", absolute_path);
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

asset_manager_texture_key :: (absolute_path: string, spec: Texture_Spec) -> string {
    return tprint(
        "%|%|%|%|%|%|%",
        absolute_path,
        cast(s32) spec.min_filter,
        cast(s32) spec.mag_filter,
        cast(s32) spec.wrap_s,
        cast(s32) spec.wrap_t,
        spec.generate_mipmaps,
        spec.srgb
    );
}

asset_ref_set :: (
    ref: *Asset_Ref,
    metadata: Asset_Metadata,
    resource: *void
) {
    ref.type = metadata.type;
    ref.guid = copy_string(metadata.guid);
    ref.path = copy_string(metadata.path);
    ref.key = asset_manager_reference_key(metadata.type, metadata.guid, metadata.absolute_path);
    ref.generation = 1;
    ref.resource = resource;
}

asset_manager_reference_increment :: (ref: *Asset_Ref) {
    if !ref || !ref.key then return;

    found, entry := table_find(*manager.references, ref.key);
    if found {
        entry.ref_count += 1;
        table_set(*manager.references, entry.key, entry);
        ref.generation = entry.generation;
        return;
    }

    entry = .{};
    entry.key = copy_string(ref.key);
    entry.guid = copy_string(ref.guid);
    entry.path = copy_string(ref.path);
    entry.type = ref.type;
    entry.ref_count = 1;
    entry.generation = 1;
    table_add(*manager.references, entry.key, entry);
    ref.generation = entry.generation;
}

asset_manager_reference_key :: (
    type: Asset_Type,
    guid: string,
    absolute_path: string
) -> string {
    if guid {
        return copy_string(tprint("%|%", asset_type_to_string(type), guid));
    }

    return copy_string(tprint("%|%", asset_type_to_string(type), absolute_path));
}

asset_manager_meta_path :: (path: string) -> string {
    return tprint("%.meta", path);
}

asset_manager_load_metadata_file :: (
    meta_path: string,
    absolute_path: string,
    fallback_path: string,
    fallback_type: Asset_Type
) -> bool, Asset_Metadata, bool {
    if !file_exists(meta_path) {
        return false, .{}, false;
    }

    contents, read_ok := read_entire_file(meta_path);
    if !read_ok {
        log_warning("Failed to read asset metadata: %", meta_path);
        return false, .{}, false;
    }
    defer free(contents);

    parse_ok, file := Toml.string_to_type(contents, Asset_Metadata_File);
    if !parse_ok {
        log_warning("Failed to parse asset metadata: %", meta_path);
        return false, .{}, false;
    }
    defer {
        free(file.guid);
        free(file.type);
        free(file.path);
    }

    metadata: Asset_Metadata;
    rewrite_metadata := false;
    if file.guid && !asset_manager_guid_is_legacy(file.guid) {
        metadata.guid = copy_string(file.guid);
    } else {
        metadata.guid = asset_manager_generate_guid(absolute_path, fallback_type);
        rewrite_metadata = true;
    }
    if !metadata.guid {
        metadata.guid = asset_manager_generate_guid(absolute_path, fallback_type);
        rewrite_metadata = true;
    }

    parsed_type := asset_type_from_string(file.type);
    metadata.type = ifx parsed_type != .UNKNOWN then parsed_type else fallback_type;
    metadata.path = copy_string(ifx file.path then file.path else fallback_path);
    metadata.absolute_path = copy_string(absolute_path);
    metadata.meta_path = copy_string(meta_path);
    return true, metadata, rewrite_metadata;
}

asset_manager_write_metadata_file :: (metadata: Asset_Metadata) -> bool {
    if !metadata.meta_path then return false;

    builder: String_Builder;
    init_string_builder(*builder);
    print_to_builder(*builder, "guid = \"%\"\n", metadata.guid);
    print_to_builder(*builder, "type = \"%\"\n", asset_type_to_string(metadata.type));
    print_to_builder(*builder, "path = \"%\"\n", metadata.path);

    contents := builder_to_string(*builder);
    defer free(contents);

    ok := write_entire_file(metadata.meta_path, contents);
    if ok {
        log("Wrote asset metadata: %", metadata.meta_path);
    } else {
        log_warning("Failed to write asset metadata: %", metadata.meta_path);
    }

    return ok;
}

asset_manager_generate_guid :: (path: string, type: Asset_Type) -> string {
    hash := fnv1a64(path);
    hash = fnv1a64_continue(hash, asset_type_to_string(type));
    return copy_string(tprint("%", formatInt(hash, base = 16, minimum_digits = 16)));
}

asset_manager_guid_is_legacy :: (guid: string) -> bool {
    if !guid then return true;
    return begins_with(guid, "voxerra-");
}

fnv1a64 :: (value: string) -> u64 {
    return fnv1a64_continue(14695981039346656037, value);
}

fnv1a64_continue :: (hash: u64, value: string) -> u64 {
    result := hash;
    for value {
        result = result ^ cast(u64) it;
        result *= 1099511628211;
    }
    return result;
}

#scope_export

asset_type_to_string :: (type: Asset_Type) -> string {
    if type == .SCENE then return "scene";
    if type == .MODEL then return "model";
    if type == .TEXTURE then return "texture";
    if type == .SHADER then return "shader";
    if type == .CUBEMAP then return "cubemap";
    return "unknown";
}

asset_type_from_string :: (value: string) -> Asset_Type {
    if value == "scene" then return .SCENE;
    if value == "model" then return .MODEL;
    if value == "texture" then return .TEXTURE;
    if value == "shader" then return .SHADER;
    if value == "cubemap" then return .CUBEMAP;
    return .UNKNOWN;
}

asset_type_from_path :: (path: string) -> Asset_Type {
    extension, found := path_extension(path);
    if !found then return .UNKNOWN;

    if extension == "toml" {
        if contains(path, "/scenes/") || contains(path, ".scene.") then return .SCENE;
        return .UNKNOWN;
    }
    if extension == "obj" || extension == "fbx" || extension == "gltf" || extension == "glb" {
        return .MODEL;
    }
    if extension == "png" || extension == "jpg" || extension == "jpeg" || extension == "tga" {
        return .TEXTURE;
    }
    if extension == "vert" || extension == "frag" || extension == "glsl" {
        return .SHADER;
    }

    return .UNKNOWN;
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
        
        found, enabled := table_find(*manager.hot_reload_textures, key);
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
            min_filter       = .NEAREST,
            mag_filter       = .NEAREST,
            wrap_s           = .REPEAT,
            wrap_t           = .REPEAT,
            generate_mipmaps = false,
        }
    );

    return texture;
}

create_checker_texture :: () -> *Texture {
    width :: 8;
    height :: 8;

    data := cast(*u8) alloc(width * height * 4);

    for y: 0..height - 1 {
        for x: 0..width - 1 {
            index := (y * width + x) * 4;
            
            is_purple := ((x / 2) + (y / 2)) % 2 == 0;
            
            if is_purple {
                data[index + 0] = 255; // r
                data[index + 1] = 0;   // g
                data[index + 2] = 255; // b
                data[index + 3] = 255; // a
            } else {
                data[index + 0] = 0;   // r
                data[index + 1] = 0;   // g
                data[index + 2] = 0;   // b
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
