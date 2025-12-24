#scope_file

#import "Basic";
#import "Math";

#scope_export

Camera :: struct {
    position: Vector3;
    front: Vector3 = .{0, 0, -1};
    up: Vector3 = .{0, 1, 0};
    right: Vector3 = .{1, 0, 0};
    world_up: Vector3 = .{0, 1, 0};

    yaw: float = -90.0;
    pitch: float = 0.0;

    near: float = 0.1;
    far: float = 1000.0;

    fov: float = 45.0;
}

camera_create :: (position: Vector3) -> Camera {
    camera: Camera;
    camera.position = position;
    camera_update_vectors(*camera);
    return camera;
}

camera_get_view_matrix :: (camera: Camera) -> Matrix4 {
    center := camera.position + camera.front;
    return make_look_at_matrix(camera.position, center, camera.up, x_is_forward = false);
}

camera_get_projection_matrix :: (camera: Camera, aspect: float) -> Matrix4 {
    return make_projection_matrix(degrees_to_radians(camera.fov), aspect, camera.near, camera.far);
}

camera_update_vectors :: (camera: *Camera) {
    yaw_radians := degrees_to_radians(camera.yaw);
    pitch_radians := degrees_to_radians(camera.pitch);
    
    // calculate front vector
    front: Vector3;
    front.x = cos(yaw_radians) * cos(pitch_radians);
    front.y = sin(pitch_radians);
    front.z = sin(yaw_radians) * cos(pitch_radians);
    camera.front = normalize(front);
    
    // calculate right and up vectors
    camera.right = normalize(cross(camera.front, camera.world_up));
    camera.up = normalize(cross(camera.right, camera.front));
}
