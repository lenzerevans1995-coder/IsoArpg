shader_type canvas_item;

// Pixelize + circular body-mask + behind-facing half-plane. The FX
// overlay uses this to (a) chunk-up the rendering and (b) hide any
// particles that are EITHER inside the player's body circle OR behind
// the player's facing direction. So projectiles spawned at the bow
// stay invisible while inside the body AND while behind the player,
// and only appear once they exit both regions.

uniform float pixel_size : hint_range(1.0, 32.0) = 1.1;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;

// Player body centre in screen UV space (0..1). Runner writes this each
// frame from the active 2D camera + player.global_position + body_offset.
uniform vec2 mask_center_uv = vec2(0.5, 0.5);
// Body radius in UV space (radius_pixels * cam_zoom / screen_height).
// Aspect-corrected by the screen ratio passed via mask_aspect.
uniform float mask_radius_uv : hint_range(0.0, 1.0) = 0.0;
// screen_size.x / screen_size.y — used to undo the UV stretch so the
// cutout is a true circle on screen, not an ellipse.
uniform float mask_aspect = 1.7777;
// Soft-edge falloff in UV (smoothstep band around the radius / cut line).
uniform float mask_softness : hint_range(0.0, 0.2) = 0.02;
// Player facing direction (UNIT vector, world-aligned: +X right, +Y down).
// Used for the half-plane "behind" cut. Length 0 disables half-plane.
uniform vec2 mask_facing = vec2(0.0, 0.0);
// Master toggle: 0 = no masking, 1 = full mask.
uniform float mask_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	float cell = max(pixel_size, 1.0);
	vec2 snapped_pixel = (floor(UV * tex_size / cell) + 0.5) * cell;
	vec2 quantized_uv = snapped_pixel / tex_size;
	vec4 c = texture(TEXTURE, quantized_uv);
	if (mask_strength > 0.0001) {
		vec2 delta = UV - mask_center_uv;
		delta.x *= mask_aspect;
		// Circular body mask — 0 inside the body circle, 1 outside.
		float circ_visible = 1.0;
		if (mask_radius_uv > 0.0) {
			float d = length(delta);
			circ_visible = smoothstep(mask_radius_uv - mask_softness,
				mask_radius_uv + mask_softness, d);
		}
		// Half-plane "behind facing" mask — 0 behind the player, 1 in
		// front. Disabled when mask_facing has zero length.
		float half_visible = 1.0;
		if (length(mask_facing) > 0.0001) {
			float along = dot(delta, normalize(mask_facing));
			half_visible = smoothstep(-mask_softness, mask_softness, along);
		}
		// Hidden if EITHER mask says hide → multiply visibilities.
		float visible = circ_visible * half_visible;
		c.a *= mix(1.0, visible, mask_strength);
	}
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(lum), c.rgb, saturation) * brightness;
	COLOR = c;
}
