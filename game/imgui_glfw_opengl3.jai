// translated glfw/opengl3 backend from imgui repo
// contains semi-evaluated conditional compilation for opengl 3.3 and glfw 3.4

// @ToDo: convert to my naming convention, hook up to my engine backend 

#import "Basic";
#import "String";
#import "Math";
#import "GL";
#import "glfw";
ImGui :: #import "jai-imgui";
for_expansion :: ImGui.for_expansion;
operator [] :: ImGui.operator [];

#if OS == .WINDOWS {
    #import "Windows";

    // put these here to avoid modifying the Windows.jai module
    SetPropA :: (hwnd: HWND, name: *u8, data: *void) -> BOOL #foreign user32;
    GetPropA :: (hwnd: HWND, name: *u8) -> *void #foreign user32;
    GetWindowLongPtrW :: (hwnd: HWND, nIndex: s32) -> LONG_PTR #foreign user32;
    CallWindowProcW :: (prev_wnd_proc: WNDPROC, hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT #foreign user32;

    WNDPROC :: #type *(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT;
    LONG_PTR :: s64; // @Cleanup: 64 bit only for now
    GWLP_WNDPROC :: -4;
}

IMGUI_IMPL_GLFW_DISABLE_X11 :: false;
#if !IMGUI_IMPL_GLFW_DISABLE_X11 && OS == .LINUX {
    GLFW_HAS_X11 :: true;
} else {
    GLFW_HAS_X11 :: false;
}
IMGUI_IMPL_GLFW_DISABLE_WAYLAND :: false;
#if !IMGUI_IMPL_GLFW_DISABLE_WAYLAND && OS == .LINUX {
    GLFW_HAS_WAYLAND :: true;
} else {
    GLFW_HAS_WAYLAND :: false;
}

ImGui_ImplGlfw_Data :: struct {
    ctx: *ImGui.ImGuiContext;
    window: *GLFWwindow;
    time: float64;
    mouse_window: *GLFWwindow;
    mouse_cursors: [ImGui.MouseCursor.ImGuiMouseCursor_COUNT] *GLFWcursor;
    last_mouse_cursor: *GLFWcursor;
    mouse_ignore_button_up_wait_for_focus_loss: bool;
    mouse_ignore_button_up: bool;
    last_valid_mouse_pos: ImGui.ImVec2;
    key_owner_windows: [GLFW_KEY_LAST] *GLFWwindow;
    is_wayland: bool;
    installed_callbacks: bool;
    callbacks_chain_for_all_windows: bool;
    backend_platform_name: *u8;

    prev_user_callback_window_focus: GLFWwindowfocusfun;
    prev_user_callback_cursor_pos: GLFWcursorposfun;
    prev_user_callback_cursor_enter: GLFWcursorenterfun;
    prev_user_callback_mousebutton: GLFWmousebuttonfun;
    prev_user_callback_scroll: GLFWscrollfun;
    prev_user_callback_key: GLFWkeyfun;
    prev_user_callback_char: GLFWcharfun;
    prev_user_callback_monitor: GLFWmonitorfun;

    #if OS == .WINDOWS {
        prev_wnd_proc: WNDPROC;
    }

    #if GLFW_HAS_X11 {
        x_11_module: *void;
        x_intern_atom: PFN_XInternAtom;
        x_change_property: PFN_XChangeProperty;
        x_change_window_attributes: PFN_XChangeWindowAttributes;
        x_flush: PFN_XFlush;
    }
}

ImGui_ImplGlfw_InitForOpenGL :: (
    window: *GLFWwindow,
    install_callbacks: bool = true
) {
    io := ImGui.GetIO();

    bd := New(ImGui_ImplGlfw_Data);
    
    bd.backend_platform_name = to_c_string("imgui_impl_glfw (3.4)");
    io.BackendPlatformUserData = cast(*void) bd;
    io.BackendPlatformName = bd.backend_platform_name;
    io.BackendFlags_ |= ImGui.BackendFlags.HasMouseCursors;
    io.BackendFlags_ |= ImGui.BackendFlags.HasSetMousePos;

    has_viewports := false;
    if (glfwGetPlatform() == GLFW_PLATFORM_WAYLAND) {
        has_viewports = false;
    }
    if has_viewports {
        io.BackendFlags_ |= ImGui.BackendFlags.PlatformHasViewports;
    }
    io.BackendFlags_ |= ImGui.BackendFlags.HasMouseHoveredViewport;

    bd.ctx = ImGui.GetCurrentContext();
    bd.window = window;
    bd.time = 0.0;
    bd.is_wayland = ImGui_ImplGlfw_IsWayland();
    ImGui_ImplGlfw_ContextMap_Add(window, bd.ctx);

    platform_io := ImGui.GetPlatformIO();
    platform_io.Platform_SetClipboardTextFn = 
        (ctx: *ImGui.ImGuiContext, text: *u8 ) #c_call {
            glfwSetClipboardString(null, text);
        };
    platform_io.Platform_GetClipboardTextFn =
        (ctx: *ImGui.ImGuiContext) -> *u8 #c_call {
            return glfwGetClipboardString(null);
        };

    prev_error_callback: GLFWerrorfun = glfwSetErrorCallback(null);
    bd.mouse_cursors[ImGui.MouseCursor.Arrow] = glfwCreateStandardCursor(GLFW_ARROW_CURSOR);
    bd.mouse_cursors[ImGui.MouseCursor.TextInput] = glfwCreateStandardCursor(GLFW_IBEAM_CURSOR);
    bd.mouse_cursors[ImGui.MouseCursor.ResizeNS] = glfwCreateStandardCursor(GLFW_VRESIZE_CURSOR);
    bd.mouse_cursors[ImGui.MouseCursor.ResizeEW] = glfwCreateStandardCursor(GLFW_HRESIZE_CURSOR);
    bd.mouse_cursors[ImGui.MouseCursor.Hand] = glfwCreateStandardCursor(GLFW_HAND_CURSOR);
    bd.mouse_cursors[ImGui.MouseCursor.ResizeAll] = glfwCreateStandardCursor(GLFW_RESIZE_ALL_CURSOR);
    bd.mouse_cursors[ImGui.MouseCursor.ResizeNESW] = glfwCreateStandardCursor(GLFW_RESIZE_NESW_CURSOR);
    bd.mouse_cursors[ImGui.MouseCursor.ResizeNWSE] = glfwCreateStandardCursor(GLFW_RESIZE_NWSE_CURSOR);
    bd.mouse_cursors[ImGui.MouseCursor.NotAllowed] = glfwCreateStandardCursor(GLFW_NOT_ALLOWED_CURSOR);
    glfwSetErrorCallback(prev_error_callback);

    glfwGetError(null);

    if install_callbacks {
        ImGui_ImplGlfw_InstallCallbacks(window);
    }

    ImGui_ImplGlfw_UpdateMonitors();
    glfwSetMonitorCallback(ImGui_ImplGlfw_MonitorCallback);

    main_viewport := ImGui.GetMainViewport();
    main_viewport.PlatformHandle = cast(*void) bd.window;
    #if OS == .WINDOWS {
        main_viewport.PlatformHandleRaw = glfwGetWin32Window(bd.window);
    } else if OS == .MACOS {
        main_viewport.PlatformHandleRaw =
            cast(*void) glfwGetCocoaWindow(bd.window);
    }

    if has_viewports {
        ImGui_ImplGlfw_InitMultiViewportSupport();
    }

    #if OS == .WINDOWS {
        hwnd := cast(HWND) main_viewport.PlatformHandleRaw;
        SetPropA(hwnd, "IMGUI_BACKEND_DATA", bd);
        bd.prev_wnd_proc = cast(WNDPROC) GetWindowLongPtrW(hwnd, GWLP_WNDPROC);
        assert(bd.prev_wnd_proc != null);
        SetWindowLongPtrW(
            cast(HWND) main_viewport.PlatformHandleRaw,
            GWLP_WNDPROC,
            cast(LONG_PTR) cast(*void) ImGui_ImplGlfw_WndProc
        );
    }

    #if GLFW_HAS_X11 {
        if !bd.is_wayland {
            x11_module_path: *u8 = "libX11.so.6";
            bd.x_11_module = dlopen(x11_module_path, RTLD_LAZY | RTLD_LOCAL);
            bd.XInternAtom = cast(PFN_XInternAtom) dlsym(bd.X11Module, "XInternAtom");
            bd.XChangeProperty = cast(PFN_XChangeProperty) dlsym(bd.X11Module, "XChangeProperty");
            bd.XChangeWindowAttributes = cast(PFN_XChangeWindowAttributes) dlsym(bd.X11Module, "XChangeWindowAttributes");
            bd.XFlush = cast(PFN_XFlush) dlsym(bd.X11Module, "XFlush");
            assert(bd.XInternAtom != null && bd.XChangeProperty != null && bd.XChangeWindowAttributes != null && bd.XFlush != null);
        }
    }
}

ImGui_ImplGlfw_IsWayland :: () -> bool {
    #if !GLFW_HAS_WAYLAND {
        return false;
    } else #if GLFW_HAS_GETPLATFORM {
        return glfwGetPlatform() == GLFW_PLATFORM_WAYLAND;
    } else {
        version := glfwGetVersionString();
        if (strstr(version, "Wayland") == null) {
            return false;
        }
        #if GLFW_EXPOSE_NATIVE_X11 {
            if glfwGetX11Display() != null {
                return false;
            }
        }
        return true;
    }
}

ImGui_ImplGlfw_WindowToContext :: struct { 
    window: *GLFWwindow;
    ctx: *ImGui.ImGuiContext;
}

context_map: [..] ImGui_ImplGlfw_WindowToContext;

ImGui_ImplGlfw_ContextMap_Add :: (window: *GLFWwindow, ctx: *ImGui.ImGuiContext) {
    array_add(*context_map, .{window, ctx});
}

ImGui_ImplGlfw_ContextMap_Get :: (window: *GLFWwindow) -> *ImGui.ImGuiContext { 
    for context_map {
        if it.window == window {
            return it.ctx;
        }
    }

    return null;
}

ImGui_ImplGlfw_InstallCallbacks :: (window: *GLFWwindow) {
    bd := ImGui_ImplGlfw_GetBackendData(window);
    assert(bd.installed_callbacks == false, "Callbacks already installed!");
    assert(bd.window == window);

    bd.prev_user_callback_window_focus = glfwSetWindowFocusCallback(
        window,
        ImGui_ImplGlfw_WindowFocusCallback
    );
    bd.prev_user_callback_cursor_enter = glfwSetCursorEnterCallback(
        window,
        ImGui_ImplGlfw_CursorEnterCallback
    );
    bd.prev_user_callback_cursor_pos = glfwSetCursorPosCallback(
        window,
        ImGui_ImplGlfw_CursorPosCallback
    );
    bd.prev_user_callback_mousebutton = glfwSetMouseButtonCallback(
        window,
        ImGui_ImplGlfw_MouseButtonCallback
    );
    bd.prev_user_callback_scroll = glfwSetScrollCallback(
        window,
        ImGui_ImplGlfw_ScrollCallback
    );
    bd.prev_user_callback_key = glfwSetKeyCallback(
        window,
        ImGui_ImplGlfw_KeyCallback
    );
    bd.prev_user_callback_char = glfwSetCharCallback(
        window,
        ImGui_ImplGlfw_CharCallback
    );
    bd.prev_user_callback_monitor = glfwSetMonitorCallback(
        ImGui_ImplGlfw_MonitorCallback
    );
    bd.installed_callbacks = true;
}

ImGui_ImplGlfw_GetBackendData :: () -> *ImGui_ImplGlfw_Data {
    if ImGui.GetCurrentContext() {
        return cast(*ImGui_ImplGlfw_Data) ImGui.GetIO().BackendPlatformUserData;
    }

    return null;
}

// @Cleanup: hack to get this function - its not in the bindings
// i should fix up the bindings myself
// ImGui_GetIO :: (ctx: *ImGui.ImGuiContext) -> *ImGui.IO #foreign imgui "_ZN5ImGui5GetIOEP12ImGuiContext";
#if OS == .MACOS {
    imgui :: #library "../modules/jai-imgui/macos/ImGui";
    ImGui_GetIO :: (ctx: *ImGui.ImGuiContext) -> *ImGui.IO #foreign imgui "_ZN5ImGui5GetIOEP12ImGuiContext";
}
#if OS == .LINUX {
    imgui :: #library "../modules/jai-imgui/linux/ImGui";
    ImGui_GetIO :: (ctx: *ImGui.ImGuiContext) -> *ImGui.IO #foreign imgui "_ZN5ImGui5GetIOEP12ImGuiContext";
}
#if OS == .WINDOWS {
    imgui :: #library,no_dll "../modules/jai-imgui/windows/ImGui";
    ImGui_GetIO :: (ctx: *ImGui.ImGuiContext) -> *ImGui.IO #foreign imgui "?GetIO@ImGui@@YAAEAUImGuiIO@@PEAUImGuiContext@@@Z";
}

ImGui_ImplGlfw_GetBackendData :: (window: *GLFWwindow) -> *ImGui_ImplGlfw_Data {
    ctx := ImGui_ImplGlfw_ContextMap_Get(window);
    return cast(*ImGui_ImplGlfw_Data) ImGui_GetIO(ctx).BackendPlatformUserData;
}

ImGui_ImplGlfw_WindowFocusCallback :: (
    window: *GLFWwindow,
    focused: s32
) #c_call {
    push_context {
        bd := ImGui_ImplGlfw_GetBackendData(window);
        if bd.prev_user_callback_window_focus != null &&
        ImGui_ImplGlfw_ShouldChainCallback(bd, window) {
            bd.prev_user_callback_window_focus(window, focused);
        }

        bd.mouse_ignore_button_up =
            bd.mouse_ignore_button_up_wait_for_focus_loss && focused == 0;
        bd.mouse_ignore_button_up_wait_for_focus_loss = false;

        io := ImGui_GetIO(bd.ctx);
        ImGui.IO.AddFocusEvent(io, focused != 0);
    }
}

ImGui_ImplGlfw_ShouldChainCallback :: (
    bd: *ImGui_ImplGlfw_Data,
    window: *GLFWwindow
) -> bool {
    if bd.callbacks_chain_for_all_windows {
        return true;
    }
    return window == bd.window;
}

ImGui_ImplGlfw_CursorEnterCallback :: (
    window: *GLFWwindow,
    entered: s32
) #c_call {
    push_context {
        bd := ImGui_ImplGlfw_GetBackendData(window);
        if bd.prev_user_callback_cursor_enter != null &&
        ImGui_ImplGlfw_ShouldChainCallback(bd, window) {
            bd.prev_user_callback_cursor_enter(window, entered);
        }

        io := ImGui_GetIO(bd.ctx);
        if entered {
            bd.mouse_window = window;
            ImGui.IO.AddMousePosEvent(
                io,
                bd.last_valid_mouse_pos.x, bd.last_valid_mouse_pos.y
            );
        } else if !entered && bd.mouse_window == window {
            bd.last_valid_mouse_pos = io.MousePos;
            bd.mouse_window = null;
            ImGui.IO.AddMousePosEvent(io, -FLOAT32_MAX, -FLOAT32_MAX);
        }
    }
}

ImGui_ImplGlfw_CursorPosCallback :: (
    window: *GLFWwindow,
    x: float64,
    y: float64
) #c_call {
    push_context {
        bd := ImGui_ImplGlfw_GetBackendData(window);
        if bd.prev_user_callback_cursor_pos != null &&
           ImGui_ImplGlfw_ShouldChainCallback(bd, window) {
            bd.prev_user_callback_cursor_pos(window, x, y);
        }

        io := ImGui_GetIO(bd.ctx);
        if io.ConfigFlags_ & ImGui.ConfigFlags.ViewportsEnable {
            window_x, window_y: s32;
            glfwGetWindowPos(window, *window_x, *window_y);
            x += window_x;
            y += window_y;
        }
        ImGui.IO.AddMousePosEvent(io, cast(float) x, cast(float) y);
        bd.last_valid_mouse_pos = .{cast(float) x, cast(float) y};
    }
}

ImGui_ImplGlfw_MouseButtonCallback :: (
    window: *GLFWwindow,
    button: s32,
    action: s32,
    mods: s32
) #c_call {
    push_context {
        bd := ImGui_ImplGlfw_GetBackendData(window);
        if bd.prev_user_callback_mousebutton != null &&
           ImGui_ImplGlfw_ShouldChainCallback(bd, window) {
            bd.prev_user_callback_mousebutton(window, button, action, mods);
        }

        if bd.mouse_ignore_button_up && action == GLFW_RELEASE {
            return;
        }

        io := ImGui_GetIO(bd.ctx);
        ImGui_ImplGlfw_UpdateKeyModifiers(io, window);
        if button >= 0 &&
           button < cast(s32) ImGui.MouseButton.ImGuiMouseButton_COUNT {
            ImGui.IO.AddMouseButtonEvent(io, button, action == GLFW_PRESS);
        }
    }
}

ImGui_ImplGlfw_UpdateKeyModifiers :: (io: *ImGui.IO, window: *GLFWwindow) {
    ImGui.IO.AddKeyEvent(
        io,
        ImGui.Key.ImGuiMod_Ctrl,
        (glfwGetKey(window, GLFW_KEY_LEFT_CONTROL) == GLFW_PRESS) ||
        (glfwGetKey(window, GLFW_KEY_RIGHT_CONTROL) == GLFW_PRESS)
    );
    ImGui.IO.AddKeyEvent(
        io,
        ImGui.Key.ImGuiMod_Shift,
        (glfwGetKey(window, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS) ||
        (glfwGetKey(window, GLFW_KEY_RIGHT_SHIFT)   == GLFW_PRESS)
    );
    ImGui.IO.AddKeyEvent(
        io,
        ImGui.Key.ImGuiMod_Alt,
        (glfwGetKey(window, GLFW_KEY_LEFT_ALT) == GLFW_PRESS) ||
        (glfwGetKey(window, GLFW_KEY_RIGHT_ALT) == GLFW_PRESS)
    );
    ImGui.IO.AddKeyEvent(
        io,
        ImGui.Key.ImGuiMod_Super,
        (glfwGetKey(window, GLFW_KEY_LEFT_SUPER) == GLFW_PRESS) ||
        (glfwGetKey(window, GLFW_KEY_RIGHT_SUPER) == GLFW_PRESS)
    );
}

ImGui_ImplGlfw_ScrollCallback :: (
    window: *GLFWwindow, 
    xoffset: float64, 
    yoffset: float64
) #c_call {
    push_context {
        bd := ImGui_ImplGlfw_GetBackendData(window);
        if bd.prev_user_callback_scroll != null &&
        ImGui_ImplGlfw_ShouldChainCallback(bd, window) {
        bd.prev_user_callback_scroll(window, xoffset, yoffset);
        }

        io := ImGui_GetIO(bd.ctx);
        ImGui.IO.AddMouseWheelEvent(io, cast(float) xoffset, cast(float) yoffset);
    }
}

ImGui_ImplGlfw_KeyCallback :: (
    window: *GLFWwindow,
    keycode: s32, 
    scancode: s32,
    action: s32,
    mods: s32
) #c_call {
    push_context {
        bd := ImGui_ImplGlfw_GetBackendData(window);
        if bd.prev_user_callback_key != null &&
           ImGui_ImplGlfw_ShouldChainCallback(bd, window) {
           bd.prev_user_callback_key(window, keycode, scancode, action, mods);
        }

        if action != GLFW_PRESS && action != GLFW_RELEASE {
            return;
        }

        io := ImGui_GetIO(bd.ctx);
        ImGui_ImplGlfw_UpdateKeyModifiers(io, window);

        if keycode >= 0 && keycode < bd.key_owner_windows.count {
            bd.key_owner_windows[keycode] = ifx action == GLFW_PRESS then window else null;
        }

        keycode = ImGui_ImplGlfw_TranslateUntranslatedKey(keycode, scancode);

        imgui_key := ImGui_ImplGlfw_KeyToImGuiKey(keycode, scancode);
        ImGui.IO.AddKeyEvent(io, imgui_key, action == GLFW_PRESS);
        ImGui.IO.SetKeyEventNativeData(io, imgui_key, keycode, scancode);
    }
}

ImGui_ImplGlfw_TranslateUntranslatedKey :: (key: s32, scancode: s32) -> s32 {
    if key >= GLFW_KEY_KP_0 && key <= GLFW_KEY_KP_EQUAL {
        return key;
    }
    prev_error_callback := glfwSetErrorCallback(null);
    key_name := glfwGetKeyName(key, scancode);
    glfwSetErrorCallback(prev_error_callback);
    
    glfwGetError(null);
    
    if key_name && key_name[0] != 0 && key_name[1] == 0 {
        char_names := "`-=[]\\,;'./";
        char_keys: [11] s32 = .[
            GLFW_KEY_GRAVE_ACCENT,
            GLFW_KEY_MINUS,
            GLFW_KEY_EQUAL,
            GLFW_KEY_LEFT_BRACKET,
            GLFW_KEY_RIGHT_BRACKET,
            GLFW_KEY_BACKSLASH,
            GLFW_KEY_COMMA,
            GLFW_KEY_SEMICOLON,
            GLFW_KEY_APOSTROPHE,
            GLFW_KEY_PERIOD,
            GLFW_KEY_SLASH
        ];
        assert(char_names.count == char_keys.count);
        if key_name[0] >= "0" && key_name[0] <= "9" {
            key = GLFW_KEY_0 + (key_name[0] - "0");
        } else if key_name[0] >= "A" && key_name[0] <= "Z" {
            key = GLFW_KEY_A + (key_name[0] - "A");
        } else if key_name[0] >= "a" && key_name[0] <= "z" {
            key = GLFW_KEY_A + (key_name[0] - "a");
        } else {
            idx := find_char(char_names, key_name[0]);
            if idx >= 0 {
                key = char_keys[idx];
            }
        }
    }
    
    return key;
}

find_char :: (s: string, c: u8) -> s64 {
    for i: s {
        if s.data[i] == c {
            return i;
        }
    }
    return -1;
}

ImGui_ImplGlfw_KeyToImGuiKey :: (keycode: s32, scancode: s32) -> ImGui.Key {
    if keycode == {
        case GLFW_KEY_TAB; return ImGui.Key.ImGuiKey_Tab;
        case GLFW_KEY_LEFT; return ImGui.Key.ImGuiKey_LeftArrow;
        case GLFW_KEY_RIGHT; return ImGui.Key.ImGuiKey_RightArrow;
        case GLFW_KEY_UP; return ImGui.Key.ImGuiKey_UpArrow;
        case GLFW_KEY_DOWN; return ImGui.Key.ImGuiKey_DownArrow;
        case GLFW_KEY_PAGE_UP; return ImGui.Key.ImGuiKey_PageUp;
        case GLFW_KEY_PAGE_DOWN; return ImGui.Key.ImGuiKey_PageDown;
        case GLFW_KEY_HOME; return ImGui.Key.ImGuiKey_Home;
        case GLFW_KEY_END; return ImGui.Key.ImGuiKey_End;
        case GLFW_KEY_INSERT; return ImGui.Key.ImGuiKey_Insert;
        case GLFW_KEY_DELETE; return ImGui.Key.ImGuiKey_Delete;
        case GLFW_KEY_BACKSPACE; return ImGui.Key.ImGuiKey_Backspace;
        case GLFW_KEY_SPACE; return ImGui.Key.ImGuiKey_Space;
        case GLFW_KEY_ENTER; return ImGui.Key.ImGuiKey_Enter;
        case GLFW_KEY_ESCAPE; return ImGui.Key.ImGuiKey_Escape;
        case GLFW_KEY_APOSTROPHE; return ImGui.Key.ImGuiKey_Apostrophe;
        case GLFW_KEY_COMMA; return ImGui.Key.ImGuiKey_Comma;
        case GLFW_KEY_MINUS; return ImGui.Key.ImGuiKey_Minus;
        case GLFW_KEY_PERIOD; return ImGui.Key.ImGuiKey_Period;
        case GLFW_KEY_SLASH; return ImGui.Key.ImGuiKey_Slash;
        case GLFW_KEY_SEMICOLON; return ImGui.Key.ImGuiKey_Semicolon;
        case GLFW_KEY_EQUAL; return ImGui.Key.ImGuiKey_Equal;
        case GLFW_KEY_LEFT_BRACKET; return ImGui.Key.ImGuiKey_LeftBracket;
        case GLFW_KEY_BACKSLASH; return ImGui.Key.ImGuiKey_Backslash;
        case GLFW_KEY_WORLD_1; return ImGui.Key.ImGuiKey_Oem102;
        case GLFW_KEY_WORLD_2; return ImGui.Key.ImGuiKey_Oem102;
        case GLFW_KEY_RIGHT_BRACKET; return ImGui.Key.ImGuiKey_RightBracket;
        case GLFW_KEY_GRAVE_ACCENT; return ImGui.Key.ImGuiKey_GraveAccent;
        case GLFW_KEY_CAPS_LOCK; return ImGui.Key.ImGuiKey_CapsLock;
        case GLFW_KEY_SCROLL_LOCK; return ImGui.Key.ImGuiKey_ScrollLock;
        case GLFW_KEY_NUM_LOCK; return ImGui.Key.ImGuiKey_NumLock;
        case GLFW_KEY_PRINT_SCREEN; return ImGui.Key.ImGuiKey_PrintScreen;
        case GLFW_KEY_PAUSE; return ImGui.Key.ImGuiKey_Pause;
        case GLFW_KEY_KP_0; return ImGui.Key.ImGuiKey_Keypad0;
        case GLFW_KEY_KP_1; return ImGui.Key.ImGuiKey_Keypad1;
        case GLFW_KEY_KP_2; return ImGui.Key.ImGuiKey_Keypad2;
        case GLFW_KEY_KP_3; return ImGui.Key.ImGuiKey_Keypad3;
        case GLFW_KEY_KP_4; return ImGui.Key.ImGuiKey_Keypad4;
        case GLFW_KEY_KP_5; return ImGui.Key.ImGuiKey_Keypad5;
        case GLFW_KEY_KP_6; return ImGui.Key.ImGuiKey_Keypad6;
        case GLFW_KEY_KP_7; return ImGui.Key.ImGuiKey_Keypad7;
        case GLFW_KEY_KP_8; return ImGui.Key.ImGuiKey_Keypad8;
        case GLFW_KEY_KP_9; return ImGui.Key.ImGuiKey_Keypad9;
        case GLFW_KEY_KP_DECIMAL; return ImGui.Key.ImGuiKey_KeypadDecimal;
        case GLFW_KEY_KP_DIVIDE; return ImGui.Key.ImGuiKey_KeypadDivide;
        case GLFW_KEY_KP_MULTIPLY; return ImGui.Key.ImGuiKey_KeypadMultiply;
        case GLFW_KEY_KP_SUBTRACT; return ImGui.Key.ImGuiKey_KeypadSubtract;
        case GLFW_KEY_KP_ADD; return ImGui.Key.ImGuiKey_KeypadAdd;
        case GLFW_KEY_KP_ENTER; return ImGui.Key.ImGuiKey_KeypadEnter;
        case GLFW_KEY_KP_EQUAL; return ImGui.Key.ImGuiKey_KeypadEqual;
        case GLFW_KEY_LEFT_SHIFT; return ImGui.Key.ImGuiKey_LeftShift;
        case GLFW_KEY_LEFT_CONTROL; return ImGui.Key.ImGuiKey_LeftCtrl;
        case GLFW_KEY_LEFT_ALT; return ImGui.Key.ImGuiKey_LeftAlt;
        case GLFW_KEY_LEFT_SUPER; return ImGui.Key.ImGuiKey_LeftSuper;
        case GLFW_KEY_RIGHT_SHIFT; return ImGui.Key.ImGuiKey_RightShift;
        case GLFW_KEY_RIGHT_CONTROL; return ImGui.Key.ImGuiKey_RightCtrl;
        case GLFW_KEY_RIGHT_ALT; return ImGui.Key.ImGuiKey_RightAlt;
        case GLFW_KEY_RIGHT_SUPER; return ImGui.Key.ImGuiKey_RightSuper;
        case GLFW_KEY_MENU; return ImGui.Key.ImGuiKey_Menu;
        case GLFW_KEY_0; return ImGui.Key.ImGuiKey_0;
        case GLFW_KEY_1; return ImGui.Key.ImGuiKey_1;
        case GLFW_KEY_2; return ImGui.Key.ImGuiKey_2;
        case GLFW_KEY_3; return ImGui.Key.ImGuiKey_3;
        case GLFW_KEY_4; return ImGui.Key.ImGuiKey_4;
        case GLFW_KEY_5; return ImGui.Key.ImGuiKey_5;
        case GLFW_KEY_6; return ImGui.Key.ImGuiKey_6;
        case GLFW_KEY_7; return ImGui.Key.ImGuiKey_7;
        case GLFW_KEY_8; return ImGui.Key.ImGuiKey_8;
        case GLFW_KEY_9; return ImGui.Key.ImGuiKey_9;
        case GLFW_KEY_A; return ImGui.Key.ImGuiKey_A;
        case GLFW_KEY_B; return ImGui.Key.ImGuiKey_B;
        case GLFW_KEY_C; return ImGui.Key.ImGuiKey_C;
        case GLFW_KEY_D; return ImGui.Key.ImGuiKey_D;
        case GLFW_KEY_E; return ImGui.Key.ImGuiKey_E;
        case GLFW_KEY_F; return ImGui.Key.ImGuiKey_F;
        case GLFW_KEY_G; return ImGui.Key.ImGuiKey_G;
        case GLFW_KEY_H; return ImGui.Key.ImGuiKey_H;
        case GLFW_KEY_I; return ImGui.Key.ImGuiKey_I;
        case GLFW_KEY_J; return ImGui.Key.ImGuiKey_J;
        case GLFW_KEY_K; return ImGui.Key.ImGuiKey_K;
        case GLFW_KEY_L; return ImGui.Key.ImGuiKey_L;
        case GLFW_KEY_M; return ImGui.Key.ImGuiKey_M;
        case GLFW_KEY_N; return ImGui.Key.ImGuiKey_N;
        case GLFW_KEY_O; return ImGui.Key.ImGuiKey_O;
        case GLFW_KEY_P; return ImGui.Key.ImGuiKey_P;
        case GLFW_KEY_Q; return ImGui.Key.ImGuiKey_Q;
        case GLFW_KEY_R; return ImGui.Key.ImGuiKey_R;
        case GLFW_KEY_S; return ImGui.Key.ImGuiKey_S;
        case GLFW_KEY_T; return ImGui.Key.ImGuiKey_T;
        case GLFW_KEY_U; return ImGui.Key.ImGuiKey_U;
        case GLFW_KEY_V; return ImGui.Key.ImGuiKey_V;
        case GLFW_KEY_W; return ImGui.Key.ImGuiKey_W;
        case GLFW_KEY_X; return ImGui.Key.ImGuiKey_X;
        case GLFW_KEY_Y; return ImGui.Key.ImGuiKey_Y;
        case GLFW_KEY_Z; return ImGui.Key.ImGuiKey_Z;
        case GLFW_KEY_F1; return ImGui.Key.ImGuiKey_F1;
        case GLFW_KEY_F2; return ImGui.Key.ImGuiKey_F2;
        case GLFW_KEY_F3; return ImGui.Key.ImGuiKey_F3;
        case GLFW_KEY_F4; return ImGui.Key.ImGuiKey_F4;
        case GLFW_KEY_F5; return ImGui.Key.ImGuiKey_F5;
        case GLFW_KEY_F6; return ImGui.Key.ImGuiKey_F6;
        case GLFW_KEY_F7; return ImGui.Key.ImGuiKey_F7;
        case GLFW_KEY_F8; return ImGui.Key.ImGuiKey_F8;
        case GLFW_KEY_F9; return ImGui.Key.ImGuiKey_F9;
        case GLFW_KEY_F10; return ImGui.Key.ImGuiKey_F10;
        case GLFW_KEY_F11; return ImGui.Key.ImGuiKey_F11;
        case GLFW_KEY_F12; return ImGui.Key.ImGuiKey_F12;
        case GLFW_KEY_F13; return ImGui.Key.ImGuiKey_F13;
        case GLFW_KEY_F14; return ImGui.Key.ImGuiKey_F14;
        case GLFW_KEY_F15; return ImGui.Key.ImGuiKey_F15;
        case GLFW_KEY_F16; return ImGui.Key.ImGuiKey_F16;
        case GLFW_KEY_F17; return ImGui.Key.ImGuiKey_F17;
        case GLFW_KEY_F18; return ImGui.Key.ImGuiKey_F18;
        case GLFW_KEY_F19; return ImGui.Key.ImGuiKey_F19;
        case GLFW_KEY_F20; return ImGui.Key.ImGuiKey_F20;
        case GLFW_KEY_F21; return ImGui.Key.ImGuiKey_F21;
        case GLFW_KEY_F22; return ImGui.Key.ImGuiKey_F22;
        case GLFW_KEY_F23; return ImGui.Key.ImGuiKey_F23;
        case GLFW_KEY_F24; return ImGui.Key.ImGuiKey_F24;
        case; return ImGui.Key.ImGuiKey_None;
    }
}

ImGui_ImplGlfw_CharCallback :: (window: *GLFWwindow, c: u32) #c_call {
    push_context {
        bd := ImGui_ImplGlfw_GetBackendData(window);
        if bd.prev_user_callback_char != null &&
        ImGui_ImplGlfw_ShouldChainCallback(bd, window) {
            bd.prev_user_callback_char(window, c);
        }

        io := ImGui_GetIO(bd.ctx);
        ImGui.IO.AddInputCharacter(io, c);
    }
}

ImGui_ImplGlfw_MonitorCallback :: (monitor: *GLFWmonitor, event: s32) #c_call {
}

ImGui_ImplOpenGL3_Data :: struct {
    gl_version: GLuint;               
    glsl_version_string: [32] u8;
    gl_profile_is_es2: bool;
    gl_profile_is_es3: bool;
    gl_profile_is_compat: bool;
    gl_profile_mask: GLint;
    max_texture_size: GLint;
    shader_handle: GLuint;
    attrib_location_tex: GLint;
    attrib_location_proj_mtx: GLint;
    attrib_location_vtx_pos: GLint;
    attrib_location_vtx_uv: GLint;
    attrib_location_vtx_color: GLint;
    vbo_handle: u32; 
    elements_handle: u32;
    vertex_buffer_size: GLsizeiptr;
    index_buffer_size: GLsizeiptr;
    has_polygon_mode: bool;
    has_bind_sampler: bool;
    has_clip_origin: bool;
    use_buffer_sub_data: bool;
    temp_buffer: [..] u8;
}

ImGui_ImplOpenGL3_Init :: (glsl_version: *u8) -> bool {
    io := ImGui.GetIO();
    assert(
        io.BackendRendererUserData == null,
        "Already initialized a renderer backend!"
    );

    bd := New(ImGui_ImplOpenGL3_Data);
    io.BackendRendererUserData = cast(*void) bd;
    io.BackendRendererName = "imgui_impl_opengl3";

    gl_version_str := cast(*u8) glGetString(GL_VERSION);

    major: GLint = 0;
    minor: GLint = 0;
    glGetIntegerv(GL_MAJOR_VERSION, *major);
    glGetIntegerv(GL_MINOR_VERSION, *minor);
    if major == 0 && minor == 0 {
        gl_version_str := tprint("%.%", major, minor);
    }
    bd.gl_version = cast(GLuint) (major * 100 + minor * 10);
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, *bd.max_texture_size);

    glGetIntegerv(GL_CONTEXT_PROFILE_MASK, *bd.gl_profile_mask);
    bd.gl_profile_is_compat =
        (bd.gl_profile_mask & GL_CONTEXT_COMPATIBILITY_PROFILE_BIT) != 0;

    bd.use_buffer_sub_data = false;

    if bd.gl_version >= 320 {
        io.BackendFlags_ |= ImGui.BackendFlags.RendererHasVtxOffset;
    }

    io.BackendFlags_ |= ImGui.BackendFlags.RendererHasTextures;
    io.BackendFlags_ |= ImGui.BackendFlags.RendererHasViewports;

    platform_io := ImGui.GetPlatformIO();
    platform_io.Renderer_TextureMaxWidth = cast(s32) bd.max_texture_size;
    platform_io.Renderer_TextureMaxHeight = cast(s32) bd.max_texture_size;

    if glsl_version == null {
        #if OS == .MACOS {
            glsl_version = "#version 150";
        } else {
            glsl_version = "#version 130";
        }
    }

    len := c_style_strlen(glsl_version);
    assert(cast(s32) len + 2 < bd.glsl_version_string.count);
    for i: 0..len - 1 {
        bd.glsl_version_string[i] = glsl_version[i];
    }
    bd.glsl_version_string[len] = "\n";

    current_texture: GLint;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, *current_texture);

    bd.has_polygon_mode = true;
    bd.has_bind_sampler = true;
    bd.has_clip_origin = false;

    num_extensions: GLint = 0;
    glGetIntegerv(GL_NUM_EXTENSIONS, *num_extensions);
    for i: 0..num_extensions - 1 {
        extension := cast(*u8) glGetStringi(GL_EXTENSIONS, cast(u32) i);
        if extension != null && to_string(extension) == "GL_ARB_clip_control" {
            bd.has_clip_origin = true;
        }
    }

    ImGui_ImplOpenGL3_InitMultiViewportSupport();

    return true;
}

ImGui_ImplOpenGL3_InitMultiViewportSupport :: () {
    platform_io := ImGui.GetPlatformIO();
    platform_io.Renderer_RenderWindow = ImGui_ImplOpenGL3_RenderWindow;
}

ImGui_ImplOpenGL3_RenderWindow :: (viewport: *ImGui.Viewport, *void) #c_call {
    if !(viewport.Flags & ImGui.ViewportFlags.NoRendererClear) {
        clear_color := ImGui.ImVec4.{0.0, 0.0, 0.0, 1.0};
        glClearColor(clear_color.x, clear_color.y, clear_color.z, clear_color.w);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    ImGui_ImplOpenGL3_RenderDrawData(viewport.DrawData);
}

ImGui_ImplOpenGL3_RenderDrawData :: (draw_data: *ImGui.ImDrawData) #c_call {
    push_context {
        log_install();
        fb_width :=
            cast(s32) (draw_data.DisplaySize.x * draw_data.FramebufferScale.x);
        fb_height :=
            cast(s32) (draw_data.DisplaySize.y * draw_data.FramebufferScale.y);
        if fb_width <= 0 || fb_height <= 0 {
            return;
        }

        bd := ImGui_ImplOpenGL3_GetBackendData();

        if draw_data.Textures != null {
            for * draw_data.Textures {
                if it.Status != ImGui.ImTextureStatus.ImTextureStatus_OK {
                    ImGui_ImplOpenGL3_UpdateTexture(it);
                }
            }
        }

        last_active_texture: GLenum;
        glGetIntegerv(GL_ACTIVE_TEXTURE, cast(*GLint) *last_active_texture);
        glActiveTexture(GL_TEXTURE0);
        last_program: GLuint;
        glGetIntegerv(GL_CURRENT_PROGRAM, cast(*GLint) *last_program);
        last_texture: GLuint;
        glGetIntegerv(GL_TEXTURE_BINDING_2D, cast(*GLint) *last_texture);
        last_sampler: GLuint;
        if bd.has_bind_sampler {
            glGetIntegerv(GL_SAMPLER_BINDING, cast(*GLint) *last_sampler);
        } else {
            last_sampler = 0;
        }
        last_array_buffer: GLuint;
        glGetIntegerv(GL_ARRAY_BUFFER_BINDING, cast(*GLint) *last_array_buffer);

        last_vertex_array_object: GLuint;
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, cast(*GLint) *last_vertex_array_object);

        last_polygon_mode: [2] GLint;
        if bd.has_polygon_mode {
            glGetIntegerv(GL_POLYGON_MODE, last_polygon_mode.data);
        }

        last_viewport: [4] GLint;
        glGetIntegerv(GL_VIEWPORT, last_viewport.data);
        last_scissor_box: [4] GLint;
        glGetIntegerv(GL_SCISSOR_BOX, last_scissor_box.data);
        last_blend_src_rgb: GLenum;
        glGetIntegerv(GL_BLEND_SRC_RGB, cast(*GLint) *last_blend_src_rgb);
        last_blend_dst_rgb: GLenum;
        glGetIntegerv(GL_BLEND_DST_RGB, cast(*GLint) *last_blend_dst_rgb);
        last_blend_src_alpha: GLenum;
        glGetIntegerv(GL_BLEND_SRC_ALPHA, cast(*GLint) *last_blend_src_alpha);
        last_blend_dst_alpha: GLenum;
        glGetIntegerv(GL_BLEND_DST_ALPHA, cast(*GLint) *last_blend_dst_alpha);
        last_blend_equation_rgb: GLenum;
        glGetIntegerv(GL_BLEND_EQUATION_RGB, cast(*GLint) *last_blend_equation_rgb);
        last_blend_equation_alpha: GLenum;
        glGetIntegerv(
            GL_BLEND_EQUATION_ALPHA,
            cast(*GLint) *last_blend_equation_alpha
        );
        last_enable_blend := glIsEnabled(GL_BLEND);
        last_enable_cull_face := glIsEnabled(GL_CULL_FACE);
        last_enable_depth_test := glIsEnabled(GL_DEPTH_TEST);
        last_enable_stencil_test := glIsEnabled(GL_STENCIL_TEST);
        last_enable_scissor_test := glIsEnabled(GL_SCISSOR_TEST);

        last_enable_primitive_restart: GLboolean;
        if !bd.gl_profile_is_es3 && bd.gl_version >= 310 {
            last_enable_primitive_restart = glIsEnabled(GL_PRIMITIVE_RESTART);
        } else {
            last_enable_primitive_restart = GL_FALSE;
        }

        vertex_array_object: GLuint = 0;
        GL_CALL(glGenVertexArrays(1, *vertex_array_object));
        ImGui_ImplOpenGL3_SetupRenderState(
            draw_data,
            fb_width,
            fb_height,
            vertex_array_object
        );

        clip_off: ImGui.ImVec2 = draw_data.DisplayPos;
        clip_scale: ImGui.ImVec2 = draw_data.FramebufferScale;

        // ImDrawList*
        for draw_list: draw_data.CmdLists {
            vtx_buffer_size := cast(GLsizeiptr) draw_list.VtxBuffer.Size * 
                cast(s32) size_of(ImGui.ImDrawVert);
            idx_buffer_size := cast(GLsizeiptr) draw_list.IdxBuffer.Size *
                cast(s32) size_of(ImGui.ImDrawIdx);
            if bd.use_buffer_sub_data {
                if bd.vertex_buffer_size < vtx_buffer_size {
                    bd.vertex_buffer_size = vtx_buffer_size;
                    GL_CALL(glBufferData(
                        GL_ARRAY_BUFFER,
                        bd.vertex_buffer_size,
                        null,
                        GL_STREAM_DRAW
                    ));
                }
                if bd.index_buffer_size < idx_buffer_size {
                    bd.index_buffer_size = idx_buffer_size;
                    GL_CALL(glBufferData(
                        GL_ELEMENT_ARRAY_BUFFER,
                        bd.index_buffer_size,
                        null,
                        GL_STREAM_DRAW
                    ));
                }
                GL_CALL(glBufferSubData(
                    GL_ARRAY_BUFFER,
                    0,
                    vtx_buffer_size,
                    cast(*void) draw_list.VtxBuffer.Data
                ));
                GL_CALL(glBufferSubData(
                    GL_ELEMENT_ARRAY_BUFFER,
                    0,
                    idx_buffer_size,
                    cast(*void) draw_list.IdxBuffer.Data
                ));
            } else {
                GL_CALL(glBufferData(
                    GL_ARRAY_BUFFER,
                    vtx_buffer_size, cast(*void) draw_list.VtxBuffer.Data,
                    GL_STREAM_DRAW
                ));
                GL_CALL(glBufferData(
                    GL_ELEMENT_ARRAY_BUFFER,
                    idx_buffer_size,
                    cast(*void) draw_list.IdxBuffer.Data,
                    GL_STREAM_DRAW
                ));
            }

            for cmd_i: 0..draw_list.CmdBuffer.Size - 1 {
                pcmd := *draw_list.CmdBuffer.Data[cmd_i];
                if pcmd.UserCallback != null {
                    ImDrawCallback_ResetRenderState :: cast(ImGui.ImDrawCallback) -1;
                    if pcmd.UserCallback == ImDrawCallback_ResetRenderState {
                        ImGui_ImplOpenGL3_SetupRenderState(draw_data, fb_width, fb_height, vertex_array_object);
                    } else {
                        pcmd.UserCallback(draw_list, pcmd);
                    }
                } else {
                    clip_min := ImGui.ImVec2.{
                        (pcmd.ClipRect.x - clip_off.x) * clip_scale.x,
                        (pcmd.ClipRect.y - clip_off.y) * clip_scale.y
                    };
                    clip_max := ImGui.ImVec2.{
                        (pcmd.ClipRect.z - clip_off.x) * clip_scale.x,
                        (pcmd.ClipRect.w - clip_off.y) * clip_scale.y
                    };
                    if clip_max.x <= clip_min.x || clip_max.y <= clip_min.y {
                        continue;
                    }

                    GL_CALL(glScissor(
                        cast(s32) clip_min.x,
                        cast(s32) (cast(float) fb_height - clip_max.y),
                        cast(u32) (clip_max.x - clip_min.x),
                        cast(u32) (clip_max.y - clip_min.y)
                    ));

                    // Bind texture, Draw
                    GL_CALL(glBindTexture(
                        GL_TEXTURE_2D,
                        cast(GLuint) cast(u64) GetTexID(pcmd)
                    ));

                    type: GLenum;
                    if size_of(ImGui.ImDrawIdx) == 2 {
                        type = GL_UNSIGNED_SHORT;
                    } else {
                        type = GL_UNSIGNED_INT;
                    }
                    size := cast(*void) cast(u64) (
                        pcmd.IdxOffset * size_of(ImGui.ImDrawIdx)
                    );
                    if bd.gl_version >= 320 {
                        GL_CALL(glDrawElementsBaseVertex(
                            GL_TRIANGLES, 
                            cast(GLsizei) pcmd.ElemCount,
                            type,
                            size,
                            cast(GLint) pcmd.VtxOffset
                        ));
                    } else {
                        GL_CALL(glDrawElements(
                            GL_TRIANGLES,
                            cast(GLsizei) pcmd.ElemCount,
                            type,
                            size
                        ));
                    }
                }
            }
        }

        GL_CALL(glDeleteVertexArrays(1, *vertex_array_object));

        if last_program == 0 || glIsProgram(last_program) {
            glUseProgram(last_program);
        }
        glBindTexture(GL_TEXTURE_2D, last_texture);
        if (bd.has_bind_sampler) {
            glBindSampler(0, last_sampler);
        }
        glActiveTexture(last_active_texture);
        glBindVertexArray(last_vertex_array_object);
        glBindBuffer(GL_ARRAY_BUFFER, last_array_buffer);
        glBlendEquationSeparate(last_blend_equation_rgb, last_blend_equation_alpha);
        glBlendFuncSeparate(
            last_blend_src_rgb,
            last_blend_dst_rgb,
            last_blend_src_alpha,
            last_blend_dst_alpha
        );
        if last_enable_blend {
            glEnable(GL_BLEND);
        } else {
            glDisable(GL_BLEND);
        }
        if last_enable_cull_face {
            glEnable(GL_CULL_FACE);
        } else {
            glDisable(GL_CULL_FACE);
        }
        if last_enable_depth_test {
            glEnable(GL_DEPTH_TEST);
        } else {
            glDisable(GL_DEPTH_TEST);
        }
        if last_enable_stencil_test {
            glEnable(GL_STENCIL_TEST);
        } else {
            glDisable(GL_STENCIL_TEST);
        }
        if last_enable_scissor_test{ 
            glEnable(GL_SCISSOR_TEST);
        } else {
            glDisable(GL_SCISSOR_TEST);
        }
        if !bd.gl_profile_is_es3 && bd.gl_version >= 310 {
            if last_enable_primitive_restart {
                glEnable(GL_PRIMITIVE_RESTART);
            } else {
                glDisable(GL_PRIMITIVE_RESTART); 
            }
        }

        if bd.has_polygon_mode {
            if bd.gl_version <= 310 || bd.gl_profile_is_compat { 
                glPolygonMode(GL_FRONT, cast(GLenum) last_polygon_mode[0]);
                glPolygonMode(GL_BACK, cast(GLenum) last_polygon_mode[1]); 
            } else { 
                glPolygonMode(GL_FRONT_AND_BACK, cast(GLenum) last_polygon_mode[0]); 
            } 
        }

        glViewport(
            last_viewport[0],
            last_viewport[1],
            cast(GLsizei) last_viewport[2],
            cast(GLsizei) last_viewport[3]);
        glScissor(
            last_scissor_box[0],
            last_scissor_box[1],
            cast(GLsizei) last_scissor_box[2],
            cast(GLsizei) last_scissor_box[3]
        );
    }
}

ImGui_ImplOpenGL3_GetBackendData :: () -> *ImGui_ImplOpenGL3_Data {
    if ImGui.GetCurrentContext() {
        return 
            cast(*ImGui_ImplOpenGL3_Data) ImGui.GetIO().BackendRendererUserData;
    }

    return null;
}

GL_CALL :: (code: Code, loc := #caller_location) #expand {
    // this might get called from a fresh push_context so we do this
    log_install(); 

    #insert code;
    gl_err := glGetError();
    if gl_err != 0 {
        log_error(
            "GL error: 0x% at %:%",
            formatInt(gl_err, base=16),
            loc.fully_pathed_filename, 
            loc.line_number
        );
    }   
}

// not implemented in bindings
GetPixels :: (tex: *ImGui.ImTextureData) -> *void {
    assert(tex.Pixels != null);
    return tex.Pixels;
}
GetPixelsAt :: (tex: *ImGui.ImTextureData, x: s32, y: s32) -> *void {
    assert(tex.Pixels != null);
    return tex.Pixels + (x + y * tex.Width) * tex.BytesPerPixel;
}

SetTexID :: (tex: *ImGui.ImTextureData, tex_id: ImGui.ImTextureID) {
    tex.TexID = tex_id;
}
SetStatus :: (tex: *ImGui.ImTextureData, status: ImGui.ImTextureStatus) {
    tex.Status = status;
    if status == ImGui.ImTextureStatus.ImTextureStatus_Destroyed &&
        !tex.WantDestroyNextFrame &&
        tex.Pixels != null {
            tex.Status = ImGui.ImTextureStatus.ImTextureStatus_WantCreate;
        }
    }


ImGui_ImplOpenGL3_UpdateTexture :: (tex: *ImGui.ImTextureData) {
    if tex.Status == ImGui.ImTextureStatus.ImTextureStatus_WantCreate ||
       tex.Status == ImGui.ImTextureStatus.ImTextureStatus_WantUpdates {
        #if GL_UNPACK_ROW_LENGTH { 
            GL_CALL(glPixelStorei(GL_UNPACK_ROW_LENGTH, 0));
        }
        #if GL_UNPACK_ALIGNMENT {
            GL_CALL(glPixelStorei(GL_UNPACK_ALIGNMENT, 1));
        }
    }

    if tex.Status == ImGui.ImTextureStatus.ImTextureStatus_WantCreate {
        assert(tex.TexID == 0 && tex.BackendUserData == null);
        assert(tex.Format == ImGui.ImTextureFormat.ImTextureFormat_RGBA32);
        pixels := GetPixels(tex);
        gl_texture_id: GLuint = 0;

        last_texture: GLint;
        GL_CALL(glGetIntegerv(GL_TEXTURE_BINDING_2D, *last_texture));
        GL_CALL(glGenTextures(1, *gl_texture_id));
        GL_CALL(glBindTexture(GL_TEXTURE_2D, gl_texture_id));
        GL_CALL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR));
        GL_CALL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR));
        GL_CALL(glTexParameteri(
            GL_TEXTURE_2D,
            GL_TEXTURE_WRAP_S,
            GL_CLAMP_TO_EDGE
        ));
        GL_CALL(glTexParameteri(
            GL_TEXTURE_2D,
            GL_TEXTURE_WRAP_T,
            GL_CLAMP_TO_EDGE
        ));
        GL_CALL(glTexImage2D(
            GL_TEXTURE_2D,
            0,
            GL_RGBA,
            cast(u32) tex.Width,
            cast(u32) tex.Height,
            0,
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            pixels
        ));

        SetTexID(tex, cast(ImGui.ImTextureID) cast(u64) gl_texture_id);
        SetStatus(tex, ImGui.ImTextureStatus.ImTextureStatus_OK);

        GL_CALL(glBindTexture(GL_TEXTURE_2D, cast(u32) last_texture));
    } else if tex.Status == ImGui.ImTextureStatus.ImTextureStatus_WantUpdates {
        last_texture: GLint;
        GL_CALL(glGetIntegerv(GL_TEXTURE_BINDING_2D, *last_texture));

        gl_tex_id := cast(GLuint) cast(u64) tex.TexID;
        GL_CALL(glBindTexture(GL_TEXTURE_2D, gl_tex_id));
        
        #if GL_UNPACK_ROW_LENGTH {
            GL_CALL(glPixelStorei(GL_UNPACK_ROW_LENGTH, tex.Width));
            for r: tex.Updates {
                GL_CALL(glTexSubImage2D(
                    GL_TEXTURE_2D,
                    0,
                    r.x,
                    r.y,
                    r.w,
                    r.h,
                    GL_RGBA,
                    GL_UNSIGNED_BYTE,
                    GetPixelsAt(tex, r.x, r.y)
                ));
            }
            GL_CALL(glPixelStorei(GL_UNPACK_ROW_LENGTH, 0));
        } else {
            bd := ImGui_ImplOpenGL3_GetBackendData();
            for r: tex.Updates {
                src_pitch: s32 = r.w * tex.BytesPerPixel;
                bd.TempBuffer.resize(r.h * src_pitch);
                out_p: *u8 = bd.TempBuffer.Data;
                for y: 0..r.h - 1 {
                    out_p = out_p + src_pitch;
                    memcpy(out_p, tex.GetPixelsAt(r.x, r.y + y), src_pitch);
                }
                assert(out_p == bd.TempBuffer.end());
                GL_CALL(glTexSubImage2D(
                    GL_TEXTURE_2D,
                    0,
                    r.x,
                    r.y,
                    r.w,
                    r.h,
                    GL_RGBA,
                    GL_UNSIGNED_BYTE,
                    bd.TempBuffer.Data
                ));
            }
        }
        SetStatus(tex, ImGui.ImTextureStatus.ImTextureStatus_OK);
        GL_CALL(glBindTexture(GL_TEXTURE_2D, cast(u32) last_texture));
    } else if tex.Status == ImGui.ImTextureStatus.ImTextureStatus_WantDestroy &&
        tex.UnusedFrames > 0 {
        ImGui_ImplOpenGL3_DestroyTexture(tex);
    }
}

ImGui_ImplOpenGL3_DestroyTexture :: (tex: *ImGui.ImTextureData)
{
    gl_tex_id := cast(GLuint) cast(u64) tex.TexID;
    glDeleteTextures(1, *gl_tex_id);

    SetTexID(tex, ImGui.ImTextureID_Invalid);
    SetStatus(tex, ImGui.ImTextureStatus.ImTextureStatus_Destroyed);
}

ImGui_ImplOpenGL3_SetupRenderState :: (
    draw_data: *ImGui.ImDrawData,
    fb_width: s32,
    fb_height: s32,
    vertex_array_object: GLuint
) {
    bd := ImGui_ImplOpenGL3_GetBackendData();

    glEnable(GL_BLEND);
    glBlendEquation(GL_FUNC_ADD);
    glBlendFuncSeparate(
        GL_SRC_ALPHA,
        GL_ONE_MINUS_SRC_ALPHA,
        GL_ONE,
        GL_ONE_MINUS_SRC_ALPHA
    );
    glDisable(GL_CULL_FACE);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_STENCIL_TEST);
    glEnable(GL_SCISSOR_TEST);
    if !bd.gl_profile_is_es3 && bd.gl_version >= 310 {
        glDisable(GL_PRIMITIVE_RESTART);
    }
    if bd.has_polygon_mode {
        glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    }

    #if GL_CLIP_ORIGIN {
        clip_origin_lower_left: bool = true;
        if bd.has_clip_origin {
            current_clip_origin: GLenum = 0;
            glGetIntegerv(GL_CLIP_ORIGIN, cast(*GLint) *current_clip_origin);
            if current_clip_origin == GL_UPPER_LEFT {
                clip_origin_lower_left = false;
            }
        }
    }

    GL_CALL(glViewport(0, 0, cast(GLsizei) fb_width, cast(GLsizei) fb_height));
    L: float = draw_data.DisplayPos.x;
    R: float = draw_data.DisplayPos.x + draw_data.DisplaySize.x;
    T: float = draw_data.DisplayPos.y;
    B: float = draw_data.DisplayPos.y + draw_data.DisplaySize.y;
    #if GL_CLIP_ORIGIN {
        if !clip_origin_lower_left { 
            tmp: float = T;
            T = B;
            B = tmp;
        }
    }
    ortho_projection: [4][4] float = .[
        .[2.0/(R-L),   0.0,         0.0, 0.0],
        .[0.0,         2.0/(T-B),   0.0, 0.0],
        .[0.0,         0.0,        -1.0, 0.0],
        .[(R+L)/(L-R), (T+B)/(B-T), 0.0, 1.0],
    ];
    glUseProgram(bd.shader_handle);
    glUniform1i(bd.attrib_location_tex, 0);
    glUniformMatrix4fv(
        bd.attrib_location_proj_mtx,
        1,
        GL_FALSE,
        *ortho_projection[0][0]
    );

    if bd.has_bind_sampler {
        glBindSampler(0, 0);
    }

    glBindVertexArray(vertex_array_object);

    GL_CALL(glBindBuffer(GL_ARRAY_BUFFER, bd.vbo_handle));
    GL_CALL(glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, bd.elements_handle));
    GL_CALL(glEnableVertexAttribArray(cast(u32) bd.attrib_location_vtx_pos));
    GL_CALL(glEnableVertexAttribArray(cast(u32) bd.attrib_location_vtx_uv));
    GL_CALL(glEnableVertexAttribArray(cast(u32) bd.attrib_location_vtx_color));
    dummy: ImGui.ImDrawVert;
    pos_offset := cast(u64) *dummy.pos - cast(u64) *dummy;
    uv_offset := cast(u64) *dummy.uv - cast(u64) *dummy;
    col_offset := cast(u64) *dummy.col - cast(u64) *dummy;
    GL_CALL(glVertexAttribPointer(
        cast(u32) bd.attrib_location_vtx_pos,
        2,
        GL_FLOAT,
        GL_FALSE,
        size_of(ImGui.ImDrawVert),
        cast(*void) pos_offset
    ));
    GL_CALL(glVertexAttribPointer(
        cast(u32) bd.attrib_location_vtx_uv,
        2,
        GL_FLOAT,
        GL_FALSE,
        size_of(ImGui.ImDrawVert),
        cast(*void) uv_offset
    ));
    GL_CALL(glVertexAttribPointer(
        cast(u32) bd.attrib_location_vtx_color,
        4,
        GL_UNSIGNED_BYTE,
        GL_TRUE,
        size_of(ImGui.ImDrawVert),
        cast(*void) col_offset
    ));
}

GetTexID :: () {

}

GetTexID :: (cmd: *ImGui.ImDrawCmd) -> ImGui.ImTextureID {
    tex_id: ImGui.ImTextureID;
    if cmd.TexRef._TexData {
        tex_id = cmd.TexRef._TexData.TexID;
    } else {
        tex_id = cmd.TexRef._TexID;
    }
    if cmd.TexRef._TexData != null {
        assert(
            tex_id != ImGui.ImTextureID_Invalid,
            "ImDrawCmd is referring to ImTextureData that wasn't uploaded to graphics system. Backend must call ImTextureData::SetTexID() after handling ImTextureStatus_WantCreate request!"
        );
    }

    return tex_id;
}

ImGui_ImplOpenGL3_Shutdown :: () {
    bd := ImGui_ImplOpenGL3_GetBackendData();
    assert(bd != null, "No renderer backend to shutdown, or already shutdown?");
    io := ImGui.GetIO();
    platform_io := ImGui.GetPlatformIO();

    ImGui_ImplOpenGL3_ShutdownMultiViewportSupport();
    ImGui_ImplOpenGL3_DestroyDeviceObjects();

    io.BackendRendererName = null;
    io.BackendRendererUserData = null;
    io.BackendFlags_ &= ~(
        ImGui.BackendFlags.ImGuiBackendFlags_RendererHasVtxOffset |
        ImGui.BackendFlags.ImGuiBackendFlags_RendererHasTextures |
        ImGui.BackendFlags.ImGuiBackendFlags_RendererHasViewports
    );
    ImGui.PlatformIO.ClearRendererHandlers(platform_io);
    array_reset(*bd.temp_buffer);
    free(bd);
}

ImGui_ImplOpenGL3_ShutdownMultiViewportSupport :: () {
    ImGui.DestroyPlatformWindows();
}

ImGui_ImplOpenGL3_DestroyDeviceObjects :: () {
    bd := ImGui_ImplOpenGL3_GetBackendData();
    if bd.vbo_handle {
        glDeleteBuffers(1, *bd.vbo_handle);
        bd.vbo_handle = 0;
    }
    if bd.elements_handle {
        glDeleteBuffers(1, *bd.elements_handle);
        bd.elements_handle = 0;
    }
    if bd.shader_handle {
        glDeleteProgram(bd.shader_handle);
        bd.shader_handle = 0;
    }

    for tex: ImGui.GetPlatformIO().Textures {
        if tex.RefCount == 1 {
            ImGui_ImplOpenGL3_DestroyTexture(tex);
        }
    }
}

ImGui_ImplGlfw_Shutdown :: () {
    bd := ImGui_ImplGlfw_GetBackendData();
    assert(bd != null, "No platform backend to shutdown, or already shutdown?");

    io := ImGui.GetIO();
    platform_io := ImGui.GetPlatformIO();

    ImGui_ImplGlfw_ShutdownMultiViewportSupport();
    if bd.installed_callbacks {
        ImGui_ImplGlfw_RestoreCallbacks(bd.window);
    }
    for cursor_n: 0..ImGui.MouseCursor.ImGuiMouseCursor_COUNT - 1 {
        glfwDestroyCursor(bd.mouse_cursors[cursor_n]);
    }

    #if OS == .WINDOWS {
        main_viewport := ImGui.GetMainViewport();
        SetPropA(
            cast(HWND) main_viewport.PlatformHandleRaw,
            "IMGUI_BACKEND_DATA",
            null
        );
        SetWindowLongPtrW(
            cast(HWND) main_viewport.PlatformHandleRaw,
            GWLP_WNDPROC,
            cast(LONG_PTR) bd.prev_wnd_proc
        );
        bd.prev_wnd_proc = null;
    }

    #if GLFW_HAS_X11 {
        if bd.x_11_module != null {
            dlclose(bd.x_11_module);
        }
    }

    io.BackendPlatformName = null;
    io.BackendPlatformUserData = null;
    io.BackendFlags_ &= ~(
        ImGui.BackendFlags.ImGuiBackendFlags_HasMouseCursors |
        ImGui.BackendFlags.ImGuiBackendFlags_HasSetMousePos |
        ImGui.BackendFlags.ImGuiBackendFlags_HasGamepad |
        ImGui.BackendFlags.ImGuiBackendFlags_PlatformHasViewports |
        ImGui.BackendFlags.ImGuiBackendFlags_HasMouseHoveredViewport
    );
    ImGui.PlatformIO.ClearPlatformHandlers(platform_io);
    ImGui_ImplGlfw_ContextMap_Remove(bd.window);
    free(bd);
    array_free(context_map);
}

ImGui_ImplGlfw_ShutdownMultiViewportSupport :: () {
    ImGui.DestroyPlatformWindows();
}

ImGui_ImplGlfw_RestoreCallbacks :: (window: *GLFWwindow) {
    bd := ImGui_ImplGlfw_GetBackendData(window);
    assert(bd.installed_callbacks == true, "Callbacks not installed!");
    assert(bd.window == window);

    glfwSetWindowFocusCallback(window, bd.prev_user_callback_window_focus);
    glfwSetCursorEnterCallback(window, bd.prev_user_callback_cursor_enter);
    glfwSetCursorPosCallback(window, bd.prev_user_callback_cursor_pos);
    glfwSetMouseButtonCallback(window, bd.prev_user_callback_mousebutton);
    glfwSetScrollCallback(window, bd.prev_user_callback_scroll);
    glfwSetKeyCallback(window, bd.prev_user_callback_key);
    glfwSetCharCallback(window, bd.prev_user_callback_char);
    glfwSetMonitorCallback(bd.prev_user_callback_monitor);
    bd.installed_callbacks = false;
    bd.prev_user_callback_window_focus = null;
    bd.prev_user_callback_cursor_enter = null;
    bd.prev_user_callback_cursor_pos = null;
    bd.prev_user_callback_mousebutton = null;
    bd.prev_user_callback_scroll = null;
    bd.prev_user_callback_key = null;
    bd.prev_user_callback_char = null;
    bd.prev_user_callback_monitor = null;
}

ImGui_ImplGlfw_ContextMap_Remove :: (window: *GLFWwindow) {
    for entry, index: context_map {
        if entry.window == window {
            array_unordered_remove_by_index(*context_map, index);
            if context_map.count == 0 {
                array_reset(*context_map);
            }
            return; 
        }
    }
}

ImGui_ImplOpenGL3_NewFrame :: () {
    bd := ImGui_ImplOpenGL3_GetBackendData();
    assert(
        bd != null,
        "Context or backend not initialized! Did you call ImGui_ImplOpenGL3_Init()?"
    );

    if !bd.shader_handle {
        if !ImGui_ImplOpenGL3_CreateDeviceObjects() {
            assert(false, "ImGui_ImplOpenGL3_CreateDeviceObjects() failed!");
        }
    }
}

ImGui_ImplOpenGL3_CreateDeviceObjects :: () -> bool {
    bd := ImGui_ImplOpenGL3_GetBackendData();

    last_texture: GLint;
    last_array_buffer: GLint;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, *last_texture);
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, *last_array_buffer);
    last_pixel_unpack_buffer: GLint = 0;
    if bd.gl_version >= 210 {
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, *last_pixel_unpack_buffer);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    }

    last_vertex_array: GLint;
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING, *last_vertex_array);

    // glsl_version: s32 = 130;
    // sscanf(bd.glsl_version_string, "#version %", *glsl_version);

    glsl_version: s32 = 130;
    if bd.glsl_version_string[0] {
        version_string := to_string(bd.glsl_version_string.data);
        prefix :: "#version ";
        if begins_with(version_string, prefix) {
            version_str := advance(version_string, prefix.count);
            glsl_version = cast(s32) string_to_int(version_str);
        }
    }

    vertex_shader_glsl_120 :: #string DONE
uniform mat4 ProjMtx;
attribute vec2 Position;
attribute vec2 UV;
attribute vec4 Color;
varying vec2 Frag_UV;
varying vec4 Frag_Color;
void main() {
    Frag_UV = UV;
    Frag_Color = Color;
    gl_Position = ProjMtx * vec4(Position.xy,0,1);
}
DONE;

    vertex_shader_glsl_130 :: #string DONE
uniform mat4 ProjMtx;
in vec2 Position;
in vec2 UV;
in vec4 Color;
out vec2 Frag_UV;
out vec4 Frag_Color;
void main() {
    Frag_UV = UV;
    Frag_Color = Color;
    gl_Position = ProjMtx * vec4(Position.xy,0,1);
}
DONE;

    vertex_shader_glsl_300_es :: #string DONE
precision highp float;
layout (location = 0) in vec2 Position;
layout (location = 1) in vec2 UV;
layout (location = 2) in vec4 Color;
uniform mat4 ProjMtx;
out vec2 Frag_UV;
out vec4 Frag_Color;
void main() {
    Frag_UV = UV;
    Frag_Color = Color;
    gl_Position = ProjMtx * vec4(Position.xy,0,1);
}
DONE;

    vertex_shader_glsl_410_core :: #string DONE
layout (location = 0) in vec2 Position;
layout (location = 1) in vec2 UV;
layout (location = 2) in vec4 Color;
uniform mat4 ProjMtx;
out vec2 Frag_UV;
out vec4 Frag_Color;
void main() {
    Frag_UV = UV;
    Frag_Color = Color;
    gl_Position = ProjMtx * vec4(Position.xy,0,1);
}
DONE;

    fragment_shader_glsl_120 :: #string DONE
#ifdef GL_ES
precision mediump float;
#endif
uniform sampler2D Texture;
varying vec2 Frag_UV;
varying vec4 Frag_Color;
void main() {
    gl_FragColor = Frag_Color * texture2D(Texture, Frag_UV.st);
}
DONE;
 
fragment_shader_glsl_130 :: #string DONE
uniform sampler2D Texture;
in vec2 Frag_UV;
in vec4 Frag_Color;
out vec4 Out_Color;
void main() {
    Out_Color = Frag_Color * texture(Texture, Frag_UV.st);
}
DONE;

    fragment_shader_glsl_300_es :: #string DONE
precision mediump float;
uniform sampler2D Texture;
in vec2 Frag_UV;
in vec4 Frag_Color;
layout (location = 0) out vec4 Out_Color;
void main() {
    Out_Color = Frag_Color * texture(Texture, Frag_UV.st);
}
DONE;

    fragment_shader_glsl_410_core :: #string DONE
in vec2 Frag_UV;
in vec4 Frag_Color;
uniform sampler2D Texture;
layout (location = 0) out vec4 Out_Color;
void main() {
    Out_Color = Frag_Color * texture(Texture, Frag_UV.st);
}
DONE;

    vertex_shader: *GLchar = null;
    fragment_shader: *GLchar = null;
    if glsl_version < 130 {
        vertex_shader = vertex_shader_glsl_120;
        fragment_shader = fragment_shader_glsl_120;
    } else if glsl_version >= 410 {
        vertex_shader = vertex_shader_glsl_410_core;
        fragment_shader = fragment_shader_glsl_410_core;
    } else if glsl_version == 300 {
        vertex_shader = vertex_shader_glsl_300_es;
        fragment_shader = fragment_shader_glsl_300_es;
    } else {
        vertex_shader = vertex_shader_glsl_130;
        fragment_shader = fragment_shader_glsl_130;
    }

    vertex_shader_with_version: [2] *GLchar = .[
        bd.glsl_version_string.data,
        vertex_shader
    ];
    vert_handle: GLuint;
    
    GL_CALL(#code {
        vert_handle = glCreateShader(GL_VERTEX_SHADER);
    });
    glShaderSource(vert_handle, 2, vertex_shader_with_version.data, null);
    glCompileShader(vert_handle);
    if !CheckShader(vert_handle, "vertex shader") {
        return false;
    }

    fragment_shader_with_version: [2] *GLchar = .[
        bd.glsl_version_string.data,
        fragment_shader
    ];
    frag_handle: GLuint;
    GL_CALL(#code {
        frag_handle = glCreateShader(GL_FRAGMENT_SHADER);
    });
    glShaderSource(frag_handle, 2, fragment_shader_with_version.data, null);
    glCompileShader(frag_handle);
    if !CheckShader(frag_handle, "fragment shader") {
        return false;
    }

    bd.shader_handle = glCreateProgram();
    glAttachShader(bd.shader_handle, vert_handle);
    glAttachShader(bd.shader_handle, frag_handle);
    glLinkProgram(bd.shader_handle);
    if !CheckProgram(bd.shader_handle, "shader program") {
        return false;
    }

    glDetachShader(bd.shader_handle, vert_handle);
    glDetachShader(bd.shader_handle, frag_handle);
    glDeleteShader(vert_handle);
    glDeleteShader(frag_handle);

    bd.attrib_location_tex = glGetUniformLocation(bd.shader_handle, "Texture");
    bd.attrib_location_proj_mtx = glGetUniformLocation(bd.shader_handle, "ProjMtx");
    bd.attrib_location_vtx_pos = glGetAttribLocation(bd.shader_handle, "Position");
    bd.attrib_location_vtx_uv = glGetAttribLocation(bd.shader_handle, "UV");
    bd.attrib_location_vtx_color = glGetAttribLocation(bd.shader_handle, "Color");

    glGenBuffers(1, *bd.vbo_handle);
    glGenBuffers(1, *bd.elements_handle);

    glBindTexture(GL_TEXTURE_2D, cast(u32) last_texture);
    glBindBuffer(GL_ARRAY_BUFFER, cast(u32) last_array_buffer);
    
    if bd.gl_version >= 210 { 
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, cast(u32) last_pixel_unpack_buffer);
    }

    glBindVertexArray(cast(u32) last_vertex_array);

    return true;
}

CheckShader :: (handle: GLuint, desc: *u8) -> bool {
    bd := ImGui_ImplOpenGL3_GetBackendData();
    status: GLint = 0;
    log_length: GLint = 0;
    glGetShaderiv(handle, GL_COMPILE_STATUS, *status);
    glGetShaderiv(handle, GL_INFO_LOG_LENGTH, *log_length);
    if cast(GLboolean) status == GL_FALSE {
        log_error(
            "ImGui_ImplOpenGL3_CreateDeviceObjects: failed to compile %! With GLSL: %",
            desc, 
            to_string(bd.glsl_version_string)
        );
    }
    if log_length > 1 {
        buf: [..] u8;
        array_resize(*buf, cast(s32) (log_length + 1));
        glGetShaderInfoLog(
            handle,
            cast(u32) log_length,
            null,
            cast(*GLchar) buf.data
        );
        log_error("%", buf.data);
    }
    return cast(GLboolean) status == GL_TRUE;
}

CheckProgram :: (handle: GLuint, desc: *u8) -> bool {
    bd := ImGui_ImplOpenGL3_GetBackendData();
    status: GLint = 0;
    log_length: GLint = 0;
    glGetProgramiv(handle, GL_LINK_STATUS, *status);
    glGetProgramiv(handle, GL_INFO_LOG_LENGTH, *log_length);
    if cast(GLboolean) status == GL_FALSE {
        log_error(
            "ImGui_ImplOpenGL3_CreateDeviceObjects: failed to link %! With GLSL %",
            desc,
            bd.glsl_version_string
        );
    }
    if (log_length > 1) {
        buf: [..] u8;
        array_resize(*buf, cast(s32) (log_length + 1));
        glGetProgramInfoLog(
            handle,
            cast(u32) log_length,
            null,
            cast(*GLchar) buf.data
        );
        log_error("%", buf.data);
    }
    return cast(GLboolean) status == GL_TRUE;
}

ImGui_ImplGlfw_NewFrame :: () {
    io := ImGui.GetIO();
    bd := ImGui_ImplGlfw_GetBackendData();
    assert(
        bd != null,
        "Context or backend not initialized! Did you call ImGui_ImplGlfw_InitForXXX()?"
    );

    ImGui_ImplGlfw_GetWindowSizeAndFramebufferScale(
        bd.window,
        *io.DisplaySize, 
        *io.DisplayFramebufferScale
    );
    ImGui_ImplGlfw_UpdateMonitors();

    current_time: float64 = glfwGetTime();
    if current_time <= bd.time {
        current_time = bd.time + 0.00001;
    }
    io.DeltaTime = ifx bd.time > 0.0 then cast(float) (current_time - bd.time) else cast(float) (1.0 / 60.0);
    bd.time = current_time;

    bd.mouse_ignore_button_up = false;
    ImGui_ImplGlfw_UpdateMouseData();
    ImGui_ImplGlfw_UpdateMouseCursor();

    // ImGui_ImplGlfw_UpdateGamepads(); // @ToDo: implement gamepad function elsewhere
}

ImGui_ImplGlfw_GetWindowSizeAndFramebufferScale :: (
    window: *GLFWwindow,
    out_size: *ImGui.ImVec2,
    out_framebuffer_scale: *ImGui.ImVec2) {
    w: s32;
    h: s32;
    display_w: s32;
    display_h: s32;
    glfwGetWindowSize(window, *w, *h);
    glfwGetFramebufferSize(window, *display_w, *display_h);
    fb_scale_x := ifx w > 0 then cast(float) display_w / cast(float) w else 1.0;
    fb_scale_y := ifx h > 0 then cast(float) display_h / cast(float) h else 1.0;
    #if GLFW_HAS_WAYLAND {
        bd := ImGui_ImplGlfw_GetBackendData(window);
        if !bd.is_wayland {
            fb_scale_x = fb_scale_y = 1.0;
        }
    }
    if out_size != null {
        out_size.* = ImGui.ImVec2.{cast(float) w, cast(float) h};
    }
    if out_framebuffer_scale != null {
        out_framebuffer_scale.* = ImGui.ImVec2.{fb_scale_x, fb_scale_y};
    }
}

ImGui_ImplGlfw_UpdateMonitors :: () {
    platform_io := ImGui.GetPlatformIO();

    monitors_count: s32 = 0;
    glfw_monitors: **GLFWmonitor = glfwGetMonitors(*monitors_count);
    if monitors_count == 0 {
        return;
    }

    platform_io.Monitors.Size = 0; // platform_io.Monitors.resize(0);
    for n: 0..monitors_count - 1 {
        monitor: ImGui.PlatformMonitor;
        x: s32;
        y: s32;
        glfwGetMonitorPos(glfw_monitors[n], *x, *y);
        vid_mode := glfwGetVideoMode(glfw_monitors[n]);
        if vid_mode == null {
            continue;
        }
        monitor.MainPos = ImGui.ImVec2.{cast(float) x, cast(float) y};
        monitor.WorkPos = ImGui.ImVec2.{cast(float) x, cast(float) y};
        monitor.MainSize = ImGui.ImVec2.{
            cast(float) vid_mode.width,
            cast(float) vid_mode.height
        };
        monitor.WorkSize = ImGui.ImVec2.{
            cast(float) vid_mode.width,
            cast(float) vid_mode.height
        };
        w: s32;
        h: s32;
        glfwGetMonitorWorkarea(glfw_monitors[n], *x, *y, *w, *h);
        if w > 0 && h > 0 {
            monitor.WorkPos = ImGui.ImVec2.{cast(float) x, cast(float) y};
            monitor.WorkSize = ImGui.ImVec2.{cast(float) w, cast(float) h};
        }
        scale := ImGui_ImplGlfw_GetContentScaleForMonitor(glfw_monitors[n]);
        if scale == 0.0 {
            continue;
        }
        monitor.DpiScale = scale;
        monitor.PlatformHandle = cast(*void) glfw_monitors[n];
        ImGui.vector_push_back(*platform_io.Monitors, monitor); // platform_io.Monitors.push_back(monitor);
        log("");
    }
}

ImGui_ImplGlfw_GetContentScaleForMonitor :: (monitor: *GLFWmonitor) -> float {
    #if GLFW_HAS_WAYLAND {
        if ImGui_ImplGlfw_IsWayland(){
            return 1.0;
        }
    }
    #if OS != .MACOS {
        x_scale: float;
        y_scale: float;
        glfwGetMonitorContentScale(monitor, *x_scale, *y_scale);
        return x_scale;
    } else {
        return 1.0;
    }
}

ImGui_ImplGlfw_UpdateMouseData :: () {
    bd := ImGui_ImplGlfw_GetBackendData();
    io := ImGui.GetIO();
    platform_io := ImGui.GetPlatformIO();

    mouse_viewport_id: ImGui.ID = 0;
    mouse_pos_prev: ImGui.ImVec2 = io.MousePos;
    for n: 0..platform_io.Viewports.Size - 1 {
        viewport := platform_io.Viewports[n];
        window := cast(*GLFWwindow) viewport.PlatformHandle;

        is_window_focused: bool = glfwGetWindowAttrib(window, GLFW_FOCUSED) != 0;
     
        if is_window_focused {
            if io.WantSetMousePos {
                glfwSetCursorPos(
                    window,
                    cast(float64) (mouse_pos_prev.x - viewport.Pos.x),
                    cast(float64) (mouse_pos_prev.y - viewport.Pos.y)
                );
            }

            if bd.mouse_window == null {
                mouse_x: float64;
                mouse_y: float64;
                glfwGetCursorPos(window, *mouse_x, *mouse_y);
                if io.ConfigFlags_ &
                    ImGui.ConfigFlags.ImGuiConfigFlags_ViewportsEnable {
                    window_x: s32;
                    window_y: s32;
                    glfwGetWindowPos(window, *window_x, *window_y);
                    mouse_x += window_x;
                    mouse_y += window_y;
                }
                bd.last_valid_mouse_pos = ImGui.ImVec2.{
                    cast(float) mouse_x,
                    cast(float) mouse_y
                };
                ImGui.IO.AddMousePosEvent(io, cast(float) mouse_x, cast(float) mouse_y);
            }
        }

        if glfwGetWindowAttrib(window, GLFW_HOVERED) {
            mouse_viewport_id = viewport.ID_;
        }
    }

    if io.BackendFlags_ &
        ImGui.BackendFlags.ImGuiBackendFlags_HasMouseHoveredViewport {
        ImGui.IO.AddMouseViewportEvent(io, mouse_viewport_id);
    }
}

ImGui_ImplGlfw_UpdateMouseCursor :: () {
    io := ImGui.GetIO();
    bd := ImGui_ImplGlfw_GetBackendData();
    if (io.ConfigFlags_ & ImGui.ConfigFlags.ImGuiConfigFlags_NoMouseCursorChange) || 
        glfwGetInputMode(bd.window, GLFW_CURSOR) == GLFW_CURSOR_DISABLED {
        return;
    }

    imgui_cursor := ImGui.GetMouseCursor();
    platform_io := ImGui.GetPlatformIO();
    for n: 0..platform_io.Viewports.Size - 1 {
        window := cast(*GLFWwindow) platform_io.Viewports[n].PlatformHandle;
        if imgui_cursor == ImGui.MouseCursor.ImGuiMouseCursor_None ||
            io.MouseDrawCursor {
            if bd.last_mouse_cursor != null {
                glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
                bd.last_mouse_cursor = null;
            }
        } else {
            cursor: *GLFWcursor;
            if bd.mouse_cursors[imgui_cursor] {
                cursor = bd.mouse_cursors[imgui_cursor];
            } else { 
                bd.mouse_cursors[ImGui.MouseCursor.ImGuiMouseCursor_Arrow];
            }
            if bd.last_mouse_cursor != cursor {
                glfwSetCursor(window, cursor);
                bd.last_mouse_cursor = cursor;
            }
            glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
        }
    }
}

ImGui_ImplGlfw_InitMultiViewportSupport :: () {
    bd := ImGui_ImplGlfw_GetBackendData();
    platform_io := ImGui.GetPlatformIO();
    platform_io.Platform_CreateWindow = ImGui_ImplGlfw_CreateWindow;
    platform_io.Platform_DestroyWindow = ImGui_ImplGlfw_DestroyWindow;
    platform_io.Platform_ShowWindow = ImGui_ImplGlfw_ShowWindow;
    platform_io.Platform_SetWindowPos = ImGui_ImplGlfw_SetWindowPos;
    platform_io.Platform_GetWindowPos = ImGui_ImplGlfw_GetWindowPos;
    platform_io.Platform_SetWindowSize = ImGui_ImplGlfw_SetWindowSize;
    platform_io.Platform_GetWindowSize = ImGui_ImplGlfw_GetWindowSize;
    platform_io.Platform_GetWindowFramebufferScale = ImGui_ImplGlfw_GetWindowFramebufferScale;
    platform_io.Platform_SetWindowFocus = ImGui_ImplGlfw_SetWindowFocus;
    platform_io.Platform_GetWindowFocus = ImGui_ImplGlfw_GetWindowFocus;
    platform_io.Platform_GetWindowMinimized = ImGui_ImplGlfw_GetWindowMinimized;
    platform_io.Platform_SetWindowTitle = ImGui_ImplGlfw_SetWindowTitle;
    platform_io.Platform_RenderWindow = ImGui_ImplGlfw_RenderWindow;
    platform_io.Platform_SwapBuffers = ImGui_ImplGlfw_SwapBuffers;
    platform_io.Platform_SetWindowAlpha = ImGui_ImplGlfw_SetWindowAlpha;

    main_viewport := ImGui.GetMainViewport();
    vd := New(ImGui_ImplGlfw_ViewportData);
    vd.window = bd.window;
    vd.window_owned = false;
    main_viewport.PlatformUserData = vd;
    main_viewport.PlatformHandle = cast(*void) bd.window;
}

ImGui_ImplGlfw_ViewportData :: struct {
    window: *GLFWwindow;
    window_owned: bool;
    ignore_window_pos_event_frame: s32 = -1;
    ignore_window_size_event_frame: s32 = -1;
    #if OS == .WINDOWS {
        prev_wnd_proc: WNDPROC;
    }

    // ~ImGui_ImplGlfw_ViewportData() { IM_ASSERT(Window == nullptr); } // @ToDo: move this assert
};

ImGui_ImplGlfw_CreateWindow :: (viewport: *ImGui.Viewport) #c_call {
    push_context {
        bd := ImGui_ImplGlfw_GetBackendData();
        vd := New(ImGui_ImplGlfw_ViewportData);
        viewport.PlatformUserData = vd;

        #if OS == .LINUX {
            bd.mouse_ignore_button_up_wait_for_focus_loss = true;
        }

        glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
        glfwWindowHint(GLFW_FOCUSED, GLFW_FALSE);
        glfwWindowHint(GLFW_FOCUS_ON_SHOW, GLFW_FALSE);
        glfwWindowHint(GLFW_DECORATED, cast(s32) ifx (viewport.Flags & ImGui.ViewportFlags.ImGuiViewportFlags_NoDecoration) then false else true);
        glfwWindowHint(GLFW_FLOATING, cast(s32) ifx (viewport.Flags & ImGui.ViewportFlags.ImGuiViewportFlags_TopMost) then true else false);
        share_window := bd.window;
        vd.window = glfwCreateWindow(cast(s32) viewport.Size.x, cast(s32) viewport.Size.y, "No Title Yet", null, share_window);
        vd.window_owned = true;
        ImGui_ImplGlfw_ContextMap_Add(vd.window, bd.ctx);
        viewport.PlatformHandle = cast(*void) vd.window;
        #if OS != .MACOS && OS != .WINDOWS {
            ImGui_ImplGlfw_SetWindowFloating(bd, vd.window);
        }
        #if OS == .WINDOWS {
            viewport.PlatformHandleRaw = glfwGetWin32Window(vd.window);
            SetPropA(cast(HWND) viewport.PlatformHandleRaw, "IMGUI_BACKEND_DATA", bd);
        } else #if OS == .MACOS {
            viewport.PlatformHandleRaw = cast(*void) glfwGetCocoaWindow(vd.window);
        }
        glfwSetWindowPos(vd.window, cast(s32) viewport.Pos.x, cast(s32) viewport.Pos.y);

        // Install GLFW callbacks for secondary viewports
        glfwSetWindowFocusCallback(vd.window, ImGui_ImplGlfw_WindowFocusCallback);
        glfwSetCursorEnterCallback(vd.window, ImGui_ImplGlfw_CursorEnterCallback);
        glfwSetCursorPosCallback(vd.window, ImGui_ImplGlfw_CursorPosCallback);
        glfwSetMouseButtonCallback(vd.window, ImGui_ImplGlfw_MouseButtonCallback);
        glfwSetScrollCallback(vd.window, ImGui_ImplGlfw_ScrollCallback);
        glfwSetKeyCallback(vd.window, ImGui_ImplGlfw_KeyCallback);
        glfwSetCharCallback(vd.window, ImGui_ImplGlfw_CharCallback);
        glfwSetWindowCloseCallback(vd.window, ImGui_ImplGlfw_WindowCloseCallback);
        glfwSetWindowPosCallback(vd.window, ImGui_ImplGlfw_WindowPosCallback);
        glfwSetWindowSizeCallback(vd.window, ImGui_ImplGlfw_WindowSizeCallback);
    
        glfwMakeContextCurrent(vd.window);
        glfwSwapInterval(0);
    }
}

ImGui_ImplGlfw_WindowCloseCallback :: (window: *GLFWwindow) #c_call {
    viewport := ImGui.FindViewportByPlatformHandle(window);
    if viewport {
        viewport.PlatformRequestClose = true;
    }
}

ImGui_ImplGlfw_WindowPosCallback :: (window: *GLFWwindow, s32, s32) #c_call {
    viewport := ImGui.FindViewportByPlatformHandle(window);
    if viewport {
        vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
        if vd {
            ignore_event := (ImGui.GetFrameCount() <= vd.ignore_window_pos_event_frame + 1);
            if ignore_event {
                return;
            }
        }
        viewport.PlatformRequestMove = true;
    }
}

ImGui_ImplGlfw_WindowSizeCallback :: (window: *GLFWwindow, s32, s32) #c_call {
    viewport := ImGui.FindViewportByPlatformHandle(window);
    if viewport {
        vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
        if vd {
            ignore_event := (ImGui.GetFrameCount() <= vd.ignore_window_size_event_frame + 1);
            if ignore_event {
                return;
            }
        }
        viewport.PlatformRequestResize = true;
    }
}

ImGui_ImplGlfw_DestroyWindow :: (viewport: *ImGui.Viewport) #c_call {
    push_context {
        bd := ImGui_ImplGlfw_GetBackendData();
        vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
        if vd {
            if vd.window_owned {

// #if !GLFW_HAS_MOUSE_PASSTHROUGH && GLFW_HAS_WINDOW_HOVERED && defined(_WIN32)
            // hwnd := cast(HWND) viewport.PlatformHandleRaw;
            // RemovePropA(hwnd, "IMGUI_VIEWPORT");
// #endif

                for i: 0..bd.key_owner_windows.count - 1 {
                    if bd.key_owner_windows[i] == vd.window {
                        ImGui_ImplGlfw_KeyCallback(vd.window, cast(s32) i, 0, GLFW_RELEASE, 0);
                    }
                }

                ImGui_ImplGlfw_ContextMap_Remove(vd.window);
                glfwDestroyWindow(vd.window);
            }
            vd.window = null;
            free(vd);
        }
        viewport.PlatformUserData = null;
        viewport.PlatformHandle = null;
    }
}

ImGui_ImplGlfw_ShowWindow :: (viewport: *ImGui.Viewport) #c_call {
    vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;

    #if OS == .WINDOWS {
        hwnd := cast(HWND) viewport.PlatformHandleRaw;
        if viewport.Flags & ImGui.ViewportFlags.ImGuiViewportFlags_NoTaskBarIcon {
            ex_style: s32 = GetWindowLongA(hwnd, GWL_EXSTYLE);
            ex_style &= ~cast(s32) WS_EX_APPWINDOW;
            ex_style |= WS_EX_TOOLWINDOW;
            SetWindowLongA(hwnd, GWL_EXSTYLE, ex_style);
        }

        SetPropA(hwnd, "IMGUI_VIEWPORT", viewport);
        vd.prev_wnd_proc = cast(WNDPROC) GetWindowLongPtrW(hwnd, GWLP_WNDPROC);
        SetWindowLongPtrW(hwnd, GWLP_WNDPROC, cast(LONG_PTR) cast(*void) ImGui_ImplGlfw_WndProc);

        if viewport.Flags & ImGui.ViewportFlags.ImGuiViewportFlags_NoFocusOnAppearing {
            ShowWindow(hwnd, SW_SHOWNA);
            return;
        }
    }

    glfwShowWindow(vd.window);
}

ImGui_ImplGlfw_GetWindowPos :: (viewport: *ImGui.Viewport) -> ImGui.ImVec2 #c_call {
    vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
    x: s32 = 0;
    y: s32 = 0;
    glfwGetWindowPos(vd.window, *x, *y);
    return ImGui.ImVec2.{cast(float) x, cast(float) y};
}

ImGui_ImplGlfw_SetWindowPos :: (viewport: *ImGui.Viewport, pos: ImGui.ImVec2) #c_call {
    vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
    vd.ignore_window_pos_event_frame = ImGui.GetFrameCount();
    glfwSetWindowPos(vd.window, cast(s32) pos.x, cast(s32) pos.y);
}

ImGui_ImplGlfw_GetWindowSize :: (viewport: *ImGui.Viewport) -> ImGui.ImVec2 #c_call {
    vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
    w: s32 = 0;
    h: s32 = 0;
    glfwGetWindowSize(vd.window, *w, *h);
    return ImGui.ImVec2.{cast(float) w, cast(float) h};
}

ImGui_ImplGlfw_SetWindowSize :: (viewport: *ImGui.Viewport, size: ImGui.ImVec2) #c_call {
    vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
    vd.ignore_window_size_event_frame = ImGui.GetFrameCount();
    glfwSetWindowSize(vd.window, cast(s32) size.x, cast(s32) size.y);
}

ImGui_ImplGlfw_GetWindowFramebufferScale :: (viewport: *ImGui.Viewport) -> ImGui.ImVec2 #c_call {
    push_context {
        vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
        framebuffer_scale: ImGui.ImVec2;
        ImGui_ImplGlfw_GetWindowSizeAndFramebufferScale(vd.window, null, *framebuffer_scale);
        return framebuffer_scale;
    }
}

ImGui_ImplGlfw_SetWindowFocus :: (viewport: *ImGui.Viewport) #c_call {
    vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
    glfwFocusWindow(vd.window);
}

ImGui_ImplGlfw_GetWindowFocus :: (viewport: *ImGui.Viewport) -> bool #c_call {
    vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
    return glfwGetWindowAttrib(vd.window, GLFW_FOCUSED) != 0;
}

ImGui_ImplGlfw_GetWindowMinimized :: (viewport: *ImGui.Viewport) -> bool #c_call {
    vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
    return glfwGetWindowAttrib(vd.window, GLFW_ICONIFIED) != 0;
}

ImGui_ImplGlfw_SetWindowTitle :: (viewport: *ImGui.Viewport, title: *u8) #c_call {
    vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
    glfwSetWindowTitle(vd.window, title);
}

ImGui_ImplGlfw_RenderWindow :: (viewport: *ImGui.Viewport, *void) #c_call {
    push_context {
        bd := ImGui_ImplGlfw_GetBackendData();
        vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
        glfwMakeContextCurrent(vd.window);
    }
}

ImGui_ImplGlfw_SwapBuffers :: (viewport: *ImGui.Viewport, *void) #c_call {
    push_context {
        bd := ImGui_ImplGlfw_GetBackendData();
        vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
        glfwMakeContextCurrent(vd.window);
        glfwSwapBuffers(vd.window);
    }
}

ImGui_ImplGlfw_SetWindowAlpha :: (viewport: *ImGui.Viewport, alpha: float) #c_call {
    vd := cast(*ImGui_ImplGlfw_ViewportData) viewport.PlatformUserData;
    glfwSetWindowOpacity(vd.window, alpha);
}

#if OS == .WINDOWS {
    GetMouseSourceFromMessageExtraInfo :: () -> ImGui.MouseSource #c_call {
        push_context {
            extra_info: LPARAM = GetMessageExtraInfo();
            if (extra_info & 0xFFFFFF80) == 0xFF515700 {
                return ImGui.MouseSource.ImGuiMouseSource_Pen;
            }
            if (extra_info & 0xFFFFFF80) == 0xFF515780 {
                return ImGui.MouseSource.ImGuiMouseSource_TouchScreen;
            }
            return ImGui.MouseSource.ImGuiMouseSource_Mouse;
        }
    }

    ImGui_ImplGlfw_WndProc :: (hWnd: HWND, msg: u32, wParam: WPARAM, lParam: LPARAM) -> LRESULT #c_call {
        push_context {
            bd := cast(*ImGui_ImplGlfw_Data) GetPropA(hWnd, "IMGUI_BACKEND_DATA");
            io := ImGui_GetIO(bd.ctx);

            if msg == {
                case WM_MOUSEMOVE; #through;
                case WM_NCMOUSEMOVE; #through;
                case WM_LBUTTONDOWN; #through; 
                case WM_LBUTTONDBLCLK; #through; 
                case WM_LBUTTONUP; #through;
                case WM_RBUTTONDOWN; #through; 
                case WM_RBUTTONDBLCLK; #through; 
                case WM_RBUTTONUP; #through;
                case WM_MBUTTONDOWN; #through; 
                case WM_MBUTTONDBLCLK; #through; 
                case WM_MBUTTONUP; #through;
                case WM_XBUTTONDOWN; #through; 
                case WM_XBUTTONDBLCLK; #through; 
                case WM_XBUTTONUP;
                    ImGui.IO.AddMouseSourceEvent(io, GetMouseSourceFromMessageExtraInfo());
            }
            return CallWindowProcW(bd.prev_wnd_proc, hWnd, msg, wParam, lParam);
        }
    }
}

#scope_file

user32   :: #library,system "user32";
