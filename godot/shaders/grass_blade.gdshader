shader_type spatial;
render_mode cull_disabled;

// Wind-swaying grass blade — tops bend on a traveling sine wave, phase
// offset by world position so the field ripples instead of marching.
uniform vec3 base_col : source_color = vec3(0.14, 0.34, 0.12);
uniform vec3 tip_col : source_color = vec3(0.42, 0.66, 0.22);
uniform float wind_strength = 0.14;
uniform float wind_speed = 1.6;

void vertex() {
	float bend = 1.0 - UV.y; // QuadMesh: v=0 at the top → tips move, roots stay
	VERTEX.x *= UV.y;        // taper to a point — blade reads as a spike, not a card
	vec2 wpos = vec2(MODEL_MATRIX[3].x, MODEL_MATRIX[3].z);
	float phase = wpos.x * 0.7 + wpos.y * 0.9;
	float sway = sin(TIME * wind_speed + phase) + 0.4 * sin(TIME * wind_speed * 2.3 + phase * 1.7);
	VERTEX.x += sway * wind_strength * bend * bend;
	VERTEX.z += sway * wind_strength * 0.35 * bend * bend;
}

void fragment() {
	ALBEDO = mix(tip_col, base_col, UV.y);
	ROUGHNESS = 0.9;
}
