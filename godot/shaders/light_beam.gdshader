shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Fake god-ray card — the classic HD-2D trick. Far cheaper and more
// art-directable than physical volumetrics; we layer it on top of them.
uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.72, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 0.45;

void fragment() {
	float fade = 1.0 - UV.y;                       // bright at window, fades to floor
	float edge = smoothstep(0.0, 0.2, UV.x) * smoothstep(1.0, 0.8, UV.x);
	float a = clamp(strength * fade * edge, 0.0, 1.0);
	ALBEDO = tint.rgb;   // unshaded: ALBEDO is the output color (EMISSION is ignored)
	ALPHA = a;
}
