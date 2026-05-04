shader_type canvas_item;

// Snap UVs to a coarse grid so the sampled texel becomes a large block —
// produces the chunky pixel-art look on otherwise high-res glyph art.
uniform float pixel_block : hint_range(1.0, 16.0) = 3.0;
uniform vec2 region_size = vec2(64.0, 64.0);

void fragment() {
	vec2 px_uv = UV * region_size;
	px_uv = floor(px_uv / pixel_block) * pixel_block + pixel_block * 0.5;
	vec2 quant_uv = px_uv / region_size;
	vec4 c = texture(TEXTURE, quant_uv);
	COLOR = c * COLOR;
}
