#scope_file

#import "String";
#import "Hash_Table";

#scope_module

properties_init :: () {
}

properties_shutdown :: () {
    for entry, key: ui_cache {
        free(key);
        free(entry.label);
    }

    deinit(*ui_cache);
}

node_name_edit_runtime_id: u64;
node_name_edit_buffer: [256] u8;

properties_draw :: () {
    SetNextWindowSize(ImVec2.{300, 0}, Cond.FirstUseEver);

    if Begin("Node Properties") {
        if selected_node != null {
            draw_node_identity(selected_node);
            Separator();
            draw_transform_component(selected_node);

            if selected_node.instance_path {
                draw_scene_instance_properties(selected_node);
            } else {
                removed_component: *Component = null;
                for component: selected_node.components {
                    if ui_draw_component(component) {
                        removed_component = component;
                    }
                }

                if removed_component != null {
                    node_remove_component(selected_node, removed_component);
                    editor_mark_current_scene_dirty();
                }

                Separator();
                Dummy(ImVec2.{0, 10});

                if Button("Add Component", ImVec2.{-1, 24}) {
                    OpenPopup("AddComponentPopup");
                }

                if BeginPopup("AddComponentPopup") {
                    #insert -> string {
                        builder: String_Builder;
                        for component: ui_available_components {
                            name := component;
                            display_name := ui_format_label(name);
                            print_to_builder(*builder, "if node_get_component(selected_node, %) == null {\n", component);
                            print_to_builder(*builder, "    if Selectable(\"%\") {\n", display_name);
                            print_to_builder(*builder, "        node_add_component(selected_node, %);\n", component);
                            print_to_builder(*builder, "        editor_mark_current_scene_dirty();\n");
                            print_to_builder(*builder, "    }\n");
                            print_to_builder(*builder, "}\n");
                        }
                        return builder_to_string(*builder);
                    };
                    EndPopup();
                }
            }
        } else {
            TextDisabled("No node selected");
        }
    }

    End();
} @UI_Window

draw_node_identity :: (node: *Node) {
    if !node then return;

    if node_name_edit_runtime_id != node.runtime_id {
        node_name_edit_runtime_id = node.runtime_id;
        ui_copy_string_to_buffer(node.name, node_name_edit_buffer.data, node_name_edit_buffer.count);
    }

    if BeginTable("node_identity_table", 2, TABLE_FLAGS, ImVec2.{0, 0}) {
        TableSetupColumn("Name", .WidthFixed, 0.0);
        TableSetupColumn("Value", .WidthStretch, 0.0);

        TableNextRow();
        TableNextColumn();
        AlignTextToFramePadding();
        Text("Name");

        TableNextColumn();
        PushItemWidth(-1);
        if InputText("##node_name", node_name_edit_buffer.data, node_name_edit_buffer.count) {
            editor_rename_node(node, to_string(node_name_edit_buffer.data));
        }
        PopItemWidth();

        EndTable();
    }
}

draw_scene_instance_properties :: (node: *Node) {
    if !node || !node.instance_path then return;

    if CollapsingHeader("Scene Instance", COLLAPSING_HEADER_FLAGS) {
        TextDisabled("Source Scene");
        TextWrapped("%", node.instance_path);

        if Button("Open Source Scene", ImVec2.{-1, 24}) {
            editor_open_scene(node.instance_path);
        }
    }
}

ui_draw_component :: (component: *Component) -> bool {
    if !component then return false;
    if component.type == Static_Mesh_Component then return false;

    information := cast(*Type_Info) component.type;
    if information.type != .STRUCT then return false;

    struct_info := cast(*Type_Info_Struct) information;
    name := struct_info.name;

    visible := true;
    if CollapsingHeader(temp_c_string(ui_format_label(name)), *visible, COLLAPSING_HEADER_FLAGS) {
        PushID(cast(*void) component);

        if BeginTable(temp_c_string(tprint("%_table", struct_info.name)), 2, TABLE_FLAGS, ImVec2.{0, 0}) {
            TableSetupColumn("Name", .WidthFixed, 0.0);
            TableSetupColumn("Value", .WidthStretch, 0.0);
            ui_draw_struct_fields(cast(*void) component, struct_info, true);
            EndTable();
        }

        if component.type == Model_Component {
            draw_model_component_materials(cast(*Model_Component) component);
        }

        PopID();
    }

    return !visible;
}

// hide fields that do not apply
should_skip_field :: (struct_info: *Type_Info_Struct, member: Type_Info_Struct_Member, data: *void) -> bool {
    if struct_info.name == "Light" {
        light := cast(*Light) data;
        if member.name == "range"     && light.type == .Directional  then return true;
        if member.name == "inner_cos" && light.type != .Spot         then return true;
        if member.name == "outer_cos" && light.type != .Spot         then return true;
    }
    if struct_info.name == "Scene" {
        if member.name == "camera" || member.name == "lights" || member.name == "source_path" then return true;
    }
    if struct_info.name == "Camera" {
        if member.name == "position" then return true;
        if member.name == "front" then return true;
        if member.name == "up" then return true;
        if member.name == "right" then return true;
        if member.name == "world_up" then return true;
    }
    if struct_info.name == "Model_Component" {
        if member.name == "base" then return true;
        if member.name == "model_resource" then return true;
        if member.name == "model_local_matrix" then return true;
        if member.name == "material_overrides" then return true;
    }
    if struct_info.name == "Sprite_Component" {
        if member.name == "component" then return true;
        if member.name == "texture" then return true;
        if member.name == "shader" then return true;
        if member.name == "uv_transform" then return true;
        if member.name == "render_matrix" then return true;
    }
    if struct_info.name == "Animated_Sprite_Component" {
        if member.name == "base" then return true;
        if member.name == "current_frame" then return true;
        if member.name == "frame_accumulator" then return true;
    }
    return false;
}

draw_field_integer :: (member: *Type_Info_Struct_Member, meta: UI_Field_Metadata, field_pointer: *void, hidden_label: *u8) {
    if member.type.runtime_size == 4 {
        DragInt(hidden_label, cast(*s32) field_pointer, meta.speed_int, meta.int_range_min, meta.int_range_max);
    } else if member.type.runtime_size == 8 {
        v := cast(s32) (cast(*s64) field_pointer).*;
        if DragInt(hidden_label, *v, meta.speed_int, meta.int_range_min, meta.int_range_max) {
            (cast(*s64) field_pointer).* = cast(s64) v;
        }
    } else {
        TextDisabled(tprint("(unsupported int size: %)", member.type.runtime_size));
    }
}

draw_field_float :: (member: *Type_Info_Struct_Member, meta: UI_Field_Metadata, field_pointer: *void, hidden_label: *u8) {
    if member.type.runtime_size == 4 {
        DragFloat(hidden_label, cast(*float) field_pointer, meta.speed, meta.range_min, meta.range_max);
    } else {
        TextDisabled(tprint("(unsupported float size: %)", member.type.runtime_size));
    }
}

draw_field_bool :: (member: *Type_Info_Struct_Member, field_pointer: *void, hidden_label: *u8) {
    Checkbox(hidden_label, cast(*bool) field_pointer);
}

draw_field_string :: (member: *Type_Info_Struct_Member, field_pointer: *void) {
    TextDisabled(tprint("%", (cast(*string) field_pointer).*));
}

draw_model_component_model_field :: (model_component: *Model_Component) {
    label := ifx model_component.model_path then model_component.model_path else "Drop model here";
    Selectable(temp_c_string(tprint("%##model_component_model_drop", label)), false, .None, ImVec2.{0, 0});

    dropped_path := editor_accept_model_asset_drop();
    if dropped_path {
        if scene_set_model_component_model(model_component, dropped_path) {
            editor_mark_current_scene_dirty();
        }
    }
}

draw_model_component_materials :: (model_component: *Model_Component) {
    if !model_component || !model_component.model_resource then return;

    if !CollapsingHeader("Materials", COLLAPSING_HEADER_FLAGS) {
        return;
    }

    model := model_component.model_resource;
    if model.materials.count == 0 {
        TextDisabled("No imported materials");
        return;
    }

    for material: model.materials {
        material_index := cast(s32) it_index;
        material_name := ifx material.name.count > 0 then material.name else tprint("Material %", material_index);
        override := model_component_find_material_override(model_component, material_index);
        has_override := override != null;

        PushID(material_index);
        if BeginTable("model_material_table", 2, TABLE_FLAGS, ImVec2.{0, 0}) {
            TableSetupColumn("Name", .WidthFixed, 0.0);
            TableSetupColumn("Value", .WidthStretch, 0.0);

            TableNextRow();
            TableNextColumn();
            AlignTextToFramePadding();
            TextUnformatted(material_name);
            TableNextColumn();
            if Checkbox("Override##material_override", *has_override) {
                if has_override {
                    model_component_ensure_material_override(model_component, material_index, material);
                } else {
                    model_component_remove_material_override(model_component, material_index);
                }
                editor_mark_current_scene_dirty();
            }

            override = model_component_find_material_override(model_component, material_index);
            if override {
                draw_model_material_override_fields(override, material);
            }

            EndTable();
        }
        PopID();
    }
}

draw_model_material_override_fields :: (
    override: *Model_Material_Override,
    source_material: *Material
) {
    TableNextRow();
    TableNextColumn();
    AlignTextToFramePadding();
    Text("Tint");
    TableNextColumn();
    PushItemWidth(-1);
    if ColorEdit3("##override_tint", cast(*[3] float) *override.tint_color.x) {
        editor_mark_current_scene_dirty();
    }
    PopItemWidth();

    TableNextRow();
    TableNextColumn();
    AlignTextToFramePadding();
    Text("Alpha");
    TableNextColumn();
    PushItemWidth(-1);
    if DragFloat("##override_alpha", *override.alpha, 0.01, 0.0, 1.0) {
        editor_mark_current_scene_dirty();
    }
    PopItemWidth();

    TableNextRow();
    TableNextColumn();
    AlignTextToFramePadding();
    Text("Blend Mode");
    TableNextColumn();
    PushItemWidth(-1);
    if draw_blend_mode_combo("##override_blend_mode", *override.blend_mode) {
        editor_mark_current_scene_dirty();
    }
    PopItemWidth();

    if override.blend_mode == .ALPHA_CLIP {
        TableNextRow();
        TableNextColumn();
        AlignTextToFramePadding();
        Text("Alpha Cutoff");
        TableNextColumn();
        PushItemWidth(-1);
        if DragFloat("##override_alpha_cutoff", *override.alpha_cutoff, 0.01, 0.0, 1.0) {
            editor_mark_current_scene_dirty();
        }
        PopItemWidth();
    }

    TableNextRow();
    TableNextColumn();
    AlignTextToFramePadding();
    Text("Double Sided");
    TableNextColumn();
    if Checkbox("##override_double_sided", *override.double_sided) {
        editor_mark_current_scene_dirty();
    }

    if source_material {
        TableNextRow();
        TableNextColumn();
        TableNextColumn();
        if Button("Reset From Source", ImVec2.{-1, 22}) {
            override.* = model_material_override_from_material(override.material_index, source_material);
            editor_mark_current_scene_dirty();
        }
    }
}

draw_blend_mode_combo :: (hidden_label: *u8, value: *Blend_Mode) -> bool {
    names := NewArray(3, *u8,, temp);
    names[0] = "Opaque\0".data;
    names[1] = "Alpha Clip\0".data;
    names[2] = "Alpha Blend\0".data;

    current_index := cast(s32) value.*;
    changed := Combo(hidden_label, *current_index, names.data, cast(s32) names.count);
    if changed {
        value.* = cast(Blend_Mode) current_index;
    }

    return changed;
}

// asset combo item
Asset_Combo_Item :: struct {
    name: string;
    ptr:  *void;
}

// asset picker
draw_asset_combo :: (hidden_label: *u8, current_ptr: **void, items: [] Asset_Combo_Item) {
    total := items.count + 1; // +1 for none
    c_names := cast(**u8) alloc(size_of(*u8) * total,, temp);
    c_names[0] = "None\0".data;

    // sync combo with pointer
    current_index: s32 = 0;
    for items {
        c_names[it_index + 1] = temp_c_string(it.name);
        if it.ptr == current_ptr.* then current_index = cast(s32) it_index + 1;
    }

    if Combo(hidden_label, *current_index, c_names, cast(s32) total) {
        current_ptr.* = ifx current_index > 0 then items[current_index - 1].ptr else null;
    }
}

draw_field_pointer :: (member: *Type_Info_Struct_Member, field_pointer: *void, hidden_label: *u8) {
    current_ptr  := cast(**void) field_pointer;
    pointer_info := cast(*Type_Info_Pointer) member.type;

    if pointer_info.pointer_to.type != .STRUCT {
        TextDisabled(tprint("%", ifx current_ptr.* then "Loaded" else "None"));
        return;
    }

    s_info := cast(*Type_Info_Struct) pointer_info.pointer_to;

    if s_info.name == "Texture" {
        textures := asset_manager_get_textures();
        items := NewArray(textures.count, Asset_Combo_Item,, temp);
        i := 0;
        for textures {
            items[i] = .{ name = path_filename(it.path), ptr = it.texture };
            i += 1;
        }
        draw_asset_combo(hidden_label, current_ptr, items);

    } else if s_info.name == "Mesh" {
        models := asset_manager_get_models();
        total_meshes := 0;
        for models total_meshes += it.model.submeshes.count;
        items := NewArray(total_meshes, Asset_Combo_Item,, temp);
        i := 0;
        for models {
            m_name := path_filename(it.model.name);
            for j: 0..it.model.submeshes.count-1 {
                sm := it.model.submeshes[j];
                items[i] = .{ name = tprint("[%] [%]", m_name, j), ptr = sm.mesh };
                i += 1;
            }
        }
        draw_asset_combo(hidden_label, current_ptr, items);

    } else if s_info.name == "Shader" {
        shaders := asset_manager_get_shaders();
        items := NewArray(shaders.count, Asset_Combo_Item,, temp);
        i := 0;
        for shaders {
            items[i] = .{ name = path_filename(it.vertex_path), ptr = it.shader };
            i += 1;
        }
        draw_asset_combo(hidden_label, current_ptr, items);

    } else if s_info.name == "Material" {
        models := asset_manager_get_models();
        total_mats := 0;
        for models total_mats += it.model.materials.count;
        items := NewArray(total_mats, Asset_Combo_Item,, temp);
        i := 0;
        for models {
            m_name := path_filename(it.model.name);
            for material: it.model.materials {
                mat_name := ifx material.name.count > 0 then material.name else "Unnamed";
                items[i] = .{ name = tprint("[%] %", m_name, mat_name), ptr = material };
                i += 1;
            }
        }
        draw_asset_combo(hidden_label, current_ptr, items);

    } else {
        TextDisabled(tprint("%", ifx current_ptr.* then "Loaded" else "None"));
    }
}

draw_field_enum :: (member: *Type_Info_Struct_Member, field_pointer: *void, hidden_label: *u8) {
    enum_info   := cast(*Type_Info_Enum) member.type;
    items_count := enum_info.names.count;
    c_names     := cast(**u8) alloc(size_of(*u8) * items_count,, temp);
    for enum_info.names c_names[it_index] = temp_c_string(ui_format_label(it));

    if enum_info.internal_type.runtime_size == 4 {
        value := (cast(*s32) field_pointer).*;
        current_index: s32 = 0;
        for enum_info.values {
            if it == value { current_index = cast(s32) it_index; break; }
        }
        if Combo(hidden_label, *current_index, c_names, cast(s32) items_count) {
            (cast(*s32) field_pointer).* = cast(s32) enum_info.values[current_index];
        }
    } else if enum_info.internal_type.runtime_size == 8 {
        value := (cast(*s64) field_pointer).*;
        current_index: s32 = 0;
        for enum_info.values {
            if it == value { current_index = cast(s32) it_index; break; }
        }
        if Combo(hidden_label, *current_index, c_names, cast(s32) items_count) {
            (cast(*s64) field_pointer).* = enum_info.values[current_index];
        }
    } else {
        TextDisabled(tprint("(unsupported enum size: %)", enum_info.internal_type.runtime_size));
    }
}

draw_field_struct :: (member: *Type_Info_Struct_Member, meta: UI_Field_Metadata, field_pointer: *void, hidden_label: *u8, tree_open: bool) {
    s_info := cast(*Type_Info_Struct) member.type;
    if s_info.name == "Vector2" {
        DragFloat2(hidden_label, cast(*[2]float) field_pointer, meta.speed, meta.range_min, meta.range_max);
    } else if s_info.name == "Vector3" {
        if meta.is_color {
            ColorEdit3(hidden_label, cast(*[3]float) field_pointer);
        } else {
            draw_vec3_control(member.name, cast(*Vector3) field_pointer, meta.speed, meta.range_min, meta.range_max, .{0,0,0}, false);
        }
    } else if s_info.name == "Quaternion" {
        draw_rotation_control(member.name, cast(*Quaternion) field_pointer, meta.speed, meta.range_min, meta.range_max, .{0,0,0}, false);
    } else if s_info.name == "Vector4" {
        TextDisabled("(Vector4)");
    } else {
        if tree_open {
            ui_draw_struct_fields(field_pointer, s_info, false);
            TreePop();
        }
    }
}

ui_draw_struct_fields :: (data: *void, struct_info: *Type_Info_Struct, is_top_level: bool = false) {
    for member: struct_info.members {
        if is_top_level {
            if member.name == "type" || member.name == "node" then continue;
            if member.name == "base" {
                if struct_info.name == "Animated_Sprite_Component" && member.type.type == .STRUCT {
                    s_info := cast(*Type_Info_Struct) member.type;
                    field_pointer := data + member.offset_in_bytes;
                    ui_draw_struct_fields(field_pointer, s_info, false);
                }
                continue;
            }
        }

        cache_key := tprint("%_%", struct_info.name, member.name);
        found, entry := table_find(*ui_cache, cache_key);
        if !found {
            new_entry: UI_Cache_Entry;
            new_entry.label = copy_string(ui_format_label(member.name));
            new_entry.meta  = parse_ui_notes(member.notes);
            table_add(*ui_cache, copy_string(cache_key), new_entry);
            entry = new_entry;
        }

        meta         := entry.meta;
        label_string := entry.label;

        if meta.is_hidden then continue;
        if should_skip_field(struct_info, member, data) then continue;

        field_pointer := data + member.offset_in_bytes;

        // flatten inline structs
        if member.type.type == .STRUCT {
            s_info   := cast(*Type_Info_Struct) member.type;
            is_simple := s_info.name == "Vector2" || s_info.name == "Vector3" ||
                         s_info.name == "Vector4"  || s_info.name == "Quaternion";
            if !is_simple && meta.is_inline {
                ui_draw_struct_fields(field_pointer, s_info, false);
                continue;
            }
        }

        label        := temp_c_string(label_string);
        hidden_label := temp_c_string(tprint("##%", member.name));

        TableNextRow();
        TableNextColumn();
        AlignTextToFramePadding();

        is_struct_tree := false;
        open           := false;

        if member.type.type == .STRUCT {
            s_info   := cast(*Type_Info_Struct) member.type;
            is_simple := s_info.name == "Vector2" || s_info.name == "Vector3" ||
                         s_info.name == "Vector4"  || s_info.name == "Quaternion";
            if !is_simple {
                is_struct_tree = true;
                open = TreeNodeEx(label, .DefaultOpen);
            }
        }

        if !is_struct_tree then Text(label_string);

        if meta.tooltip.count > 0 {
            if BeginItemTooltip() {
                TextUnformatted(meta.tooltip);
                EndTooltip();
            }
        }

        TableNextColumn();
        PushItemWidth(-1);

        if struct_info.name == "Model_Component" && member.name == "model_path" {
            draw_model_component_model_field(cast(*Model_Component) data);
        } else {
            if member.type.type == {
                case .INTEGER; draw_field_integer(*member, meta, field_pointer, hidden_label);
                case .FLOAT;   draw_field_float(*member, meta, field_pointer, hidden_label);
                case .BOOL;    draw_field_bool(*member, field_pointer, hidden_label);
                case .STRING;  draw_field_string(*member, field_pointer);
                case .POINTER; draw_field_pointer(*member, field_pointer, hidden_label);
                case .ENUM;    draw_field_enum(*member, field_pointer, hidden_label);
                case .STRUCT;  draw_field_struct(*member, meta, field_pointer, hidden_label, open);
                case;          TextDisabled(tprint("(unimplemented edit for field %)", member.type.type));
            }
        }

        if IsItemEdited() {
            editor_mark_current_scene_dirty();
        }

        PopItemWidth();
    }
}

UI_Cache_Entry :: struct {
    label: string;
    meta:  UI_Field_Metadata;
}

ui_cache: Table(string, UI_Cache_Entry);

UI_Field_Metadata :: struct {
    speed:         float  = 0.1;
    speed_int:     float  = 1.0;
    has_range:     bool   = false;
    range_min:     float  = -FLOAT32_MAX;
    range_max:     float  =  FLOAT32_MAX;
    int_range_min: s32    = -2147483647;
    int_range_max: s32    =  2147483647;
    tooltip:       string = "";
    is_color:      bool   = false;
    is_hidden:     bool   = false;
    is_inline:     bool   = false;
}

parse_ui_notes :: (notes: [] string) -> UI_Field_Metadata {
    meta: UI_Field_Metadata;
    for note: notes {
        if note == "Color"  then meta.is_color  = true;
        if note == "Hidden" then meta.is_hidden = true;
        if note == "Inline" then meta.is_inline = true;

        if begins_with(note, "Speed(") {
            inner := slice(note, 6, note.count - 7);
            value, ok := string_to_float(inner);
            if ok {
                meta.speed     = value;
                meta.speed_int = value;
            }
        }

        if begins_with(note, "Range(") {
            inner := slice(note, 6, note.count - 7);
            parts := split(inner, ",");
            if parts.count >= 2 {
                min_val, ok1 := string_to_float(trim(parts[0]));
                max_val, ok2 := string_to_float(trim(parts[1]));
                if ok1 && ok2 {
                    meta.has_range     = true;
                    meta.range_min     = min_val;
                    meta.range_max     = max_val;
                    meta.int_range_min = cast(s32) min_val;
                    meta.int_range_max = cast(s32) max_val;
                }
            }
        }

        if begins_with(note, "Tooltip(\"") {
            inner := slice(note, 9, note.count - 11);
            meta.tooltip = inner;
        }
    }
    return meta;
}

ui_copy_string_to_buffer :: (value: string, buffer: *u8, buffer_count: s64) {
    if !buffer || buffer_count <= 0 then return;

    for i: 0..buffer_count-1 {
        buffer[i] = 0;
    }

    if !value then return;
    copy_count := min(value.count, buffer_count - 1);
    for i: 0..copy_count-1 {
        buffer[i] = value[i];
    }
}

ui_format_label :: (s: string) -> string {
    if s.count == 0 then return s;

    push_allocator(temp);
    result: string;
    result.count = s.count;
    result.data  = alloc(s.count);

    // capitalize after underscores
    capitalize_next := true;
    for i: 0..s.count-1 {
        c := s[i];
        if c == #char "_" {
            result.data[i] = #char " ";
            capitalize_next = true;
        } else {
            if capitalize_next && c >= #char "a" && c <= #char "z" {
                result.data[i] = c - 32;
            } else if !capitalize_next && c >= #char "A" && c <= #char "Z" {
                result.data[i] = c + 32;
            } else {
                result.data[i] = c;
            }
            capitalize_next = false;
        }
    }
    return result;
}
