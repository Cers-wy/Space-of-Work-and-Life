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
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p = mat2(.8, -.6, .6, .8) * p * 2.02 + 5.3;
    a *= .5;
  }
  return v;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  // Two curated looks: light theme = right-side blue-violet plume on a pale
  // blue field; dark theme = central blue plume on deep navy. uDark blends them.
  float sd = mix(1.6, 2.3, uDark) + (uSeed - .5) * .12;
  float t = uTime;
  vec2 base = uv * vec2(2.6, 1.9);
  vec2 p = base + vec2(sd * 3.7 + 1.1, sd * 2.3 + 4.7);
  // Slow drift keeps the plume alive without burning frames.
  p += vec2(t * .22, sin(t * .31 + sd) * .45);

  // Two-level domain warping folds the cloud into curling dye filaments.
  float qx = fbm(p);
  float qy = fbm(p + vec2(5.2, 1.3));
  float ax = fbm(vec2(p.x + 3.2 * qx + 1.7, p.y + 3.2 * qy + 9.2));
  float ay = fbm(vec2(p.x + 3.2 * qx + 8.3, p.y + 3.2 * qy + 2.8));
  float f = fbm(vec2(p.x + 4.2 * ax, p.y + 4.2 * ay));

  // Localize the plume to one side so the title/description area stays calm.
  vec2 flow = mix(vec2(.74, .42), vec2(.50, .45), uDark);
  vec2 gd = (base - flow) / vec2(.9, .8);
  float plume = smoothstep(.28, .62, f)
              * smoothstep(.05, .55, exp(-dot(gd, gd) * 1.8) + .25 * f);
  float wisp = smoothstep(.5, .85, f);

  // Ambient haze across the whole card, kept faint.
  float mistg = fbm(p * .8 + vec2(3.0, 7.0));
  float ma = smoothstep(.4, .8, mistg) * .28;

  vec3 bg   = mix(vec3(.902, .925, .973), vec3(.086, .102, .243), uDark);
  vec3 mist = mix(vec3(.812, .851, .941), vec3(.165, .200, .408), uDark);
  vec3 smA  = mix(vec3(.275, .341, .722), vec3(.306, .400, .784), uDark);
  vec3 smB  = mix(vec3(.494, .435, .816), vec3(.541, .435, .847), uDark);

  vec3 color = mix(bg, mist, ma);
  color = mix(color, mix(smA, smB, smoothstep(.30, .75, ax)), plume);
  // Bright silky ridge along the plume edge for volume, restrained so text reads.
  float ridge = clamp(wisp - plume, 0.0, 1.0) * smoothstep(.45, .8, f);
  color = mix(color, vec3(.941, .918, 1.0), ridge * .5);

  // Soft glass rim keeps the plume inside the rounded card edge. Alpha tracks
  // the drifting plume so the smoke breathes (dense wisps slightly more opaque)
  // instead of being a flat, unchanging sheet.
  vec2 edge = smoothstep(vec2(0), vec2(.07), uv)
            * smoothstep(vec2(0), vec2(.07), 1.0 - uv);
  float body = smoothstep(.28, .70, f) * (0.35 + 0.65 * plume);
  float coverage = mix(.86, 1.0, body);
  float alpha = coverage * edge.x * edge.y * mix(1.0, 1.03, uEmphasis);
  fragColor = vec4(color * alpha, alpha);
}
