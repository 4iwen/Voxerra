// File:        metrics.jai
// Author:      Lukáš Bien
// Description: Displays runtime and renderer metrics inside the editor UI.

#scope_export

#import "Basic";
#import "jai-imgui";
#import "Math";

metrics_draw :: () {
    io := GetIO();

    frame_time_ms := io.DeltaTime * 1000.0;
    metrics_state.frame_time_values[metrics_state.offset] = frame_time_ms;
    metrics_state.offset = (metrics_state.offset + 1) % METRICS_HISTORY_COUNT;

    SetNextWindowSize(ImVec2.{300, 0}, Cond.FirstUseEver);
    if Begin(UI_Icon_Window_Title(ICON_FA_GAUGE, "Metrics", "Metrics")) {
        metrics_ui(io.Framerate);
    }
    End();
} @UI_Window

#scope_module

METRICS_HISTORY_COUNT :: 2048;
METRICS_SCALE_MAX_MS :: 33.333;
METRICS_GOOD_FRAME_MS :: 16.667;
METRICS_GRAPH_ROUNDING :: 4.0;
METRICS_GRAPH_PADDING :: 2.0;
METRICS_CANDLE_WIDTH :: 2.0;
METRICS_CANDLE_GAP :: 0.0;

Metrics_State :: struct {
    frame_time_values: [METRICS_HISTORY_COUNT] float;
    offset: int;
}

metrics_state: Metrics_State;

#scope_file

metrics_ui :: (fps: float) {
    stats_visible_count := metrics_get_visible_count(
        GetContentRegionAvail().x - METRICS_GRAPH_PADDING * 2.0
    );
    min_time, max_time, avg_time := metrics_compute_visible_stats(stats_visible_count);

    fps_color := ImVec4.{0.0, 1.0, 0.0, 1.0};
    if fps < 30.0 then fps_color = .{1.0, 0.0, 0.0, 1.0};
    else if fps < 58.0 then fps_color = .{1.0, 1.0, 0.0, 1.0};

    TextColored(fps_color, "FPS: %", formatFloat(
        fps,
        trailing_width = 0,
        zero_removal = .NO
    ));

    Separator();

    Columns(3, "stats", false);

    TextColored(ImVec4.{0.6, 0.6, 0.6, 1.0}, "Min");
    Text("%ms", formatFloat(
        min_time,
        trailing_width = 2,
        zero_removal = .NO
    ));
    NextColumn();

    TextColored(ImVec4.{0.6, 0.6, 0.6, 1.0}, "Avg");
    Text("%ms", formatFloat(
        avg_time,
        trailing_width = 2,
        zero_removal = .NO
    ));
    NextColumn();

    TextColored(ImVec4.{0.6, 0.6, 0.6, 1.0}, "Max");
    max_color := ImVec4.{1.0, 1.0, 1.0, 1.0};
    if max_time >= METRICS_SCALE_MAX_MS {
        max_color = ImVec4.{1.0, 0.35, 0.20, 1.0};
    } else if max_time >= METRICS_GOOD_FRAME_MS {
        max_color = ImVec4.{0.95, 0.80, 0.25, 1.0};
    }
    TextColored(max_color, "%ms", formatFloat(
        max_time,
        trailing_width = 2,
        zero_removal = .NO
    ));
    NextColumn();

    Columns(1);

    Separator();

    graph_avail := GetContentRegionAvail();
    graph_size := ImVec2.{graph_avail.x, max(1.0, graph_avail.y)};
    visible_count := metrics_get_visible_count(graph_size.x - METRICS_GRAPH_PADDING * 2.0);

    draw_lagometer(graph_size, visible_count);
}

metrics_get_visible_count :: (inner_width: float) -> int {
    candle_pitch := METRICS_CANDLE_WIDTH + METRICS_CANDLE_GAP;
    count := cast(int) floor((inner_width + METRICS_CANDLE_GAP) / candle_pitch);
    count = clamp(count, 1, METRICS_HISTORY_COUNT);
    return count;
}

metrics_compute_visible_stats :: (visible_count: int) -> (float, float, float) {
    min_time := FLOAT32_MAX;
    max_time := 0.0;
    avg_time := 0.0;
    valid_count := 0;

    first_sample_index := metrics_state.offset - visible_count;
    while first_sample_index < 0 {
        first_sample_index += METRICS_HISTORY_COUNT;
    }

    for i: 0..visible_count - 1 {
        sample_index := (first_sample_index + i) % METRICS_HISTORY_COUNT;
        sample_ms := metrics_state.frame_time_values[sample_index];
        if sample_ms <= 0.0 then continue;

        if sample_ms < min_time then min_time = sample_ms;
        if sample_ms > max_time then max_time = sample_ms;
        avg_time += sample_ms;
        valid_count += 1;
    }

    if valid_count == 0 {
        return 0.0, 0.0, 0.0;
    }

    avg_time /= valid_count;
    return min_time, max_time, avg_time;
}

draw_lagometer :: (graph_size: ImVec2, visible_count: int) {
    graph_min := GetCursorScreenPos();
    graph_max := graph_min + graph_size;
    inner_min := graph_min + ImVec2.{METRICS_GRAPH_PADDING, METRICS_GRAPH_PADDING};
    inner_max := graph_max - ImVec2.{METRICS_GRAPH_PADDING, METRICS_GRAPH_PADDING};
    inner_height := inner_max.y - inner_min.y;
    draw_list := GetWindowDrawList();

    bg_color := GetColorU32(ImVec4.{0.05, 0.05, 0.06, 1.0});
    border_color := GetColorU32(ImVec4.{0.20, 0.20, 0.22, 1.0});
    line_60fps := GetColorU32(ImVec4.{0.45, 0.85, 1.0, 0.55});
    line_30fps := GetColorU32(ImVec4.{1.00, 0.55, 0.20, 0.50});
    line_label_color := GetColorU32(ImVec4.{0.95, 0.96, 0.98, 1.0});

    ImDrawList.AddRectFilled(draw_list, graph_min, graph_max, bg_color, METRICS_GRAPH_ROUNDING);

    ImDrawList.PushClipRect(draw_list, inner_min, inner_max, true);
    draw_threshold_line(draw_list, inner_min, inner_max, METRICS_GOOD_FRAME_MS, line_60fps);
    draw_threshold_line(draw_list, inner_min, inner_max, METRICS_SCALE_MAX_MS, line_30fps);

    first_sample_index := metrics_state.offset - visible_count;
    while first_sample_index < 0 {
        first_sample_index += METRICS_HISTORY_COUNT;
    }

    for i: 0..visible_count - 1 {
        sample_index := (first_sample_index + i) % METRICS_HISTORY_COUNT;
        sample_ms := metrics_state.frame_time_values[sample_index];
        if sample_ms <= 0.0 then continue;

        clamped_ms := clamp(sample_ms, 0.0, METRICS_SCALE_MAX_MS);
        normalized_height := clamped_ms / METRICS_SCALE_MAX_MS;
        candle_height := normalized_height * inner_height;
        if candle_height < 1.0 then candle_height = 1.0;

        candle_pitch := METRICS_CANDLE_WIDTH + METRICS_CANDLE_GAP;
        x := inner_max.x - cast(float) (visible_count - i) * candle_pitch;
        y1 := inner_max.y;
        y0 := y1 - candle_height;

        candle_color := metrics_frame_time_color(sample_ms);

        ImDrawList.AddRectFilled(
            draw_list,
            ImVec2.{x, y0},
            ImVec2.{x + METRICS_CANDLE_WIDTH, y1},
            candle_color
        );
    }
    ImDrawList.PopClipRect(draw_list);

    draw_threshold_label(draw_list, inner_min, inner_max, METRICS_SCALE_MAX_MS, line_label_color);
    draw_threshold_label(draw_list, inner_min, inner_max, METRICS_GOOD_FRAME_MS, line_label_color);
    ImDrawList.AddRect(draw_list, graph_min, graph_max, border_color, METRICS_GRAPH_ROUNDING);
    Dummy(graph_size);
}

draw_threshold_line :: (
    draw_list: *ImDrawList,
    inner_min: ImVec2,
    inner_max: ImVec2,
    value_ms: float,
    color: ImU32
) {
    normalized_height := clamp(value_ms / METRICS_SCALE_MAX_MS, 0.0, 1.0);
    y := inner_max.y - normalized_height * (inner_max.y - inner_min.y);
    ImDrawList.AddLine(
        draw_list,
        ImVec2.{inner_min.x, y},
        ImVec2.{inner_max.x, y},
        color
    );
}

draw_threshold_label :: (
    draw_list: *ImDrawList,
    inner_min: ImVec2,
    inner_max: ImVec2,
    value_ms: float,
    color: ImU32
) {
    normalized_height := clamp(value_ms / METRICS_SCALE_MAX_MS, 0.0, 1.0);
    y := inner_max.y - normalized_height * (inner_max.y - inner_min.y);

    label := tprint("%ms", formatFloat(
        value_ms,
        trailing_width = 1,
        zero_removal = .NO
    ));
    text_size := CalcTextSize(label);
    text_pos := ImVec2.{
        inner_min.x + 4.0,
        y - text_size.y - 1.0
    };

    if text_pos.y < inner_min.y {
        text_pos.y = inner_min.y;
    }
    if text_pos.y + text_size.y > inner_max.y {
        text_pos.y = inner_max.y - text_size.y;
    }

    ImDrawList.AddText(draw_list, text_pos, color, label);
}

metrics_frame_time_color :: (sample_ms: float) -> ImU32 {
    good := ImVec4.{0.35, 0.90, 0.45, 1.0};
    warn := ImVec4.{0.95, 0.80, 0.25, 1.0};
    bad  := ImVec4.{1.00, 0.35, 0.20, 1.0};

    if sample_ms <= METRICS_GOOD_FRAME_MS {
        t := clamp(sample_ms / METRICS_GOOD_FRAME_MS, 0.0, 1.0);
        return GetColorU32(lerp(good, warn, t));
    }

    t := clamp(
        (sample_ms - METRICS_GOOD_FRAME_MS) / (METRICS_SCALE_MAX_MS - METRICS_GOOD_FRAME_MS),
        0.0,
        1.0
    );
    return GetColorU32(lerp(warn, bad, t));
}
