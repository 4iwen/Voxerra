properties_draw :: () {
    SetNextWindowSize(ImVec2.{300, 0}, Cond.FirstUseEver);

    if Begin("Properties") {
        if selected_node != null {
            draw_transform_component();

            // components
            mesh_comp := node_get_component(selected_node, Static_Mesh_Component);
            if mesh_comp != null {
                Separator();
                Text("Static Mesh Component");
                TextDisabled(tprint("Mesh: %", ifx mesh_comp.mesh then "Loaded" else "None"));
                TextDisabled(tprint("Material: %", ifx mesh_comp.material then "Loaded" else "None"));
            }

            light_comp := node_get_component(selected_node, Light_Component);
            if light_comp != null {
                Separator();
                Text("Light Component");
                // color
                ColorEdit3("Color", *light_comp.light.color.component);
                // intensity
                DragFloat("Intensity", *light_comp.light.intensity, 0.1, 0.0, 100.0);
                
                if light_comp.light.type == .Point || light_comp.light.type == .Spot {
                    DragFloat("Range", *light_comp.light.range, 0.5, 0.1, 1000.0);
                }

                TextDisabled(tprint("Light Type: %", light_comp.light.type));
            }
        } else {
            TextDisabled("No node selected");
        }
    }

    End();
} @UI_Window
