#scope_file

#import "Basic";
#import "String";
#import "File_Utilities";
#import "jai-imgui";

#scope_module

Asset_Browser_Item :: struct {
    path: string;
    name: string;
    type: Asset_Type;
}

Asset_Browser_State :: struct {
    items: [..] Asset_Browser_Item;
    filter_buffer: [256] u8;
}

asset_browser_state: Asset_Browser_State;

#scope_export

asset_browser_init :: () {
    asset_browser_refresh();
}

asset_browser_shutdown :: () {
    asset_browser_clear();
    array_free(asset_browser_state.items);
}

asset_browser_draw :: () {
    if Begin("Asset Browser") {
        if Button("Refresh", ImVec2.{90, 0}) {
            asset_browser_refresh();
        }
        SameLine();
        SetNextItemWidth(-1);
        InputTextWithHint(
            "##AssetFilter",
            "Filter assets",
            asset_browser_state.filter_buffer.data,
            asset_browser_state.filter_buffer.count
        );

        Separator();

        if BeginChild("asset_list", ImVec2.{0, 0}, .FrameStyle) {
            for item: asset_browser_state.items {
                if !asset_browser_item_visible(item) then continue;

                label := tprint("[%] %###asset_%", asset_type_to_string(item.type), item.name, item.path);
                if Selectable(temp_c_string(label)) {
                }
                if IsItemHovered() && IsMouseDoubleClicked(.Left) {
                    asset_browser_open_item(item);
                }
                if item.type == .MODEL {
                    editor_model_asset_drag_source(item.path, item.name);
                }
                if BeginItemTooltip() {
                    TextUnformatted(item.path);
                    EndTooltip();
                }
            }
        }
        EndChild();
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

asset_browser_refresh :: () {
    asset_browser_clear();

    root := editor_context.project_asset_root;
    if !root then root = "game";

    files := file_list(root, recursive = true);
    defer {
        for files free(it);
        array_free(files);
    }

    for file_path: files {
        if asset_browser_should_skip(file_path) then continue;

        type := asset_browser_type_for_path(file_path);
        if type == .UNKNOWN then continue;

        item: Asset_Browser_Item;
        item.path = copy_string(file_path);
        item.name = copy_string(path_filename(file_path));
        item.type = type;
        array_add(*asset_browser_state.items, item);
    }
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

asset_browser_item_visible :: (item: Asset_Browser_Item) -> bool {
    filter := to_string(asset_browser_state.filter_buffer.data);
    if filter.count == 0 then return true;
    if contains_nocase(item.name, filter) then return true;
    if contains_nocase(item.path, filter) then return true;
    if contains_nocase(asset_type_to_string(item.type), filter) then return true;
    return false;
}

asset_browser_open_item :: (item: Asset_Browser_Item) {
    if item.type == .SCENE {
        editor_open_scene_tab(item.path);
        return;
    }

    metadata := asset_manager_ensure_metadata(item.path, item.type);
    log("Asset: % [%]", metadata.path, metadata.guid);
}
