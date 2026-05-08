// File:        math.jai
// Author:      Lukáš Bien
// Description: Provides core math helpers and shared numeric utilities.

#scope_file

#import "Math";

#scope_export

degrees_to_radians :: (degrees: float) -> float {
    return degrees * (PI / 180.0);
}

radians_to_degrees :: (radians: float) -> float {
    return radians * (180.0 / PI);
}

wrap_angle_pi :: (angle: float) -> float {
    result := angle;
    
    while result > PI result -= 2 * PI;
    while result <= PI result += 2 * PI;

    return result;
}

closest_angle_to_reference :: (candidate: float, reference: float) -> float {
    best := wrap_angle_pi(candidate);
    best_distance := abs(best - reference);

    for offset: -2..2 {
        test := best + cast(float) offset * 2 * PI;
        distance := abs(test - reference);
        if distance < best_distance {
            best = test;
            best_distance = distance;
        }
    }

    return best;
}

make_euler_continuous :: (candidate: Vector3, reference: Vector3) -> Vector3 {
    return .{
        closest_angle_to_reference(candidate.x, reference.x),
        closest_angle_to_reference(candidate.y, reference.y),
        closest_angle_to_reference(candidate.z, reference.z),
    };
}

quaternion_equal_rotation :: (a: Quaternion, b: Quaternion, epsilon: float = 0.000001) -> bool {
    na := a;
    nb := b;
    normalize_or_identity(*na);
    normalize_or_identity(*nb);

    d := abs(dot(na, nb));
    return 1.0 - d <= epsilon;
}
