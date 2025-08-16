#include <flutter/runtime_effect.glsl>
precision mediump float;

uniform vec2 uScreenOrigin;      // screenOffset in logical pixels
uniform float uScaledSpacing;     // spacing * scale in logical pixels
uniform float uInvScaledSpacing;  // 1.0 / uScaledSpacing
uniform vec2 uPhasePx;            // phase shift in logical pixels
uniform float uRadiusPx;          // dot radius in logical pixels
uniform vec4 uDotColor;           // RGBA 0..1
uniform vec4 uBgColor;            // RGBA 0..1

out vec4 fragColor;

void main() {
  // Work entirely in logical pixels
  vec2 p = FlutterFragCoord().xy - uScreenOrigin; // local logical pixel coords within the painted rect

  // LOD: if dots become sub-pixel or spacing too dense, draw only background
  if (uScaledSpacing < 1.0 || uRadiusPx < 0.25) {
    fragColor = uBgColor;
    return;
  }

  // Fractional position within the lattice, centered around each grid point
  vec2 cell = (p + uPhasePx) * uInvScaledSpacing; // multiply by inverse spacing to avoid division
  vec2 f = fract(cell) - 0.5;                     // [-0.5, 0.5)

  // Use squared distance to avoid sqrt
  float s2 = uScaledSpacing * uScaledSpacing;
  float dist2 = dot(f, f) * s2;

  // Analytic AA using squared thresholds (~1 logical px transition)
  float e0 = max(0.0, uRadiusPx - 1.0);
  float e1 = uRadiusPx + 1.0;
  float alpha = 1.0 - smoothstep(e0 * e0, e1 * e1, dist2);

  fragColor = mix(uBgColor, uDotColor, alpha);
}
