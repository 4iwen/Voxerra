#scope_export

// core
#load "core/logging.jai";
#load "core/window.jai";
#load "core/input.jai";
#load "core/platform.jai";
#load "core/time.jai";
#load "core/engine.jai";

// math
#load "math/math.jai";
#load "math/noise.jai";
#load "math/transform.jai";

// render
#load "renderer/renderer.jai";
#load "renderer/shader.jai";
#load "renderer/mesh.jai";
#load "renderer/camera.jai";
#load "renderer/texture.jai";
#load "renderer/render_queue.jai";
#load "renderer/material.jai";
#load "renderer/model.jai";
#load "renderer/light.jai";
#load "renderer/framebuffer.jai";
#load "renderer/postfx.jai";
#load "renderer/scene.jai";
#load "renderer/skybox.jai";
#load "renderer/cubemap.jai";

// assets
#load "assets/asset_manager.jai";

// ecs
#load "ecs/entity.jai";
#load "ecs/components.jai";

// editor
#if BUILD_MODE == .EDITOR {
    #load "editor/picking.jai";
}

// ui
#if BUILD_MODE == .EDITOR {
    #load "ui/ui.jai";
    #load "ui/widgets.jai";
    #load "ui/metrics.jai";
    #load "ui/node_hierarchy.jai";
    #load "ui/node_properties.jai";
    #load "ui/main_menu.jai";
    #load "ui/postfx.jai";
    #load "ui/viewport.jai";
    #load "ui/log.jai";
}

#load "runtime/game_module.jai";
#load "runtime/app.jai";
