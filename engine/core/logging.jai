#scope_file

#import "Basic";
#import "Print_Color";
#import "Reflection";

logging_state: Logging_State;

#scope_module

MAX_LOG_ENTRIES :: 2048;

Log_Source :: enum {
    ENGINE;
    GAME;
}
Log_Severity :: enum {
    INFO;
    WARNING;
    ERROR;
}

Log_Entry :: struct {
    source: Log_Source;
    severity: Log_Severity;
    message: string;
    timestamp: Apollo_Time;
}

Logging_State :: struct {
    entries: [MAX_LOG_ENTRIES] Log_Entry;
    ordered_entries: [MAX_LOG_ENTRIES] Log_Entry;
    start_index: int;
    entry_count: int;
}

#scope_export

logging_init :: () {
    logging_state = .{};
    logging_install_logger();
}

logging_install_logger :: () {
    context.logger = colored_logger;
    context.logger_data = null;
}

logging_shutdown :: () {
    if logging_state.entry_count == 0 {
        return;
    }

    for i: 0..logging_state.entry_count - 1 {
        entry_index := ring_index_for_offset(i);
        free(logging_state.entries[entry_index].message);
        logging_state.entries[entry_index].message = "";
    }

    logging_state.start_index = 0;
    logging_state.entry_count = 0;
}

logging_get_entries :: () -> [] Log_Entry {
    if logging_state.entry_count == 0 {
        return array_view(logging_state.ordered_entries, 0, 0);
    }

    for i: 0..logging_state.entry_count - 1 {
        entry_index := ring_index_for_offset(i);
        logging_state.ordered_entries[i] = logging_state.entries[entry_index];
    }

    return array_view(
        logging_state.ordered_entries,
        0,
        logging_state.entry_count
    );
}

host_log_write :: (
    source: Log_Source,
    severity: Log_Severity,
    message: string
) {
    entry := make_log_entry(source, severity, message);

    write_log_entry(entry);
    append_log_entry(entry);
}

log_warning :: (
    format_string: string,
    args: .. Any,
    loc := #caller_location,
    flags := Log_Flags.NONE,
    user_flags: u32 = 0,
    section: *Log_Section = null
) {
    message := tprint(format_string, ..args);
    host_log_write(.ENGINE, .WARNING, message);
} @PrintLike

logging_get_entry_text :: (entry: Log_Entry) -> string {
    return tprint(
        "[%][%][%] %",
        logging_get_timestamp_text(entry.timestamp),
        enum_value_to_name(entry.source),
        enum_value_to_name(entry.severity),
        entry.message
    );
}

logging_get_timestamp_text :: (timestamp: Apollo_Time) -> string {
    calendar := to_calendar(timestamp, .LOCAL);
    return tprint(
        "%:%:%.%",
        log_time_part(calendar.hour),
        log_time_part(calendar.minute),
        log_time_part(calendar.second),
        formatInt(calendar.millisecond, minimum_digits = 3)
    );
}

#scope_file

make_log_entry :: (
    source: Log_Source,
    severity: Log_Severity,
    message: string
) -> Log_Entry {
    entry: Log_Entry;
    entry.source = source;
    entry.severity = severity;
    entry.message = copy_string(message);
    entry.timestamp = current_time_consensus();
    return entry;
}

append_log_entry :: (entry: Log_Entry) {
    if logging_state.entry_count < MAX_LOG_ENTRIES {
        write_index := ring_index_for_offset(logging_state.entry_count);
        logging_state.entries[write_index] = entry;
        logging_state.entry_count += 1;
        return;
    }

    write_index := logging_state.start_index;
    free(logging_state.entries[write_index].message);
    logging_state.entries[write_index] = entry;
    logging_state.start_index = (logging_state.start_index + 1) % MAX_LOG_ENTRIES;
}

ring_index_for_offset :: (offset: int) -> int {
    return (logging_state.start_index + offset) % MAX_LOG_ENTRIES;
}

write_log_entry :: (entry: Log_Entry) {
    to_standard_error := entry.severity == .ERROR;

    source_tag, source_color := log_source_style(entry.source);
    severity_tag, severity_color := log_severity_style(entry.severity);

    write_log_prefix(entry.timestamp, to_standard_error);

    with_console_color(source_color, #code {
        write_string("[");
        write_string(source_tag);
        write_string("]");
    }, style = .BOLD, to_standard_error = to_standard_error);

    with_console_color(severity_color, #code {
        write_string("[");
        write_string(severity_tag);
        write_string("] ");
    }, style = .BOLD, to_standard_error = to_standard_error);

    write_string(entry.message, to_standard_error = to_standard_error);
    if entry.message && entry.message[entry.message.count - 1] != #char "\n" {
        write_string("\n", to_standard_error = to_standard_error);
    }
}

write_log_prefix :: (
    timestamp: Apollo_Time,
    to_standard_error: bool
) {
    with_console_color(.WHITE, #code {
        write_string("[");
        write_string(logging_get_timestamp_text(timestamp));
        write_string("]");
    }, style = .BOLD, to_standard_error = to_standard_error);
}

colored_logger :: (message: string, data: *void, info: Log_Info) {
    _ = data;
    severity := log_info_to_severity(info);
    host_log_write(.ENGINE, severity, message);
}

log_info_to_severity :: (info: Log_Info) -> Log_Severity {
    if (info.common_flags & .ERROR) != 0 then return .ERROR;
    if (info.common_flags & .WARNING) != 0 then return .WARNING;
    return .INFO;
}

log_source_style :: (source: Log_Source) -> string, Console_Color {
    if source == .GAME then return enum_value_to_name(source), .MAGENTA;
    return enum_value_to_name(source), .CYAN;
}

log_severity_style :: (severity: Log_Severity) -> string, Console_Color {
    if severity == .ERROR then return enum_value_to_name(severity), .RED;
    if severity == .WARNING then return enum_value_to_name(severity), .YELLOW;
    return enum_value_to_name(severity), .GREEN;
}

log_time_part :: (value: Any) -> FormatInt {
    return formatInt(value, minimum_digits = 2);
}
