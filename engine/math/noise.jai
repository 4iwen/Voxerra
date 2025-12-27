#scope_file

#import "Math";
#import "Hash";

Neighbor :: struct {
    x: s32;
    y: s32;
}

NEIGHBOR_OFFSETS : [9] Neighbor : .[
    {-1, -1},
    {-1, -0},
    {-1, 1},
    {0, -1},
    {0, -0},
    {0, 1},
    {1, -1},
    {1, -0},
    {1, 1},
];

#scope_export

Worley_Noise_Spec :: struct {
    seed: u64;
    zoom: float;
}

worley_noise_2d :: (x: float64, y: float64, spec: Worley_Noise_Spec) -> float64 {
    x = x / spec.zoom;
    y = y / spec.zoom;

    cell_x: s32 = cast(s32) floor(x);
    cell_y: s32 = cast(s32) floor(y);

    closest := FLOAT64_MAX;

    for offset : NEIGHBOR_OFFSETS {
        cx := cell_x + offset.x;
        cy := cell_y + offset.y;

        fx, fy := cell_point(cx, cy, spec.seed);

        dx := x - fx;
        dy := y - fy;

        dist := dx * dx + dy * dy;
        if dist < closest {
            closest = dist;
        }
    }

    return closest;
}

#scope_file

cell_point :: (cell_x: s32, cell_y: s32, seed: u64) -> float64, float64 {
    hash1 := hash_xy(cell_x, cell_y, seed + 157);
    hash2 := hash_xy(cell_x, cell_y, seed + 1571);

    offset_x := cast(float64) (hash1 & 0xFFFF) / 0xFFFF;
    offset_y := cast(float64) (hash2 & 0xFFFF) / 0xFFFF;

    return cell_x + offset_x, cell_y + offset_y;
}

hash_xy :: (x: s32, y: s32, seed: u64) -> u64 {
    h := get_hash(x);
    h = get_hash(y, h);
    h = get_hash(seed, h);

    return h;
}
