shader_type canvas_item;

// Legacy ripple-froth recolor — kept as a stub so main.gd's chunked-world
// preload (`FROTH_SHADER`) still resolves. The painted-world flow uses
// the new water.gdshader exclusively; this shader is only reached when
// BATTLE_WORLD = true (currently disabled). Safe to delete once the
// chunked world is fully retired.

uniform vec4 froth_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	if (src.a < 0.04) discard;
	COLOR = vec4(froth_color.rgb, src.a * froth_color.a);
}
