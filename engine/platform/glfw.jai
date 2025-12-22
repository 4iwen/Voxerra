#scope_file

#import "Basic";
#import "glfw";

#load "../core/input.jai";

key_callback :: (window: *GLFWwindow, key: s32, scancode: s32, action: s32, mods: s32) #c_call {
    // engine := map_key(key);
    // no need for mapping since our keys are based on glfw
    engine_key := key;
    if engine_key == cast(s32) Key_Code.UNKNOWN {
        return;
    }

    if action == GLFW_PRESS {
        state.keys_current[engine_key] = true;
    }
    if action == GLFW_RELEASE {
        state.keys_current[engine_key] = false;
    }
}

mouse_button_callback :: (window: *GLFWwindow, button: s32, action: s32, mods: s32) #c_call {
    if button < 0 || button >= MOUSE_BUTTON_COUNT {
        return;
    }

    if action == GLFW_PRESS {
        state.mouse_current[button] = true;
    }
    if action == GLFW_RELEASE {
        state.mouse_current[button] = false;
    }
}

cursor_callback :: (window: *GLFWwindow, x: float64, y: float64) #c_call {
    state.mouse_x = x;
    state.mouse_y = y;
}

scroll_callback :: (window: *GLFWwindow, xoffset: float64, yoffset: float64) #c_call {
    state.scroll_x = xoffset;
    state.scroll_y = yoffset;
}

char_callback :: (window: *GLFWwindow, codepoint: u32) #c_call {
    push_context {
        array_add(*state.text_input, codepoint);
    }
}

#scope_export

install_callbacks :: (window: *GLFWwindow) {
    glfwSetKeyCallback(window, key_callback);
    glfwSetMouseButtonCallback(window, mouse_button_callback);
    glfwSetCursorPosCallback(window, cursor_callback);
    glfwSetScrollCallback(window, scroll_callback);
    glfwSetCharCallback(window, char_callback);
}
