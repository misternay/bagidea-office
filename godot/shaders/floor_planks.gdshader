shader_type spatial;

// Procedural wood planks in world space — one material, zero textures.
uniform vec3 col_a : source_color = vec3(0.22, 0.165, 0.115);
uniform vec3 col_b : source_color = vec3(0.19, 0.14, 0.095);
uniform float plank_w = 1.1;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float row = floor(wpos.z / plank_w);
	float offset = hash(vec2(row, 0.0)) * 2.0;            // stagger plank seams
	float plank = floor((wpos.x + offset) / 2.6);
	float tone = hash(vec2(plank, row));
	vec3 c = mix(col_a, col_b, tone);
	// thin seams
	float seam_z = smoothstep(0.0, 0.04, abs(fract(wpos.z / plank_w) - 0.5) * plank_w);
	float seam_x = smoothstep(0.0, 0.04, abs(fract((wpos.x + offset) / 2.6) - 0.5) * 2.6);
	c *= 0.82 + 0.18 * min(seam_z, seam_x);
	ALBEDO = c;
	ROUGHNESS = 0.55 + 0.2 * tone;
}
