shader_type canvas_item;
render_mode unshaded, blend_mix;

// Re-styles smooth 2.5D pre-rendered monster sprites (e.g. OtherWorlds pack)
// into a more pixely / 16-bit feel. Pipeline: snap UV to a coarse pixel grid
// -> posterize per-channel -> palette grade -> darkened edge outline ->
// alpha cutoff. Region-aware: neighbour samples are clamped to the active
// cell so adjacent frames in the spritesheet don't bleed in as rays.

uniform float pixel_size : hint_range(1.0, 32.0) = 3.0;
uniform int palette_levels : hint_range(2, 32) = 9;
uniform vec3 warm_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.5, 2.0) = 1.1;
uniform float brightness : hint_range(-0.5, 0.5) = 0.0;
uniform float outline_strength : hint_range(0.0, 1.0) = 0.4;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.35;

// Glow: bright halo bled outward from the silhouette. Matches the
// character creator's glow feature (glowColor in the source dll).
uniform vec3 glow_color : source_color = vec3(1.0, 0.85, 0.4);
uniform float glow_strength : hint_range(0.0, 4.0) = 0.0;
uniform float glow_radius : hint_range(0.0, 16.0) = 4.0;

// Active region in normalised texture UV space. Set by monster.gd whenever
// the frame changes; defaults to full texture so the shader still works on
// non-region sprites.
uniform vec2 region_uv_min = vec2(0.0);
uniform vec2 region_uv_max = vec2(1.0);

// Palette quantization: every output pixel is snapped to its nearest color in
// `palette_tex` (a 1xN strip of swatches built at runtime from the asset's
// 81-color picker). Always on; palette_mix lets you blend back to the source.
uniform sampler2D palette_tex : repeat_disable, filter_nearest;
uniform int palette_size = 81;
uniform float palette_mix : hint_range(0.0, 1.0) = 1.0;

vec3 palette_nearest(vec3 c) {
    vec3 best = texture(palette_tex, vec2(0.5 / float(palette_size), 0.5)).rgb;
    float best_d = dot(c - best, c - best);
    for (int i = 1; i < 256; i++) {
        if (i >= palette_size) break;
        vec3 p = texture(palette_tex, vec2((float(i) + 0.5) / float(palette_size), 0.5)).rgb;
        float d = dot(c - p, c - p);
        if (d < best_d) {
            best_d = d;
            best = p;
        }
    }
    return best;
}

vec3 posterize(vec3 c, float n) {
    return floor(c * n + 0.5) / n;
}

void fragment() {
    vec4 modulate_in = COLOR;
    vec2 px = TEXTURE_PIXEL_SIZE * pixel_size;
    vec2 uv = (floor(UV / px) + 0.5) * px;
    // Clamp snapped UV to the active cell so the pixelate step never reads
    // adjacent frames in the 21x21 sheet (those bleed in as bright streaks).
    uv = clamp(uv, region_uv_min, region_uv_max);

    vec4 col = texture(TEXTURE, uv);
    bool inside = col.a >= alpha_cutoff;
    float glow_a = 0.0;
    if (!inside && glow_strength > 0.0 && glow_radius > 0.0) {
        float gr_x = TEXTURE_PIXEL_SIZE.x * glow_radius;
        float gr_y = TEXTURE_PIXEL_SIZE.y * glow_radius;
        vec2 o0 = vec2( gr_x, 0.0);
        vec2 o1 = vec2(-gr_x, 0.0);
        vec2 o2 = vec2(0.0,  gr_y);
        vec2 o3 = vec2(0.0, -gr_y);
        vec2 o4 = vec2( gr_x,  gr_y) * 0.7071;
        vec2 o5 = vec2(-gr_x,  gr_y) * 0.7071;
        vec2 o6 = vec2( gr_x, -gr_y) * 0.7071;
        vec2 o7 = vec2(-gr_x, -gr_y) * 0.7071;
        float a0 = texture(TEXTURE, clamp(UV + o0, region_uv_min, region_uv_max)).a;
        float a1 = texture(TEXTURE, clamp(UV + o1, region_uv_min, region_uv_max)).a;
        float a2 = texture(TEXTURE, clamp(UV + o2, region_uv_min, region_uv_max)).a;
        float a3 = texture(TEXTURE, clamp(UV + o3, region_uv_min, region_uv_max)).a;
        float a4 = texture(TEXTURE, clamp(UV + o4, region_uv_min, region_uv_max)).a;
        float a5 = texture(TEXTURE, clamp(UV + o5, region_uv_min, region_uv_max)).a;
        float a6 = texture(TEXTURE, clamp(UV + o6, region_uv_min, region_uv_max)).a;
        float a7 = texture(TEXTURE, clamp(UV + o7, region_uv_min, region_uv_max)).a;
        glow_a = max(max(max(a0, a1), max(a2, a3)), max(max(a4, a5), max(a6, a7)));
    }
    if (!inside) {
        if (glow_a < alpha_cutoff) {
            discard;
        }
        COLOR = vec4(glow_color * glow_strength * glow_a, glow_a) * modulate_in;
    } else {
        col.a = 1.0;

    col.rgb = (col.rgb - 0.5) * contrast + 0.5 + brightness;
    float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    col.rgb = mix(vec3(luma), col.rgb, saturation);
    col.rgb *= warm_tint;
    col.rgb = clamp(col.rgb, 0.0, 1.0);
    if (palette_mix > 0.0) {
        vec3 snapped = palette_nearest(col.rgb);
        col.rgb = mix(col.rgb, snapped, palette_mix);
    } else {
        col.rgb = posterize(col.rgb, float(palette_levels));
    }

    if (outline_strength > 0.0) {
        vec2 uv_n = clamp(uv + vec2(0.0, -px.y), region_uv_min, region_uv_max);
        vec2 uv_s = clamp(uv + vec2(0.0,  px.y), region_uv_min, region_uv_max);
        vec2 uv_e = clamp(uv + vec2( px.x, 0.0), region_uv_min, region_uv_max);
        vec2 uv_w = clamp(uv + vec2(-px.x, 0.0), region_uv_min, region_uv_max);
        float a_n = texture(TEXTURE, uv_n).a;
        float a_s = texture(TEXTURE, uv_s).a;
        float a_e = texture(TEXTURE, uv_e).a;
        float a_w = texture(TEXTURE, uv_w).a;
        float min_n = min(min(a_n, a_s), min(a_e, a_w));
        if (min_n < alpha_cutoff) {
            col.rgb *= 1.0 - outline_strength;
        }
    }

    COLOR = col * modulate_in;
    }
}
