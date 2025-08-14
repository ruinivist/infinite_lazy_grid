#include <flutter/runtime_effect.glsl>
precision mediump float;

uniform vec2 uScreenOrigin;      // screenOffset in pixels
uniform float uScaledSpacing;     // spacing * scale in pixels
uniform vec2 uPhasePx;            // phase shift in pixels: mod(-canvasOffset * scale, scaledSpacing)
uniform float uRadiusPx;          // dot radius in pixels: size * scale
uniform vec4 uDotColor;           // RGBA 0..1
uniform vec4 uBgColor;            // RGBA 0..1

out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy - uScreenOrigin; // local pixel coords within the painted rect

  // LOD: if dots become sub-pixel or spacing too dense, draw only background
  if (uScaledSpacing < 1.0 || uRadiusPx < 0.25) {
    fragColor = uBgColor;
    return;
  }

  // Periodic grid in screen space with phase to account for canvasOffset
  vec2 rem = mod(p + uPhasePx, uScaledSpacing);
  vec2 d = min(rem, vec2(uScaledSpacing) - rem);
  float dist = length(d);

  // Analytic AA around the circle edge (~1px transition)
  float edge = uRadiusPx;
  float alpha = 1.0 - smoothstep(edge - 1.0, edge + 1.0, dist);

  fragColor = mix(uBgColor, uDotColor, alpha);
}
