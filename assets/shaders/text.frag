#version 330 core

in vec2 v_tex_coords;

uniform sampler2D u_text;
uniform vec4 u_text_color;

out vec4 color;

void main() {
    float alpha = texture(u_text, v_tex_coords).r;
    color = vec4(u_text_color.rgb, u_text_color.a * alpha);
}
