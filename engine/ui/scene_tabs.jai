// File:        scene_tabs.jai
// Author:      Lukáš Bien
// Description: Draws editor scene tabs and manages tab switching and close requests.

#scope_file

#import "Basic";
#import "jai-imgui";

#scope_export

scene_tabs_draw :: () {
    if BeginTabBar("viewport_scene_tabs", .Reorderable) {
        close_index: s32 = -1;

        for * tab, index: editor_context.tabs {
            open := true;
            flags: TabItemFlags = .None;
            if tab.dirty then flags |= .UnsavedDocument;
            if cast(s32) index == editor_context.requested_tab_selection_index then flags |= .SetSelected;

            label := tprint("% %###scene_tab_%", ICON_FA_FILE_LINES, tab.title, index);
            if BeginTabItem(temp_c_string(label), *open, flags) {
                if editor_context.active_tab_index != cast(s32) index {
                    editor_set_active_scene_tab(cast(s32) index, false);
                }
                EndTabItem();
            }

            if !open {
                close_index = cast(s32) index;
            }
        }

        EndTabBar();
        editor_context.requested_tab_selection_index = -1;

        if close_index >= 0 {
            editor_request_close_scene_tab(close_index);
        }
    }

    scene_tabs_draw_dirty_prompt();
}

#scope_file

scene_tabs_draw_dirty_prompt :: () {
    index := editor_context.pending_close_tab_index;
    if index < 0 then return;
    if index >= cast(s32) editor_context.tabs.count {
        editor_context.pending_close_tab_index = -1;
        return;
    }

    OpenPopup(UI_Icon_Window_Title(ICON_FA_FLOPPY_DISK, "Unsaved Scene", "Unsaved Scene"));
    if BeginPopupModal(UI_Icon_Window_Title(ICON_FA_FLOPPY_DISK, "Unsaved Scene", "Unsaved Scene"), null, .AlwaysAutoResize) {
        tab := *editor_context.tabs[index];
        TextWrapped("Save changes to % before closing?", tab.title);
        Separator();

        if Button(UI_Icon_Label(ICON_FA_FLOPPY_DISK, "Save"), ImVec2.{110, 0}) {
            editor_set_active_scene_tab(index);
            if editor_save_active_scene() {
                editor_close_scene_tab(index);
                editor_context.pending_close_tab_index = -1;
                CloseCurrentPopup();
            }
        }
        SameLine();
        if Button(UI_Icon_Label(ICON_FA_TRASH, "Discard"), ImVec2.{110, 0}) {
            editor_close_scene_tab(index);
            editor_context.pending_close_tab_index = -1;
            CloseCurrentPopup();
        }
        SameLine();
        if Button(UI_Icon_Label(ICON_FA_XMARK, "Cancel"), ImVec2.{110, 0}) {
            editor_context.pending_close_tab_index = -1;
            CloseCurrentPopup();
        }

        EndPopup();
    }
}
