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

    build_options := get_build_options(workspace);
    copy_commonly_propagated_fields(get_build_options(), *build_options);
    build_options.output_executable_name = "Voxerra";
    make_directory_if_it_does_not_exist("./bin");
    build_options.output_path = "./bin";
    build_options.output_type = .EXECUTABLE;
    set_build_options(build_options, workspace);

    add_build_file("./game/main.jai", workspace);
}

#run build();
