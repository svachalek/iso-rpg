shader_type spatial;
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_back;
// The figure writes 1 (Player.XRAY_STENCIL) wherever it shows, so parts of
// it standing out in front of this shell are not taken for walls.
stencil_mode read, compare_not_equal, 1;

// Second material on the character: draws only where the normal pass failed
// the depth test, i.e. the parts hidden behind terrain.

uniform vec4 tint : source_color = vec4(0.45, 0.75, 1.0, 0.55);

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
