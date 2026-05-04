shader_type canvas_item;
render_mode unshaded, blend_mix;

// Lightweight world pixelation: snaps UV to a coarse grid. No color grading.
uniform float pixel_size : hint_range(1.0, 32.0) = 5.0;

void fragment() {
    vec2 px = TEXTURE_PIXEL_SIZE * pixel_size;
    vec2 uv = (floor(UV / px) + 0.5) * px;
    vec4 col = texture(TEXTURE, uv);
    if (col.a <= 0.001) {
        discard;
    }
    COLOR = col;
}
