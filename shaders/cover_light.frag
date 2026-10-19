// Обем и отблясъци върху корица: корица × карта на светлината.
// Картата (assets/cover_light/*.png) е коефициент / 2 — затова × 2.
// Прави я tools/chitalnya/scripts/05_cover_light.py; вика се от
// lib/cover_light.dart. Картата се разтяга до размера на корицата.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform sampler2D uCover;
uniform sampler2D uLight;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 c = texture(uCover, uv);
  vec3 g = texture(uLight, uv).rgb * 2.0;
  fragColor = vec4(clamp(c.rgb * g, 0.0, 1.0) * c.a, c.a);
}
