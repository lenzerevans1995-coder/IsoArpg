shader_type canvas_item;
render_mode unshaded, blend_mix;

// Renders a square texture as an iso ground diamond. Discards outside the
// 2:1 diamond shape and samples the source texture with a 45° rotation so
// the four corners of the square map to N/E/S/W tips of the diamond, the
// same way A1 ground tiles look.
//
// Usage: put this on a Sprite2D sized 128x64 (or any 2:1 quad). The Sprite2D's
// texture is the SQUARE source image (any resolution, e.g. 512x512).

uniform float pixel_size : hint_range(1.0, 32.0) = 1.0;

void fragment() {
    vec2 cu = UV - 0.5;
    // Diamond mask: |cu.x| + |cu.y| < 0.5 covers the iso tile shape.
    if (abs(cu.x) + abs(cu.y) >= 0.5) {
        discard;
    }
    // Rotate-and-scale: corners of the diamond -> corners of the square.
    //   left  (-0.5, 0)  -> (0,0)
    //   top   (0, -0.5)  -> (1,0)
    //   right (0.5, 0)   -> (1,1)
    //   bot   (0, 0.5)   -> (0,1)
    vec2 sample_uv = vec2(cu.x - cu.y + 0.5, cu.x + cu.y + 0.5);
    // Optional pixel snap so it composes with the world shader panel.
    vec2 px = TEXTURE_PIXEL_SIZE * pixel_size;
    sample_uv = (floor(sample_uv / px) + 0.5) * px;
    COLOR = texture(TEXTURE, sample_uv);
}
