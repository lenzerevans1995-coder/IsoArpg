shader_type canvas_item;

// Luminance-tint recolor for skill VFX layers. PVGames effect sheets
// are pre-painted in saturated colors, so plain `modulate` blends with
// the source instead of replacing it. This shader collapses the source
// to brightness only (luminance), then multiplies by the picked tint —
// so the rendered color matches the swatch exactly while preserving
// the original alpha and intensity gradients.

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	// Rec. 709 luminance — better than a flat (r+g+b)/3 average for
	// preserving perceived intensity of bright highlights.
	float lum = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(tint.rgb * lum, src.a * tint.a);
}
