// File:        transform.jai
// Author:      Lukáš Bien
// Description: Defines transform math helpers for matrices, quaternions,
//              and local/world conversion.

#scope_file

#import "Basic";
#import "Math";

#scope_export

Transform :: struct {
    position: Vector3 = .{0, 0, 0}; @"Tooltip(\"The local 3D position relative to the parent\")"
    rotation: Quaternion = .{0, 0, 0, 1}; @"Tooltip(\"The local orientation rotation\")"
    scale: Vector3 = .{1, 1, 1}; @"Tooltip(\"The local scale multiplier\")"
}

quaternion_from_euler_xyz :: (xyz_radians: Vector3) -> Quaternion {
    qx: Quaternion = ---; 
    qy: Quaternion = ---;
    qz: Quaternion = ---;
    set_from_axis_and_angle(*qx, .{1, 0, 0}, xyz_radians.x);
    set_from_axis_and_angle(*qy, .{0, 1, 0}, xyz_radians.y);
    set_from_axis_and_angle(*qz, .{0, 0, 1}, xyz_radians.z);

    q := qz * qy * qx;
    normalize_or_identity(*q);
    return q;
}

quaternion_to_euler_xyz :: (q: Quaternion) -> Vector3 {
    nq := q;
    normalize_or_identity(*nq);

    x := nq.x;
    y := nq.y;
    z := nq.z;
    w := nq.w;

    result: Vector3;

    // X (pitch)
    sinr_cosp := 2.0 * (w * x + y * z);
    cosr_cosp := 1.0 - 2.0 * (x * x + y * y);
    result.x = atan2(sinr_cosp, cosr_cosp);

    // Y (yaw)
    sinp := 2.0 * (w * y - z * x);
    if abs(sinp) >= 1.0 {
        if sinp > 0.0 {
            result.y = PI * 0.5;
        } else {
            result.y = -PI * 0.5;
        }
    } else {
        result.y = asin(sinp);
    }

    // Z (roll)
    siny_cosp := 2.0 * (w * z + x * y);
    cosy_cosp := 1.0 - 2.0 * (y * y + z * z);
    result.z = atan2(siny_cosp, cosy_cosp);

    return result;
}

transform_to_matrix :: (transform: Transform) -> Matrix4 {
    translation := make_translation_matrix4(transform.position);
    rotation := rotation_matrix(Matrix4, transform.rotation);
    scale_matrix := scale(Matrix4_Identity, transform.scale);
    return translation * rotation * scale_matrix;
}

transform_extract_rotation :: (m: Matrix4) -> Quaternion {
    r := m;

    x := Vector3.{r._11, r._21, r._31};
    y := Vector3.{r._12, r._22, r._32};
    z := Vector3.{r._13, r._23, r._33};

    normalize(*x, 0.000001, .{1, 0, 0});
    normalize(*y, 0.000001, .{0, 1, 0});
    normalize(*z, 0.000001, .{0, 0, 1});

    r._11 = x.x; r._21 = x.y; r._31 = x.z;
    r._12 = y.x; r._22 = y.y; r._32 = y.z;
    r._13 = z.x; r._23 = z.y; r._33 = z.z;

    q := get_rotation(r);
    normalize_or_identity(*q);
    return q;
}

transform_reset :: (transform: *Transform) {
    transform.position = .{0, 0, 0};
    transform.rotation = .{0, 0, 0, 1};
    transform.scale = .{1, 1, 1};
}
