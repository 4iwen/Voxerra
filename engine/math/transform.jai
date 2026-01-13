#scope_file

#import "Basic";
#import "Math";

#scope_export

Transform :: struct {
    position: Vector3 = .{0, 0, 0};
    rotation: Quaternion = .{0, 0, 0, 1};
    scale: Vector3 = .{1, 1, 1};
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

transform_to_matrix :: (transform: Transform) -> Matrix4 {
    translation := make_translation_matrix4(transform.position);
    rotation := rotation_matrix(Matrix4, transform.rotation);
    scale_matrix := scale(Matrix4_Identity, transform.scale);
    return translation * rotation * scale_matrix;
}

transform_reset :: (transform: *Transform) {
    transform.position = .{0, 0, 0};
    transform.rotation = .{0, 0, 0, 1};
    transform.scale = .{1, 1, 1};
}
