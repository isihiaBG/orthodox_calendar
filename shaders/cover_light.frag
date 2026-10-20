// Обем и отблясъци върху корица: корица × карта на светлината, със заоблени
// ъгли. Картата (assets/cover_light/*.png) е коефициент / 2 — затова × 2.
// Прави я tools/chitalnya/scripts/05_cover_light.py; вика се от
// lib/cover_light.dart. Картата се разтяга до размера на корицата.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform sampler2D uCover;
uniform sampler2D uLight;

out vec4 fragColor;

// Радиусът на ъглите — дял от ширината (като на кожената корица).
const float kCorner = 0.012;

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 uv = p / uSize;
  vec4 c = texture(uCover, uv);
  vec3 g = texture(uLight, uv).rgb * 2.0;
  // заоблен правоъгълник: разстояние до ъгъла, меко на половин пиксел
  float r = kCorner * uSize.x;
  vec2 q = max(max(vec2(r) - p, p - (uSize - vec2(r))), vec2(0.0));
  float a = clamp(r - length(q) + 0.5, 0.0, 1.0) * c.a;
  fragColor = vec4(clamp(c.rgb * g, 0.0, 1.0) * a, a);
}
