shader_type canvas_item;

// Recolors a ripple sprite (cyan teal source) to white foam/froth so it reads
// as bright surf on top of the darker water. Alpha shape is preserved exactly.

uniform vec4 froth_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	if (src.a < 0.04) discard;
	COLOR = vec4(froth_color.rgb, src.a * froth_color.a);
}
