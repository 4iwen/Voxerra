#scope_export

#import "jai-imgui";
#import "Math";

metrics_draw :: () {
    io := GetIO();
    
    dt := io.DeltaTime;
    frame_time_ms := dt * 1000.0;

    metrics_state.update_timer -= dt;
    if metrics_state.update_timer <= 0.0 {
        metrics_state.update_timer = 0.150; 
        metrics_state.display_fps = io.Framerate;
    }
    
    metrics_state.frame_time_values[metrics_state.offset] = frame_time_ms;
    metrics_state.offset = (metrics_state.offset + 1) % METRICS_PLOT_COUNT;

    // calculate stats
    min_time := FLOAT32_MAX;
    max_time := -FLOAT32_MAX;
    avg_time := 0.0;
    valid_count := 0;
    
    for metrics_state.frame_time_values {
        if it == 0 continue;
        
        if it < min_time {
            min_time = it;
        }
        if it > max_time {
            max_time = it;
        }
        avg_time += it;
        valid_count += 1;
    }
    
    if valid_count > 0 {
        avg_time /= valid_count;
    } else {
        min_time = 0;
        max_time = 0;
    }
    
    if metrics_state.scale_max_smooth == 0 {
        metrics_state.scale_max_smooth = 30.0;
    }

    target_scale := ifx max_time > 30.0 then max_time * 1.1 else 30.0; 
    
    if target_scale > metrics_state.scale_max_smooth {
        metrics_state.scale_max_smooth = target_scale;
    } else {
        metrics_state.scale_max_smooth = lerp(
            metrics_state.scale_max_smooth,
            target_scale,
            0.05
        );
    }

    SetNextWindowSize(ImVec2.{300, 0}, Cond.FirstUseEver);
    if Begin("Metrics") {
        metrics_ui(
            metrics_state.display_fps,
            min_time,
            max_time,
            avg_time,
            metrics_state.scale_max_smooth
        );
    }
    End();
} @UI_Window

#scope_module

METRICS_PLOT_COUNT :: 240;

Metrics_State :: struct {
    frame_time_values: [METRICS_PLOT_COUNT] float;
    offset: int;
    scale_max_smooth: float;
    
    update_timer: float;
    display_fps: float;
}

metrics_state: Metrics_State;

#scope_file

metrics_ui :: (
    fps: float,
    min_t: float,
    max_t: float,
    avg_t: float,
    scale_max: float
) {
    // performance
    {
        fps_color := ImVec4.{0.0, 1.0, 0.0, 1.0}; // green
        if fps < 30.0 then fps_color = .{1.0, 0.0, 0.0, 1.0}; // red
        else if fps < 58.0 then fps_color = .{1.0, 1.0, 0.0, 1.0}; // yellow

        TextColored(fps_color, "FPS: %", formatFloat(
            fps,
            trailing_width = 0,
            zero_removal = .NO
        ));
    }

    Separator();
    
    // stats
    Columns(3, "stats", false); 
    
    TextColored(ImVec4.{0.6, 0.6, 0.6, 1.0}, "Min"); 
    Text("%ms", formatFloat(min_t,
        trailing_width = 2,
        zero_removal = .NO
    ));
    NextColumn();
    
    TextColored(ImVec4.{0.6, 0.6, 0.6, 1.0}, "Avg"); 
    Text("%ms", formatFloat(
        avg_t,
        trailing_width = 2,
        zero_removal = .NO
    ));
    NextColumn();
    
    TextColored(ImVec4.{0.6, 0.6, 0.6, 1.0}, "Max"); 

    max_color := ImVec4.{1.0, 1.0, 1.0, 1.0};
    if max_t > 18.0 {
        max_color = ImVec4.{1.0, 0.5, 0.0, 1.0};
    }
    TextColored(max_color, "%ms", formatFloat(
        max_t,
        trailing_width = 2,
        zero_removal = .NO
    ));
    NextColumn();
    
    Columns(1);
    
    Separator();
    Spacing();

    // plot
    width := GetContentRegionAvail().x;
    plot_height := 64.0;
    
    PlotLines(
        "##Frame Times",
        metrics_state.frame_time_values.data,
        cast(s32) METRICS_PLOT_COUNT,
        cast(s32) metrics_state.offset,
        "History",
        0.0, 
        scale_max,
        ImVec2.{width, plot_height}
    );
}
