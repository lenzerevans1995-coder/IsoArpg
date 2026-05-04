shader_type canvas_item;

// Per-instance plant shader: subtle vertical "breathing" displacement plus an
// HSV recolor pass so we can produce different biome color tones (purple
// forest, yellow-flower meadow, etc) from the same source asset.

uniform float strength : hint_range(0.0, 0.05) = 0.010;
uniform float speed    : hint_range(0.1, 4.0)  = 1.1;
uniform float phase    : hint_range(0.0, 6.283) = 0.0;
uniform float root_uv_y : hint_range(0.0, 1.0) = 0.97;

// HSV recolor. hue_shift in [-1, 1] (full circle). sat / val multipliers
// scale saturation and brightness. Defaults are no-op.
uniform float hue_shift  : hint_range(-1.0, 1.0) = 0.0;
uniform float sat_mult   : hint_range(0.0, 2.0) = 1.0;
uniform float val_mult   : hint_range(0.0, 2.0) = 1.0;
uniform float pixel_size : hint_range(1.0, 32.0) = 1.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	float t = TIME * speed + phase;
	float breathe = sin(t) * strength;
	float v_factor = clamp((root_uv_y - UV.y) / root_uv_y, 0.0, 1.0);
	vec2 uv = UV + vec2(0.0, -breathe * v_factor);
	uv = clamp(uv, vec2(0.0), vec2(1.0));
	vec2 px = TEXTURE_PIXEL_SIZE * pixel_size;
	uv = (floor(uv / px) + 0.5) * px;
	vec4 src = texture(TEXTURE, uv);
	if (src.a < 0.001) {
		COLOR = src;
	} else {
		vec3 hsv = rgb2hsv(src.rgb);
		hsv.x = fract(hsv.x + hue_shift + 1.0);
		hsv.y = clamp(hsv.y * sat_mult, 0.0, 1.0);
		hsv.z = clamp(hsv.z * val_mult, 0.0, 1.0);
		COLOR = vec4(hsv2rgb(hsv), src.a);
	}
}
