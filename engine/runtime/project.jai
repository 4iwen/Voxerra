#scope_file

#import "Basic";
#import "File";

using Toml :: #import "toml-jai";

#scope_export

PROJECT_DESCRIPTOR_PATH :: "game/project.toml";

Project_Descriptor :: struct {
    name: string;
    version: s32;
    startup_scene: string;
    editor_startup_scene: string;
    asset_root: string;
    editor_state_path: string;
    default_build_mode: string;
    export_name: string;
}

project_load_descriptor :: (path: string = PROJECT_DESCRIPTOR_PATH) -> Project_Descriptor, bool {
    contents, read_ok := read_entire_file(path);
    if !read_ok {
        log_error("Failed to read project descriptor: %", path);
        return .{}, false;
    }
    defer free(contents);

    parse_ok, descriptor := Toml.string_to_type(contents, Project_Descriptor);
    if !parse_ok {
        log_error("Failed to parse project descriptor: %", path);
        return .{}, false;
    }

    if !descriptor.name {
        descriptor.name = copy_string("Voxerra");
    }
    if descriptor.version == 0 {
        descriptor.version = 1;
    }
    if !descriptor.asset_root {
        descriptor.asset_root = copy_string("game");
    }
    if !descriptor.editor_state_path {
        descriptor.editor_state_path = copy_string("game/editor_workspace.toml");
    }
    if !descriptor.default_build_mode {
        descriptor.default_build_mode = copy_string("editor_and_game");
    }
    if !descriptor.export_name {
        descriptor.export_name = copy_string("voxerra");
    }

    if !descriptor.startup_scene {
        log_error("Project descriptor % is missing startup_scene", path);
        project_descriptor_destroy(*descriptor);
        return .{}, false;
    }
    if !descriptor.editor_startup_scene {
        descriptor.editor_startup_scene = copy_string(descriptor.startup_scene);
    }

    return descriptor, true;
}

project_descriptor_destroy :: (descriptor: *Project_Descriptor) {
    if !descriptor then return;

    free(descriptor.name);
    free(descriptor.startup_scene);
    free(descriptor.editor_startup_scene);
    free(descriptor.asset_root);
    free(descriptor.editor_state_path);
    free(descriptor.default_build_mode);
    free(descriptor.export_name);
    descriptor.* = .{};
}
