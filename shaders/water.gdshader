shader_type canvas_item;

// Pixel-art water: mostly ONE solid mid-teal with subtle deep patches drifting
// across, plus animated white foam pixels ONLY along the water/land edges.
// Edges are detected via per-fragment derivative of the water_amt mask, so
// foam tracks wherever the water bed meets dry dirt on the source tile.

uniform vec4 water_color : source_color = vec4(0.10, 0.42, 0.62, 1.0);
uniform vec4 deep_color  : source_color = vec4(0.05, 0.28, 0.45, 1.0);
uniform vec4 froth_color : source_color = vec4(0.95, 1.0, 1.0, 1.0);

uniform float pixel_size_world : hint_range(1.0, 8.0) = 1.0;

// Body variation: fraction of water-pixels that flick darker per step.
// Higher values = more visible animation across the surface.
uniform float body_variation : hint_range(0.0, 1.0) = 0.10;

// Animation step. Lower = faster pixel re-roll = more obvious motion.
uniform float foam_step_seconds : hint_range(0.05, 1.0) = 0.12;
uniform float foam_density      : hint_range(0.0, 1.0) = 0.55;   // chance a given edge pixel turns foam this step
uniform float edge_threshold    : hint_range(0.001, 0.5) = 0.04; // |grad(water_amt)| above this counts as edge

uniform float water_threshold : hint_range(0.0, 1.0) = 0.21;
uniform float blend_softness  : hint_range(0.0, 0.2) = 0.05;

// Optional UV snapping for the painterly world look (driven by the world
// shader panel). 1.0 = no snap.
uniform float pixel_size : hint_range(1.0, 32.0) = 1.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

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

void fragment() {
	vec2 snap = TEXTURE_PIXEL_SIZE * pixel_size;
	vec2 uv = (floor(UV / snap) + 0.5) * snap;
	vec4 src = texture(TEXTURE, uv);
	if (src.a < 0.05) discard;
	float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	float water_amt = 1.0 - smoothstep(water_threshold, water_threshold + blend_softness, lum);

	// Edge detection: where water_amt changes rapidly between fragments,
	// we're at the water/land seam. Use that as the foam region.
	float edge = length(vec2(dFdx(water_amt), dFdy(water_amt)));

	// Pixelate the world position.
	vec2 px = floor(world_pos / pixel_size_world);

	// Body water: almost entirely water_color. A small fraction of pixels
	// flick to deep_color each animation step, producing scattered shimmer
	// without large patches of variation.
	float body_step = floor(TIME / foam_step_seconds);
	float body_n = hash21(px + vec2(body_step, 17.0));
	vec3 water_rgb = water_color.rgb;
	if (body_n > 1.0 - body_variation) {
		water_rgb = deep_color.rgb;
	}

	// Foam: ALL edge pixels always become froth, no hash gate, so the
	// shoreline reads as a continuous unbroken band. A subtle time-based
	// shimmer in brightness keeps it animated without uneven gaps.
	if (edge > edge_threshold) {
		float shimmer = 0.85 + 0.15 * sin(TIME * 4.0 + (px.x + px.y) * 0.6);
		water_rgb = froth_color.rgb * shimmer;
	}

	vec3 final_rgb = mix(src.rgb, water_rgb, water_amt);
	COLOR = vec4(final_rgb, src.a);
}
