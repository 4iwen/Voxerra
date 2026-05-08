# Voxerra

![Showcase](showcase.png)

## Cloning

`git clone https://github.com/4iwen/Voxerra --recursive`

## Building

- `jai first.jai` builds editor and game module
- `jai first.jai - -editor` builds only the editor
- `jai first.jai - -game` builds only the game module
- `jai first.jai - -export` builds the standalone game executable

## TODO
- Add shadows
- Improve the way to set up environment (skybox, ambient lighting, etc.)
- Add more components
- Add cubemap and their hot reloading
- Use Iprof/Tracy when implementing profiling
- Add prepocessor for shaders for deduplicating code
- Transition to bounding box picking?
- Improve the add component modal, improve the open scene modal
- Add scene save as button and modal
- Make exiting the engine prompt for saving scenes and other unsaved stuff
- FBX doesn't work
- When dragging gizmos out of viewport they stop affecting the thing thats being edited
- Creating a scene in a folder that does not exist causes an error
- Fix unidentified crash when entering a folder in the asset browser
- Sprite components do not affect dirty flag on scenes
