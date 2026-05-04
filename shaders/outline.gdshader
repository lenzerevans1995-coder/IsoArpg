shader_type canvas_item;

// Simple alpha-edge outline for hovered enemy sprites. Samples the texture
// at 8 cardinal/diagonal offsets; if any are opaque while the centre is
// transparent, the pixel is drawn in `outline_color`.
uniform vec4 outline_color : source_color = vec4(1.0, 0.92, 0.20, 1.0);
uniform float outline_width : hint_range(0.0, 8.0) = 2.0;
uniform vec2 texture_size = vec2(128.0, 128.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a > 0.5) {
		COLOR = base * COLOR;
	} else {
		float alpha = 0.0;
		vec2 px = outline_width / texture_size;
		alpha += texture(TEXTURE, UV + vec2( px.x, 0.0)).a;
		alpha += texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
		alpha += texture(TEXTURE, UV + vec2(0.0,  px.y)).a;
		alpha += texture(TEXTURE, UV + vec2(0.0, -px.y)).a;
		alpha += texture(TEXTURE, UV + vec2( px.x,  px.y)).a;
		alpha += texture(TEXTURE, UV + vec2(-px.x,  px.y)).a;
		alpha += texture(TEXTURE, UV + vec2( px.x, -px.y)).a;
		alpha += texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;
		if (alpha > 0.0) {
			COLOR = outline_color;
		} else {
			COLOR = vec4(0.0);
		}
	}
}
