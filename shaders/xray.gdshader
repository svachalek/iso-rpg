shader_type spatial;
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_back;
// The figure writes 1 (Player.XRAY_STENCIL) wherever it shows, so parts of
// it standing out in front of this shell are not taken for walls.
stencil_mode read, compare_not_equal, 1;

// Second material on the character: draws only where the normal pass failed
// the depth test, i.e. the parts hidden behind terrain.

uniform vec4 tint : source_color = vec4(0.45, 0.75, 1.0, 0.55);
// The cube the figure stands in (its lower corner). Whatever hides it from
// inside that cube is what it sits on or leans against, a chair's back or
// arm, and is not worth a silhouette. Faces on the cube's sides and floor
// belong to its neighbours, so the test stops just short of them.
uniform vec3 cube = vec3(0.0, -100000.0, 0.0);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

const float CUBE_EDGE = 0.02;

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 front = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec3 world = (INV_VIEW_MATRIX * vec4(front.xyz / front.w, 1.0)).xyz;
	vec3 local = world - cube;
	if (all(greaterThan(local, vec3(CUBE_EDGE))) && all(lessThan(local, vec3(1.0 - CUBE_EDGE)))) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
