shader_type canvas_item;
render_mode blend_mul;

// Film grain + vignette composite pass — the final 5% that sells the HD-2D look.
uniform float grain_amount : hint_range(0.0, 0.3) = 0.07;
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.32;

void fragment() {
	float n = fract(sin(dot(FRAGCOORD.xy + vec2(TIME * 61.7, TIME * 83.3),
		vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float d = distance(UV, vec2(0.5));
	float vig = mix(1.0, smoothstep(0.95, 0.45, d), vignette_amount);
	COLOR = vec4(vec3(vig * (1.0 + n * grain_amount)), 1.0);
}
