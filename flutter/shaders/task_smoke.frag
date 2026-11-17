#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uSeed;
uniform float uDark;
uniform float uEmphasis;
out vec4 fragColor;

float hash(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * .1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
             mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
  float v = 0.0, a = .5;
  for (int i = 0; i < 4; i++) {
    v += a * noise(p);
    p = mat2(.8, -.6, .6, .8) * p * 2.03 + 7.1;
    a *= .5;
  }
  return v;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float t = uTime * .16;
  vec2 p = uv * vec2(3.5, 2.6) + uSeed * 17.3;
  // Advect a broad cloud through two changing flow fields. The second warp
  // folds the cloud into wisps rather than translating a fixed texture.
  p += vec2(t * .42, sin(t * .51 + uSeed) * .65);
  vec2 flow = vec2(fbm(p + vec2(t * .23, -t * .31)),
                   fbm(p + vec2(5.2, 1.3) - t * .19));
  vec2 curl = vec2(fbm(p + flow * 3.4 + vec2(1.7, 9.2) + t * .17),
                   fbm(p + flow * 3.4 + vec2(8.3, 2.8) - t * .21));
  float cloud = fbm(p + curl * 4.2);
  float folds = 1.0 - abs(cloud * 2.0 - 1.0);
  float density = smoothstep(.26, .80, cloud) * .75
                + pow(folds, 10.0) * .50;
  // Keep a soft glass rim while allowing smoke to drift across the full face.
  vec2 edge = smoothstep(vec2(0), vec2(.07), uv)
            * smoothstep(vec2(0), vec2(.07), 1.0 - uv);
  float alpha = density * edge.x * edge.y
              * mix(.38, .60, uDark) * mix(1.0, 1.15, uEmphasis);
  vec3 blue = mix(vec3(.17, .34, 1.0), vec3(.46, .61, 1.0), uDark);
  vec3 violet = mix(vec3(.56, .18, .96), vec3(.79, .49, 1.0), uDark);
  vec3 color = mix(blue, violet, smoothstep(.25, .75, curl.x));
  color = mix(color, vec3(.73, .72, 1.0), pow(folds, 18.0) * .16);
  fragColor = vec4(color * alpha, alpha);
}
