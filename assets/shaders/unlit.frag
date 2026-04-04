#version 330 core

struct Material {
    sampler2D diffuse;
    sampler2D specular;
    float shininess;
};

in vec2 v_uv;

uniform Material u_material;

out vec4 color;

void main() {
    color = texture(u_material.diffuse, v_uv);
}
