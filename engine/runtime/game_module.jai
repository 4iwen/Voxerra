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
