#scope_file

#import "Math";

#scope_export

degrees_to_radians :: (degrees: float) -> float {
    return degrees * (PI / 180.0);
}

radians_to_degrees :: (radians: float) -> float {
    return radians * (180.0 / PI);
}
