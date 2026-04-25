#scope_export

Game_Init_Proc         :: #type ();
Game_Fixed_Update_Proc :: #type (fixed_delta_time: float64);
Game_Update_Proc       :: #type ();
Game_Shutdown_Proc     :: #type ();

Game_Module :: struct {
    game_init:         Game_Init_Proc;
    game_fixed_update: Game_Fixed_Update_Proc;
    game_update:       Game_Update_Proc;
    game_shutdown:     Game_Shutdown_Proc;
}

game_module_get_api :: () -> Game_Module {
    module: Game_Module;
    module.game_init =         game_init;
    module.game_fixed_update = game_fixed_update;
    module.game_update =       game_update;
    module.game_shutdown =     game_shutdown;
    return module;
}
