// File:        main.jai
// Author:      Lukáš Bien
// Description: Loads engine modules and runs the main application loop.

// #import "Basic"()(MEMORY_DEBUGGER = MEMORY_DEBUGGER_ENABLED);

#load "module.jai";
#load "../game/main.jai";

#scope_export

#if BUILD_MODE != .GAME {
    main :: () {
        game_module := game_module_get_api();
        if !app_init(game_module) {
            log_error("Failed to initialize host");
            return;
        }
        defer app_shutdown();

        while !app_should_close() {
            app_run_frame();
        }
    }
}
