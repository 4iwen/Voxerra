#scope_export

#import "Basic";
#import "String";
#import "jai-imgui";

#scope_module

Log_Window_State :: struct {
    filter_buffer: [256] u8;
    show_engine: bool = true;
    show_game: bool = true;
    show_info: bool = true;
    show_warning: bool = true;
    show_error: bool = true;
    auto_scroll: bool = true;
}

log_window_state: Log_Window_State;

#scope_export

log_draw :: () {
    if Begin(UI_Icon_Window_Title(ICON_FA_SCROLL, "Log", "Log")) {
        draw_log_toolbar();
        draw_log_entries();
    }
    End();
} @UI_Window

#scope_file

draw_log_toolbar :: () {
    if BeginTable("log_filter_table", 2) {
        TableNextRow();
        TableSetColumnIndex(0);
        draw_source_filter_combo();
        TableSetColumnIndex(1);
        draw_severity_filter_combo();
        EndTable();
    }

    style := GetStyle();
    auto_scroll_width := GetFrameHeightWithSpacing() + CalcTextSize("Auto scroll").x;
    filter_width := GetContentRegionAvail().x - auto_scroll_width - style.ItemSpacing.x * 2.0;
    if filter_width < 100 then filter_width = 100;

    SetNextItemWidth(filter_width);
    InputTextWithHint(
        "##LogFilter",
        "Filter logs",
        log_window_state.filter_buffer.data,
        log_window_state.filter_buffer.count
    );
    SameLine();
    Checkbox("Auto scroll", *log_window_state.auto_scroll);
}

draw_log_entries :: () {
    entries := logging_get_entries();

    if BeginChild("log_entries", ImVec2.{0, -1}, .FrameStyle, .HorizontalScrollbar) {
        visible_count := 0;
        bottom_threshold := 8;
        was_at_bottom := GetScrollY() >= GetScrollMaxY() - bottom_threshold;
        for entry, index: entries {
            if !log_entry_visible(entry) then continue;

            draw_log_line(entry, index);
            visible_count += 1;
        }

        if visible_count == 0 {
            TextDisabled("No logs");
        }

        if log_window_state.auto_scroll && was_at_bottom {
            SetScrollHereY(1.0);
        }
    }
    EndChild();
}

draw_log_line :: (entry: Log_Entry, index: int) {
    PushID(cast(s32) index);
    defer PopID();

    line_text := logging_get_entry_text(entry);
    line_height := GetTextLineHeight();
    row_width := GetContentRegionAvail().x;
    row_cursor := GetCursorPos();

    PushStyleColor(.Header, ImVec4.{0.16, 0.16, 0.16, 0.0});
    PushStyleColor(.HeaderHovered, ImVec4.{0.24, 0.24, 0.24, 0.95});
    PushStyleColor(.HeaderActive, ImVec4.{0.24, 0.24, 0.24, 0.95});
    Selectable("##row", false, .None, ImVec2.{row_width, line_height});
    PopStyleColor();
    PopStyleColor();
    PopStyleColor();

    if BeginPopupContextItem("line_context") {
        if MenuItem(UI_Icon_Label(ICON_FA_COPY, "Copy line")) {
            SetClipboardText(temp_c_string(line_text));
        }
        if MenuItem(UI_Icon_Label(ICON_FA_COPY, "Copy all")) {
            copy_logs_to_clipboard();
        }
        EndPopup();
    }

    SetCursorPos(row_cursor);

    TextDisabled("[%]", logging_get_timestamp_text(entry.timestamp));
    SameLine(0, 0);
    TextColored(log_source_color(entry.source), "[%]", enum_value_to_name(entry.source));
    SameLine(0, 0);
    TextColored(log_severity_color(entry.severity), "[%]", enum_value_to_name(entry.severity));
    SameLine();
    Text("%", entry.message);
}

draw_source_filter_combo :: () {
    SetNextItemWidth(-1);
    if BeginCombo("##Sources", temp_c_string(source_filter_preview())) {
        Checkbox("Engine", *log_window_state.show_engine);
        Checkbox("Game", *log_window_state.show_game);
        EndCombo();
    }
}

draw_severity_filter_combo :: () {
    SetNextItemWidth(-1);
    if BeginCombo("##Severity", temp_c_string(severity_filter_preview())) {
        Checkbox("Info", *log_window_state.show_info);
        Checkbox("Warning", *log_window_state.show_warning);
        Checkbox("Error", *log_window_state.show_error);
        EndCombo();
    }
}

log_entry_visible :: (entry: Log_Entry) -> bool {
    if entry.source == .ENGINE && !log_window_state.show_engine then return false;
    if entry.source == .GAME && !log_window_state.show_game then return false;

    if entry.severity == .INFO && !log_window_state.show_info then return false;
    if entry.severity == .WARNING && !log_window_state.show_warning then return false;
    if entry.severity == .ERROR && !log_window_state.show_error then return false;

    filter_text := to_string(log_window_state.filter_buffer.data);
    if filter_text.count == 0 then return true;

    if contains_nocase(entry.message, filter_text) then return true;
    if contains_nocase(enum_value_to_name(entry.source), filter_text) then return true;
    if contains_nocase(enum_value_to_name(entry.severity), filter_text) then return true;
    if contains_nocase(logging_get_timestamp_text(entry.timestamp), filter_text) then return true;
    return false;
}

copy_logs_to_clipboard :: () {
    builder: String_Builder;
    init_string_builder(*builder);

    for entry: logging_get_entries() {
        print_to_builder(*builder, "%\n", logging_get_entry_text(entry));
    }

    clipboard_text := builder_to_string(*builder);
    SetClipboardText(temp_c_string(clipboard_text));
}

log_source_color :: (source: Log_Source) -> ImVec4 {
    if source == { 
        case .GAME; return ImVec4.{1.0, 0.35, 1.0, 1.0};
        case;       return ImVec4.{0.35, 0.85, 1.0, 1.0};
    }
}

log_severity_color :: (severity: Log_Severity) -> ImVec4 {
    if severity == { 
        case .ERROR;   return ImVec4.{1.0, 0.25, 0.25, 1.0};
        case .WARNING; return ImVec4.{1.0, 0.9, 0.2, 1.0};
        case;          return ImVec4.{0.35, 1.0, 0.45, 1.0};
    }
}

source_filter_preview :: () -> string {
    builder: String_Builder;
    init_string_builder(*builder);
    dirty := false;

    if log_window_state.show_engine {
        append(*builder, "Engine");
        dirty = true;
    }
    if log_window_state.show_game {
        if dirty then append(*builder, ", ");
        append(*builder, "Game");
        dirty = true;
    }

    if dirty then return builder_to_string(*builder);
    return "None";
}

severity_filter_preview :: () -> string {
    builder: String_Builder;
    init_string_builder(*builder);
    dirty := false;

    if log_window_state.show_info {
        append(*builder, "Info");
        dirty = true;
    }
    if log_window_state.show_warning {
        if dirty then append(*builder, ", ");
        append(*builder, "Warning");
        dirty = true;
    }
    if log_window_state.show_error {
        if dirty then append(*builder, ", ");
        append(*builder, "Error");
        dirty = true;
    }
    
    if dirty then return builder_to_string(*builder);
    return "None";
}
