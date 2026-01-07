#scope_file

#import "Basic";

#scope_export

Fps_Counter :: struct {
    elapsed_seconds: float64;
    frame_count: s32;
    fps: s32;
}

#scope_module

fps_counter: Fps_Counter;

#scope_export

fps_counter_update :: (update_interval_seconds: float64 = 0.5) -> s32 {
    delta_time := engine_get_delta_time();
    if delta_time > 0 {
        fps_counter.elapsed_seconds += delta_time;
        fps_counter.frame_count += 1;
    }

    if fps_counter.elapsed_seconds >= update_interval_seconds && fps_counter.frame_count > 0 {
        fps_f := cast(float64) fps_counter.frame_count / fps_counter.elapsed_seconds;
        fps_counter.fps = cast(s32) fps_f;
        fps_counter.elapsed_seconds = 0;
        fps_counter.frame_count = 0;
    }

    return fps_counter.fps;
}

fps_counter_draw :: (
    x: float = 16,
    y: float = 16,
    font_size: float = 24.0,
    color := Color.{1.0, 1.0, 1.0, 1.0},
    update_interval_seconds: float64 = 0.5
) -> width: float {
    font := font_get_default();
    if !font {
        return 0;
    }

    fps := fps_counter_update(update_interval_seconds);
    fps_text := tprint("FPS: %", fps);
    return text_draw(font, fps_text, x, y, font_size, color);
}
