shader_type canvas_item;

// Fullscreen fog overlay. Two layers of value-noise fbm scrolling at slightly
// different rates produce drifting wisps without ever repeating visibly.

uniform float density : hint_range(0.0, 1.0) = 0.18;
uniform vec3 fog_color : source_color = vec3(0.85, 0.88, 0.92);
uniform float scroll_speed : hint_range(0.0, 0.5) = 0.025;
uniform float scale : hint_range(0.5, 8.0) = 2.2;
// Threshold cuts off fog below this fbm value -> only the densest wisps appear.
uniform float patchiness : hint_range(0.0, 1.0) = 0.55;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.07;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * scale;
	float t = TIME * scroll_speed;
	float n = fbm(uv + vec2(t, t * 0.6));
	float n2 = fbm(uv * 1.7 - vec2(t * 0.7, -t * 0.3));
	float blended = mix(n, n2, 0.4);
	// Cut off everything below the patchiness threshold so we only get wisps,
	// not a uniform overlay.
	float wisps = smoothstep(patchiness, patchiness + 0.3, blended);
	float a = wisps * density;
	COLOR = vec4(fog_color, a);
}
