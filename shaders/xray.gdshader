shader_type spatial;
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_back;

// Second material on the character: draws only where the normal pass failed
// the depth test, i.e. the parts hidden behind terrain.

uniform vec4 tint : source_color = vec4(0.45, 0.75, 1.0, 0.55);

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
