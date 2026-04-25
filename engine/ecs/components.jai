#scope_export
#import "Basic";
#import "Math";

Component :: struct {
    type: Type;
    node: *Node;
}

Static_Mesh_Component :: struct @Component {
    #as using base: Component;
    base.type = Static_Mesh_Component;
    
    mesh: *Mesh; @"Tooltip(\"The 3D mesh to render for this object\")"
    material: *Material; @"Tooltip(\"The material used to render the mesh\")"
}

Light_Component :: struct @Component {
    #as using base: Component;
    base.type = Light_Component;
    
    light: Light; @Inline
}

Camera_Component :: struct @Component {
    #as using base: Component;
    base.type = Camera_Component;

    camera: Camera; @Inline
}

component_clone :: (
    component: *Component,
    node: *Node,
    active_camera_source: *Camera = null,
    active_camera_result: **Camera = null
) -> *Component {
    if !component || !node then return null;

    if component.type == Static_Mesh_Component {
        source := cast(*Static_Mesh_Component) component;
        clone := node_add_component(node, Static_Mesh_Component);
        clone.mesh = source.mesh;
        clone.material = source.material;
        return cast(*Component) clone;
    }

    if component.type == Light_Component {
        source := cast(*Light_Component) component;
        clone := node_add_component(node, Light_Component);
        clone.light = source.light;
        return cast(*Component) clone;
    }

    if component.type == Camera_Component {
        source := cast(*Camera_Component) component;
        clone := node_add_component(node, Camera_Component);
        clone.camera = source.camera;
        if active_camera_source && active_camera_result && active_camera_source == *source.camera {
            active_camera_result.* = *clone.camera;
        }
        return cast(*Component) clone;
    }

    return null;
}
