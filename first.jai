#scope_file

#import "Basic";
#import "Compiler";
#import "File";

build :: () {
    set_build_options_dc(.{do_output = false});

    workspace := compiler_create_workspace("Target Program");
    if !workspace {
        print("Failed to create workspace.\n");
        return;
    }

    // build options for executable
    build_options := get_build_options(workspace);
    copy_commonly_propagated_fields(get_build_options(), *build_options);
    build_options.output_executable_name = "Voxerra";
    make_directory_if_it_does_not_exist("./bin");
    build_options.output_path = "./bin";
    build_options.output_type = .EXECUTABLE;

    // modify the include path
    new_path: [..] string;
    array_add(*new_path, ..build_options.import_path);
    array_add(*new_path, "./");
    build_options.import_path = new_path;

    set_build_options(build_options, workspace);

    compiler_begin_intercept(workspace, .SKIP_EXPRESSIONS_WITHOUT_NOTES);
    add_build_file("./game/main.jai", workspace);

    args := get_build_options().compile_time_command_line;
    enable_memory_debugger := array_find(args, "-memory_debugger");
    add_build_string(
        tprint("MEMORY_DEBUGGER_ENABLED :: %;", enable_memory_debugger),
        workspace
    );

    message_loop();
    compiler_end_intercept(workspace);
}

#run build();

message_loop :: () {
    ui_window_procedures: [..] *Code_Procedure_Header;
    generated := false;

    while true {
        message := compiler_wait_for_message();
        if message.kind == {
            case .TYPECHECKED;
                typechecked := cast(*Message_Typechecked) message;
                for tc: typechecked.procedure_headers {
                    header := tc.expression;
                    if has_note(header, "UI_Window") {
                        array_add(*ui_window_procedures, header);
                    }
                }
            case .PHASE;
                phase := cast(*Message_Phase) message;
                if phase.phase == .TYPECHECKED_ALL_WE_CAN {
                    if !generated {
                        builder: String_Builder;

                        print_to_builder(
                            *builder, 
                            "ui_window_procedures: [%] string : .[",
                            ui_window_procedures.count
                        );
                        for ui_window_procedures {
                            print_to_builder(*builder, "\"%\",", it.name);
                        }
                        print_to_builder(*builder, "];");

                        result := builder_to_string(*builder);
                        add_build_string(result, message.workspace);
                        array_reset(*ui_window_procedures);
                        generated = true;
                    }
                }
            case .COMPLETE;
                break;
        }
    }
}

has_note :: (header: *Code_Procedure_Header, note: string) -> bool {
    for header.notes {
        if it.text == note {
            return true;
        }
    }

    return false;
}
