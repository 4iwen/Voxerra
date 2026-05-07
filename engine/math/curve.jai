// File:        curve.jai
// Author:      Lukáš Bien
// Description: Provides shared Catmull-Rom curve sampling helpers for editor and runtime use.

#scope_export

#import "Basic";
#import "Math";

#scope_export

curve_segment_count :: (point_count: s32, closed: bool) -> s32 {
    if point_count < 2 then return 0;
    if closed then return point_count;
    return point_count - 1;
}

curve_catmull_rom_position :: (
    p0: Vector3,
    p1: Vector3,
    p2: Vector3,
    p3: Vector3,
    t: float
) -> Vector3 {
    t2 := t * t;
    t3 := t2 * t;
    return 0.5 * (
        (2.0 * p1) +
        (-p0 + p2) * t +
        (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
        (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
    );
}

curve_catmull_rom_tangent :: (
    p0: Vector3,
    p1: Vector3,
    p2: Vector3,
    p3: Vector3,
    t: float
) -> Vector3 {
    t2 := t * t;
    return 0.5 * (
        (-p0 + p2) +
        (4.0 * p0 - 10.0 * p1 + 8.0 * p2 - 2.0 * p3) * t +
        (-3.0 * p0 + 9.0 * p1 - 9.0 * p2 + 3.0 * p3) * t2
    );
}

#scope_export

curve_resolve_catmull_rom_index :: (point_count: s32, closed: bool, index: s32) -> s32 {
    if point_count <= 0 then return 0;

    if closed {
        wrapped := index % point_count;
        if wrapped < 0 {
            wrapped += point_count;
        }
        return wrapped;
    }

    return clamp(index, 0, point_count - 1);
}

curve_catmull_rom_segment_position :: (
    points: [] Vector3,
    closed: bool,
    segment_index: s32,
    t: float
) -> Vector3 {
    point_count := cast(s32) points.count;
    if point_count == 0 then return .{};
    if point_count == 1 then return points[0];

    p0 := points[curve_resolve_catmull_rom_index(point_count, closed, segment_index - 1)];
    p1 := points[curve_resolve_catmull_rom_index(point_count, closed, segment_index + 0)];
    p2 := points[curve_resolve_catmull_rom_index(point_count, closed, segment_index + 1)];
    p3 := points[curve_resolve_catmull_rom_index(point_count, closed, segment_index + 2)];
    return curve_catmull_rom_position(p0, p1, p2, p3, t);
}

curve_catmull_rom_segment_tangent :: (
    points: [] Vector3,
    closed: bool,
    segment_index: s32,
    t: float
) -> Vector3 {
    point_count := cast(s32) points.count;
    if point_count < 2 then return .{0, 0, 1};

    p0 := points[curve_resolve_catmull_rom_index(point_count, closed, segment_index - 1)];
    p1 := points[curve_resolve_catmull_rom_index(point_count, closed, segment_index + 0)];
    p2 := points[curve_resolve_catmull_rom_index(point_count, closed, segment_index + 1)];
    p3 := points[curve_resolve_catmull_rom_index(point_count, closed, segment_index + 2)];
    tangent := curve_catmull_rom_tangent(p0, p1, p2, p3, t);
    if dot(tangent, tangent) <= 0.000001 {
        return .{0, 0, 1};
    }
    return normalize(tangent);
}
