shader_type canvas_item;

// Light pixelization for skill-bar icons. Snaps the UV to a coarser
// grid so high-resolution source art renders with chunky pixel-art
// edges that match the rest of the HUD's aesthetic.

uniform float pixel_size : hint_range(1.0, 8.0) = 1.2;

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	float cell = max(pixel_size, 1.0);
	vec2 snapped = (floor(UV * tex_size / cell) + 0.5) * cell;
	vec2 quantized = snapped / tex_size;
	COLOR = texture(TEXTURE, quantized);
}
