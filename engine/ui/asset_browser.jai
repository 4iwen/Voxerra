#scope_file

#import "Basic";
#import "String";
#import "File_Utilities";
#import "Math";
#import "jai-imgui";

#scope_module

Asset_Browser_Item :: struct {
    path: string;
    name: string;
    type: Asset_Type;
    is_directory: bool;
}

Asset_Browser_State :: struct {
    items: [..] Asset_Browser_Item;
    filter_buffer: [256] u8;
    icon_size: float = 48.0;
    icon_spacing: float = 4.0;
    selected_index: s32 = -1;
    root_directory: string;
    current_directory: string;
}

asset_browser_state: Asset_Browser_State;

Asset_Browser_Layout :: struct {
    item_size: ImVec2;
    item_step: ImVec2;
    item_spacing: float;
    outer_padding: float;
    column_count: s32;
    line_count: s32;
}

#scope_export

asset_browser_init :: () {
    asset_browser_refresh();
}

asset_browser_shutdown :: () {
    asset_browser_clear();
    array_free(asset_browser_state.items);
    free(asset_browser_state.root_directory);
    free(asset_browser_state.current_directory);
    asset_browser_state.root_directory = "";
    asset_browser_state.current_directory = "";
}

asset_browser_draw :: () {
    SetNextWindowSize(ImVec2.{560, 360}, Cond.FirstUseEver);
    if Begin(UI_Icon_Window_Title(ICON_FA_FOLDER_OPEN, "Asset Browser", "Asset Browser"), null, .MenuBar) {
        asset_browser_draw_menu_bar();
        asset_browser_draw_toolbar();
        asset_browser_draw_filter();
        asset_browser_draw_grid();
    }
    End();
} @UI_Window

#scope_export

EDITOR_MODEL_ASSET_PAYLOAD :: "ENGINE_MODEL_ASSET";

editor_model_asset_drag_source :: (path: string, name: string) {
    if !path then return;

    if BeginDragDropSource() {
        payload := temp_c_string(path);
        SetDragDropPayload(
            temp_c_string(EDITOR_MODEL_ASSET_PAYLOAD),
            payload,
            cast(u64) path.count + 1
        );

        Text("Model");
        if name {
            TextUnformatted(name);
        }
        TextDisabled("%", path);

        EndDragDropSource();
    }
}

editor_accept_model_asset_drop :: () -> string {
    result: string;

    if BeginDragDropTarget() {
        payload := AcceptDragDropPayload(temp_c_string(EDITOR_MODEL_ASSET_PAYLOAD));
        if payload && payload.Delivery {
            result = editor_model_asset_payload_to_string(payload);
        }
        EndDragDropTarget();
    }

    return result;
}

editor_model_asset_payload_to_string :: (payload: *Payload) -> string {
    if !payload || !payload.Data || payload.DataSize <= 0 then return "";

    payload_count := cast(s64) payload.DataSize;
    payload_data := cast(*u8) payload.Data;
    if payload_count > 0 && payload_data[payload_count - 1] == 0 {
        payload_count -= 1;
    }

    if payload_count <= 0 then return "";

    buffer := cast(*u8) alloc(payload_count + 1,, temp);
    memcpy(buffer, payload_data, payload_count);
    buffer[payload_count] = 0;
    return string.{data = buffer, count = payload_count};
}

#scope_file

ASSET_BROWSER_MIN_ICON_SIZE :: 32.0;
ASSET_BROWSER_MAX_ICON_SIZE :: 96.0;
ASSET_BROWSER_MIN_TILE_WIDTH :: 108.0;
ASSET_BROWSER_LABEL_LINES :: 2.0;

asset_browser_draw_menu_bar :: () {
    if BeginMenuBar() {
        if MenuItem(UI_Icon_Label(ICON_FA_ARROW_ROTATE_RIGHT, "Refresh")) {
            asset_browser_refresh();
        }

        if BeginMenu("Options") {
            SeparatorText("Layout");
            PushItemWidth(180.0);
            SliderFloat("Icon Size", *asset_browser_state.icon_size, ASSET_BROWSER_MIN_ICON_SIZE, ASSET_BROWSER_MAX_ICON_SIZE, "%.0f");
            SliderFloat("Icon Spacing", *asset_browser_state.icon_spacing, 4.0, 32.0, "%.0f");
            PopItemWidth();

            EndMenu();
        }

        EndMenuBar();
    }
}

asset_browser_draw_toolbar :: () {
    can_go_up := asset_browser_can_go_up();

    BeginDisabled(!can_go_up);
    if Button(UI_Icon_Label(ICON_FA_ARROW_UP, "Up"), ImVec2.{70, 0}) {
        asset_browser_go_up();
    }
    EndDisabled();

    SameLine();
    TextDisabled("%", asset_browser_display_path());
}

asset_browser_draw_filter :: () {
    SetNextItemWidth(-1);
    InputTextWithHint(
        "##AssetFilter",
        "Filter assets",
        asset_browser_state.filter_buffer.data,
        asset_browser_state.filter_buffer.count
    );
    Separator();
}

asset_browser_draw_grid :: () {
    visible_count := asset_browser_visible_item_count();

    if BeginChild("asset_grid", ImVec2.{0, 0}, .Borders, .None) {
        if visible_count == 0 {
            TextDisabled("No assets");
        } else {
            child_avail := GetContentRegionAvail();
            layout := asset_browser_calculate_layout(child_avail.x, visible_count);
            content_height := asset_browser_content_height(layout);

            if content_height > child_avail.y {
                style := GetStyle();
                layout = asset_browser_calculate_layout(max(1.0, child_avail.x - style.ScrollbarSize), visible_count);
                content_height = asset_browser_content_height(layout);
            }

            asset_browser_draw_visible_tiles(layout, content_height);
        }

        asset_browser_handle_zoom();
    }
    EndChild();
}

asset_browser_draw_visible_tiles :: (layout: Asset_Browser_Layout, content_height: float) {
    draw_list := GetWindowDrawList();
    start_pos := GetCursorScreenPos() + ImVec2.{layout.outer_padding, layout.outer_padding};
    visible_index: s32 = 0;

    for item, item_index: asset_browser_state.items {
        if !asset_browser_item_visible(item) then continue;

        row := visible_index / layout.column_count;
        column := visible_index % layout.column_count;
        pos := start_pos + ImVec2.{
            cast(float) column * layout.item_step.x,
            cast(float) row * layout.item_step.y
        };

        SetCursorScreenPos(pos);
        PushID(item.path);

        selected := asset_browser_state.selected_index == cast(s32) item_index;
        if Selectable("##asset_tile", selected, .None, layout.item_size) {
            asset_browser_state.selected_index = cast(s32) item_index;
            selected = true;
        }

        hovered := IsItemHovered();
        if hovered && IsMouseDoubleClicked(.Left) {
            asset_browser_open_item(item);
        }

        if item.type == .MODEL && !item.is_directory {
            editor_model_asset_drag_source(item.path, item.name);
        }

        asset_browser_draw_tile(draw_list, item, pos, layout.item_size, selected, hovered);

        if BeginItemTooltip() {
            if item.is_directory {
                TextUnformatted("Folder");
            } else {
                TextUnformatted(asset_type_to_string(item.type));
            }
            TextUnformatted(item.path);
            EndTooltip();
        }

        PopID();
        visible_index += 1;
    }

    SetCursorScreenPos(start_pos + ImVec2.{0.0, content_height});
    Dummy(ImVec2.{1.0, 1.0});
}

asset_browser_draw_tile :: (
    draw_list: *ImDrawList,
    item: Asset_Browser_Item,
    pos: ImVec2,
    item_size: ImVec2,
    selected: bool,
    hovered: bool
) {
    tile_min := pos;
    tile_max := pos + item_size;

    bg_color := GetColorU32(ImVec4.{0.12, 0.12, 0.13, 0.92});
    border_color := GetColorU32(ImVec4.{0.25, 0.25, 0.27, 1.0});
    if hovered {
        bg_color = GetColorU32(ImVec4.{0.18, 0.18, 0.19, 1.0});
        border_color = GetColorU32(ImVec4.{0.55, 0.55, 0.58, 1.0});
    }
    if selected {
        bg_color = GetColorU32(ImVec4.{0.28, 0.24, 0.13, 1.0});
        border_color = GetColorU32(ImVec4.{0.90, 0.70, 0.00, 1.0});
    }

    if hovered || selected {
        ImDrawList.AddRectFilled(draw_list, tile_min, tile_max, bg_color, 5.0);
        ImDrawList.AddRect(draw_list, tile_min, tile_max, border_color, 5.0);
    }

    icon_size := asset_browser_state.icon_size;
    icon_region_min := ImVec2.{tile_min.x, tile_min.y + 8.0};
    icon_region_max := ImVec2.{tile_max.x, icon_region_min.y + icon_size};

    icon := asset_browser_icon_for_item(item);
    icon_font_size := icon_size * 0.64;
    icon_base_size := CalcTextSize(icon);
    icon_scale := icon_font_size / GetFontSize();
    icon_text_size := ImVec2.{icon_base_size.x * icon_scale, icon_base_size.y * icon_scale};
    icon_pos := ImVec2.{
        icon_region_min.x + floor(((icon_region_max.x - icon_region_min.x) - icon_text_size.x) * 0.5),
        icon_region_min.y + floor(((icon_region_max.y - icon_region_min.y) - icon_text_size.y) * 0.5)
    };
    ImDrawList.AddText(draw_list, GetFont(), icon_font_size, icon_pos, asset_browser_type_color(item), icon);

    label_pos := ImVec2.{tile_min.x + 6.0, icon_region_max.y + 7.0};
    label_clip := ImVec4.{tile_min.x + 6.0, label_pos.y, tile_max.x - 6.0, tile_max.y - 5.0};
    label_width := item_size.x - 12.0;
    label_size := CalcTextSize(item.name);
    if label_size.x < label_width {
        label_pos.x = tile_min.x + floor((item_size.x - label_size.x) * 0.5);
    }
    label_color := ifx selected then GetColorU32(Col.Text) else GetColorU32(Col.TextDisabled);
    ImDrawList.AddText(
        draw_list,
        GetFont(),
        GetFontSize(),
        label_pos,
        label_color,
        item.name,
        label_width,
        *label_clip
    );
}

asset_browser_calculate_layout :: (avail_width: float, visible_count: s32) -> Asset_Browser_Layout {
    if asset_browser_state.icon_size < ASSET_BROWSER_MIN_ICON_SIZE then asset_browser_state.icon_size = ASSET_BROWSER_MIN_ICON_SIZE;
    if asset_browser_state.icon_size > ASSET_BROWSER_MAX_ICON_SIZE then asset_browser_state.icon_size = ASSET_BROWSER_MAX_ICON_SIZE;
    if asset_browser_state.icon_spacing < 4.0 then asset_browser_state.icon_spacing = 4.0;
    if asset_browser_state.icon_spacing > 32.0 then asset_browser_state.icon_spacing = 32.0;

    icon_size := floor(asset_browser_state.icon_size);
    spacing := floor(asset_browser_state.icon_spacing);
    tile_width := icon_size + 34.0;
    if tile_width < ASSET_BROWSER_MIN_TILE_WIDTH then tile_width = ASSET_BROWSER_MIN_TILE_WIDTH;
    tile_height := icon_size + GetFontSize() * ASSET_BROWSER_LABEL_LINES + 28.0;

    columns := cast(s32) floor(avail_width / (tile_width + spacing));
    if columns < 1 then columns = 1;

    lines: s32 = 0;
    if visible_count > 0 {
        lines = (visible_count + columns - 1) / columns;
    }

    layout: Asset_Browser_Layout;
    layout.item_size = .{tile_width, tile_height};
    layout.item_step = .{tile_width + spacing, tile_height + spacing};
    layout.item_spacing = spacing;
    layout.outer_padding = floor(spacing * 0.5);
    layout.column_count = columns;
    layout.line_count = lines;
    return layout;
}

asset_browser_content_height :: (layout: Asset_Browser_Layout) -> float {
    result := layout.outer_padding * 2.0 + cast(float) layout.line_count * layout.item_step.y;
    if result < 1.0 then result = 1.0;
    return result;
}

asset_browser_handle_zoom :: () {
    io := GetIO();
    if IsWindowHovered() && io.KeyCtrl && io.MouseWheel != 0.0 && !IsAnyItemActive() {
        asset_browser_state.icon_size += io.MouseWheel * 6.0;
        if asset_browser_state.icon_size < ASSET_BROWSER_MIN_ICON_SIZE then asset_browser_state.icon_size = ASSET_BROWSER_MIN_ICON_SIZE;
        if asset_browser_state.icon_size > ASSET_BROWSER_MAX_ICON_SIZE then asset_browser_state.icon_size = ASSET_BROWSER_MAX_ICON_SIZE;
    }
}

asset_browser_visible_item_count :: () -> s32 {
    result: s32 = 0;
    for item: asset_browser_state.items {
        if asset_browser_item_visible(item) then result += 1;
    }
    return result;
}

asset_browser_ensure_directory_state :: () {
    if !asset_browser_state.root_directory {
        root := asset_browser_project_assets_root();
        root = asset_browser_strip_trailing_separator(root);
        asset_browser_state.root_directory = copy_string(root);
    }

    if !asset_browser_state.current_directory || !asset_browser_is_path_under_root(asset_browser_state.current_directory) {
        free(asset_browser_state.current_directory);
        asset_browser_state.current_directory = copy_string(asset_browser_state.root_directory);
    }
}

asset_browser_project_assets_root :: () -> string {
    project_root := editor_context.project_asset_root;
    if !project_root then project_root = "game";

    if ends_with(project_root, "/assets") || ends_with(project_root, "\\assets") {
        return project_root;
    }

    candidate := path_join(project_root, "assets");
    is_dir, ok := is_directory(candidate);
    if ok && is_dir {
        return candidate;
    }

    return project_root;
}

asset_browser_strip_trailing_separator :: (path: string) -> string {
    result := path;
    while result.count > 1 {
        last := result[result.count - 1];
        if last != #char "/" && last != #char "\\" then break;
        result.count -= 1;
    }
    return result;
}

asset_browser_is_path_under_root :: (path: string) -> bool {
    root := asset_browser_state.root_directory;
    if !root || !path then return false;
    if path == root then return true;
    if path.count <= root.count then return false;
    if !begins_with(path, root) then return false;

    separator := path[root.count];
    return separator == #char "/" || separator == #char "\\";
}

asset_browser_can_go_up :: () -> bool {
    current := asset_browser_state.current_directory;
    root := asset_browser_state.root_directory;
    if !current || !root then return false;
    if current == root then return false;
    return asset_browser_is_path_under_root(current);
}

asset_browser_go_up :: () {
    if !asset_browser_can_go_up() then return;

    parent := asset_browser_parent_directory(asset_browser_state.current_directory);
    if !parent || !asset_browser_is_path_under_root(parent) {
        parent = asset_browser_state.root_directory;
    }

    asset_browser_enter_directory(parent);
}

asset_browser_enter_directory :: (path: string) {
    if !path then return;
    normalized := asset_browser_strip_trailing_separator(path);
    if !asset_browser_is_path_under_root(normalized) then return;

    is_dir, ok := is_directory(normalized);
    if !ok || !is_dir then return;

    if asset_browser_state.current_directory == normalized then return;

    free(asset_browser_state.current_directory);
    asset_browser_state.current_directory = copy_string(normalized);
    asset_browser_refresh();
}

asset_browser_parent_directory :: (path: string) -> string {
    end := path.count;
    while end > 0 {
        last := path[end - 1];
        if last != #char "/" && last != #char "\\" then break;
        end -= 1;
    }

    if end <= 0 then return "";

    index := end - 1;
    while index >= 0 {
        c := path[index];
        if c == #char "/" || c == #char "\\" {
            if index == 0 then return slice(path, 0, 1);
            return slice(path, 0, index);
        }
        index -= 1;
    }

    return "";
}

asset_browser_display_path :: () -> string {
    root := asset_browser_state.root_directory;
    current := asset_browser_state.current_directory;
    if !root || !current then return "assets";
    if current == root then return "assets";

    relative := advance(current, root.count);
    while relative.count > 0 {
        c := relative[0];
        if c != #char "/" && c != #char "\\" then break;
        relative = advance(relative, 1);
    }

    if !relative then return "assets";
    return tprint("assets/%", relative);
}

asset_browser_sort_items :: () {
    quick_sort(asset_browser_state.items, asset_browser_compare_items);
}

asset_browser_compare_items :: (a: Asset_Browser_Item, b: Asset_Browser_Item) -> int {
    if a.is_directory && !b.is_directory then return -1;
    if !a.is_directory && b.is_directory then return 1;
    return compare_nocase(a.name, b.name);
}

asset_browser_refresh :: () {
    asset_browser_ensure_directory_state();
    asset_browser_clear();
    asset_browser_state.selected_index = -1;

    visitor :: (info: *File_Visit_Info, items: *[..] Asset_Browser_Item) {
        item: Asset_Browser_Item;

        if info.is_directory {
            item.path = copy_string(info.full_name);
            item.name = copy_string(info.short_name);
            item.type = .UNKNOWN;
            item.is_directory = true;
            array_add(items, item);
            return;
        }

        if asset_browser_should_skip(info.full_name) then return;

        item.path = copy_string(info.full_name);
        item.name = copy_string(info.short_name);
        item.type = asset_browser_type_for_path(info.full_name);
        item.is_directory = false;
        array_add(items, item);
    }

    visit_files(
        asset_browser_state.current_directory,
        recursive = false,
        *asset_browser_state.items,
        visitor,
        visit_files = true,
        visit_directories = true
    );

    asset_browser_sort_items();
}

asset_browser_clear :: () {
    for item: asset_browser_state.items {
        free(item.path);
        free(item.name);
    }
    array_reset(*asset_browser_state.items);
}

asset_browser_should_skip :: (path: string) -> bool {
    extension, found := path_extension(path);
    if found && extension == "meta" then return true;
    if path == PROJECT_DESCRIPTOR_PATH then return true;
    if contains(path, ".DS_Store") then return true;
    return false;
}

asset_browser_type_for_path :: (path: string) -> Asset_Type {
    extension, found := path_extension(path);
    if !found then return .UNKNOWN;

    if extension == "toml" {
        if contains(path, "/scenes/") || contains(path, ".scene.") {
            return .SCENE;
        }
        return .UNKNOWN;
    }

    return asset_type_from_path(path);
}

asset_browser_icon_for_type :: (type: Asset_Type) -> string {
    if type == .SCENE then return ICON_FA_FILE_LINES;
    if type == .MODEL then return ICON_FA_CUBE;
    if type == .TEXTURE then return ICON_FA_FILE_IMAGE;
    if type == .SHADER then return ICON_FA_FILE_CODE;
    if type == .CUBEMAP then return ICON_FA_BOX;
    return ICON_FA_FILE;
}

asset_browser_icon_for_item :: (item: Asset_Browser_Item) -> string {
    if item.is_directory then return ICON_FA_FOLDER;
    return asset_browser_icon_for_type(item.type);
}

asset_browser_type_color :: (item: Asset_Browser_Item) -> ImU32 {
    if item.is_directory then return GetColorU32(ImVec4.{0.95, 0.72, 0.24, 1.0});

    type := item.type;
    if type == .SCENE then return GetColorU32(ImVec4.{0.38, 0.82, 0.48, 1.0});
    if type == .MODEL then return GetColorU32(ImVec4.{0.42, 0.68, 1.00, 1.0});
    if type == .TEXTURE then return GetColorU32(ImVec4.{0.90, 0.58, 1.00, 1.0});
    if type == .SHADER then return GetColorU32(ImVec4.{1.00, 0.72, 0.36, 1.0});
    if type == .CUBEMAP then return GetColorU32(ImVec4.{0.55, 0.78, 0.82, 1.0});
    return GetColorU32(Col.TextDisabled);
}

asset_browser_item_visible :: (item: Asset_Browser_Item) -> bool {
    filter := to_string(asset_browser_state.filter_buffer.data);
    if filter.count == 0 then return true;
    if contains_nocase(item.name, filter) then return true;
    if contains_nocase(item.path, filter) then return true;
    if item.is_directory && contains_nocase("folder", filter) then return true;
    if contains_nocase(asset_type_to_string(item.type), filter) then return true;
    return false;
}

asset_browser_open_item :: (item: Asset_Browser_Item) {
    if item.is_directory {
        asset_browser_enter_directory(item.path);
        return;
    }

    if item.type == .SCENE {
        editor_open_scene_tab(item.path);
        return;
    }

    if item.type == .UNKNOWN {
        log("Asset file: %", item.path);
        return;
    }

    metadata := asset_manager_ensure_metadata(item.path, item.type);
    log("Asset: % [%]", metadata.path, metadata.guid);
}
