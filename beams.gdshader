shader_type canvas_item;
// Additive blend so the beams *add light* instead of replacing pixel color.
render_mode blend_add;

// God rays. Only 2-3 wide, soft, drifting beams angled across the screen.
// Output is RGB premultiplied by intensity; alpha is unused with blend_add.

uniform float intensity : hint_range(0.0, 1.0) = 0.22;
uniform vec3 ray_color : source_color = vec3(1.0, 0.93, 0.7);
uniform float angle : hint_range(0.0, 1.5) = 0.55;
uniform float frequency : hint_range(1.0, 12.0) = 3.5;
uniform float drift_speed : hint_range(0.0, 0.5) = 0.06;
uniform float sharpness : hint_range(1.0, 8.0) = 2.4;

void fragment() {
	float c = cos(angle);
	float s = sin(angle);
	float v = UV.x * c + UV.y * s + TIME * drift_speed;
	float wobble = sin(UV.y * 7.0 + TIME * 0.2) * 0.04;
	float t = sin((v + wobble) * frequency) * 0.5 + 0.5;
	t = pow(t, sharpness);
	// Beams brightest in the upper-left, fading out before the bottom edge.
	float vert_fade = smoothstep(0.0, 0.35, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float horiz_fade = 1.0 - smoothstep(0.55, 1.0, UV.x);
	float energy = t * vert_fade * horiz_fade * intensity;
	COLOR = vec4(ray_color * energy, 1.0);
}
