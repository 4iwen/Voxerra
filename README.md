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

- Improve pivotation on sprites, default billboard to none and fix full billboard
- Dragging stuff should work the similar way into the node properties components panel
- Add gizmos for curves and implement them in the engine as a feature
- Make exiting the engine promp for saving scenes and other unsaved stuff
