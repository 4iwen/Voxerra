#scope_file

#import "Basic";
#import "Print_Color";

#scope_file

colored_logger :: (message: string, data: *void, info: Log_Info) {
    to_standard_error := (info.common_flags & .ERROR) != 0;

    is_error := (info.common_flags & .ERROR) != 0;
    is_warning := (info.common_flags & .WARNING) != 0;

    tag: string;
    color: Console_Color;

    if is_error {
        tag = "ERROR";
        color = .HI_RED;
    } else if is_warning {
        tag = "WARN";
        color = .HI_YELLOW;
    } else {
        tag = "INFO";
        color = .HI_WHITE;
    }

    with_console_color(color, #code {
        write_string("[");
        write_string(tag);
        write_string("] ");
    }, style = .BOLD, to_standard_error = to_standard_error);

    write_string(message, to_standard_error = to_standard_error);
    if message && message[message.count - 1] != #char "\n" {
        write_string("\n", to_standard_error = to_standard_error);
    }
}

#scope_export

install_logger :: () {
    context.logger = colored_logger;
    context.logger_data = null;
}

// log_warning :: (format_string: string, args: .. Any) {
    // log(format_string, ..args, level = .WARNING);
// }

log_warning :: (
    format_string: string,
    args: .. Any,
    loc := #caller_location,
    flags := Log_Flags.NONE,
    user_flags: u32 = 0,
    section: *Log_Section = null
) {
    new_flags := flags | .WARNING;
    log(format_string, ..args, loc, new_flags, user_flags, section);
} @PrintLike
