#scope_file

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "String";

build :: () {
    set_build_options_dc(.{do_output = false});

    args := get_build_options().compile_time_command_line;
    export := array_find(args, "-export");
    editor := array_find(args, "-editor");
    game := array_find(args, "-game");

    if export {
        build_export();
    } else if editor {
        build_editor();
    } else if game {
        build_game();
    } else {
        build_editor();
        build_game();
    }
}

build_editor :: () {
    ok, workspace := setup_workspace("Editor", "editor", .EXECUTABLE);
    if !ok then return;

    compiler_begin_intercept(workspace);
    add_build_string("BUILD_MODE :: Build_Mode.EDITOR;", workspace);
    add_memory_debugger(workspace);

    add_build_file("./engine/main.jai", workspace);
    message_loop();
    compiler_end_intercept(workspace);
}

build_game :: () {
    ok, workspace := setup_workspace("Game", "game", .DYNAMIC_LIBRARY);
    if !ok then return;

    compiler_begin_intercept(workspace);
    add_build_string("BUILD_MODE :: Build_Mode.GAME;", workspace);
    add_memory_debugger(workspace);
    add_build_file("./engine/main.jai", workspace);

    wait_for_compile_complete();
    compiler_end_intercept(workspace);
}

build_export :: () {
    ok, workspace := setup_workspace("Export", "voxerra", .EXECUTABLE);
    if !ok then return;

    options := get_build_options(workspace);
    set_optimization(*options, .OPTIMIZED);
    set_build_options(options, workspace);

    compiler_begin_intercept(workspace);
    add_build_string("BUILD_MODE :: Build_Mode.EXPORT;", workspace);
    add_memory_debugger(workspace);
    add_build_file("./engine/main.jai", workspace);

    wait_for_compile_complete();
    compiler_end_intercept(workspace);
}

add_memory_debugger :: (workspace: Workspace) {
    args := get_build_options().compile_time_command_line;
    enable_memory_debugger := array_find(args, "-memory_debugger");
    add_build_string(tprint("MEMORY_DEBUGGER_ENABLED :: %;", enable_memory_debugger), workspace);
}

setup_workspace :: (
    workspace_name: string,
    executable_name: string,
    output_type: Build_Options.Output_Type
) -> bool, Workspace {
    workspace := compiler_create_workspace(workspace_name);
    if !workspace then return false, 0;

    build_options := get_build_options(workspace);
    copy_commonly_propagated_fields(get_build_options(), *build_options);
    build_options.output_executable_name = executable_name;
    make_directory_if_it_does_not_exist("./bin");
    build_options.output_path = "./bin";
    build_options.output_type = output_type;

    new_path: [..] string;
    array_add(*new_path, ..build_options.import_path);
    array_add(*new_path, "./");
    build_options.import_path = new_path;

    set_build_options(build_options, workspace);

    return true, workspace;
}

#run build();

wait_for_compile_complete :: () {
    while true {
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE then break;
    }
}

message_loop :: () {
    ui_window_procedures: [..] *Code_Procedure_Header;
    ui_components: [..] string;
    generated := false;

    while true {
        message := compiler_wait_for_message();

        if message.kind == {
            case .TYPECHECKED;
                typechecked := cast(*Message_Typechecked) message;
                process_typechecked_message(typechecked, *ui_window_procedures, *ui_components);

            case .PHASE;
                phase := cast(*Message_Phase) message;
                if phase.phase == .TYPECHECKED_ALL_WE_CAN && !generated {
                    generate_ui_definitions(message.workspace, ui_window_procedures, ui_components);
                    array_reset(*ui_window_procedures);
                    array_reset(*ui_components);
                    generated = true;
                }

            case .COMPLETE;
                break;
        }
    }
}

process_typechecked_message :: (
    message: *Message_Typechecked,
    ui_window_procedures: *[..] *Code_Procedure_Header,
    ui_components: *[..] string
) {
    for item: message.procedure_headers {
        header := item.expression;
        if has_note(header, "UI_Window") {
            if !array_find(ui_window_procedures.*, header) {
                array_add(ui_window_procedures, header);
            }
        }
    }

    for item: message.declarations {
        declaration := item.expression;
        is_struct := declaration.expression && declaration.expression.kind == .STRUCT;

        if is_struct && declaration.name && has_note(declaration, "Component") {
            if !array_find(ui_components.*, declaration.name) {
                array_add(ui_components, declaration.name);
            }
        }
    }
}

generate_ui_definitions :: (
    workspace: Workspace,
    ui_window_procedures: [..] *Code_Procedure_Header,
    ui_components: [..] string
) {
    builder: String_Builder;

    print_to_builder(*builder, "ui_window_procedures: [%] string : .[", ui_window_procedures.count);
    for ui_window_procedures print_to_builder(*builder, "\"%\",", it.name);
    print_to_builder(*builder, "];\n");

    print_to_builder(*builder, "ui_available_components: [%] string : .[", ui_components.count);
    for ui_components print_to_builder(*builder, "\"%\",", it);
    print_to_builder(*builder, "];\n");

    result := builder_to_string(*builder);
    add_build_string(result, workspace);
}

has_note :: (header: *Code_Procedure_Header, note: string) -> bool {
    for header.notes if it.text == note then return true;
    return false;
}

has_note :: (declaration: *Code_Declaration, note: string) -> bool {
    for declaration.notes if it.text == note then return true;
    return false;
}
