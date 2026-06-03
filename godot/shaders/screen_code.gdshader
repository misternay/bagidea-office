shader_type spatial;
render_mode unshaded;

// Scrolling "code lines" for monitors — distant-screen trick from the perf
// doc: zero text cost, reads as live work. HDR output (>1) feeds the glow.
uniform vec3 base_col : source_color = vec3(0.04, 0.09, 0.12);
uniform vec3 glow_col : source_color = vec3(0.3, 0.75, 1.0);
uniform float speed = 0.5;
uniform float rows = 9.0;

float hash(float n) {
	return fract(sin(n * 7.13) * 43758.5453);
}

void fragment() {
	float scroll = UV.y * rows - TIME * speed;
	float row = floor(scroll);
	float in_row = step(0.25, fract(scroll));            // gap between lines
	float len = 0.15 + 0.75 * hash(row);                  // random line length
	float indent = 0.05 + 0.25 * hash(row * 3.7);         // random indent
	float on = step(indent, UV.x) * step(UV.x, indent + len) * in_row;
	ALBEDO = base_col + glow_col * on * 1.5;
}
