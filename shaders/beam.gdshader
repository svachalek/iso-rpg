shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The click-to-move target: a shaft of light standing on the cell, an open
// cylinder with its foot sunk below the floor. It fades out into the ground
// with a faint glow where it meets it, so on a hillside the glow follows the
// slope instead of a flat marker cutting into it.

uniform vec3 color : source_color = vec3(1.0, 0.78, 0.35);
uniform float strength = 1.0;
// The cylinder's length; its mesh is centred on the node.
uniform float span = 3.4;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying float height;

void vertex() {
	height = VERTEX.y / span + 0.5;
}

void fragment() {
	// Looking through the middle crosses more of the shaft than its edge.
	float through = abs(dot(NORMAL, VIEW));
	float body = pow(through, 2.0) * pow(1.0 - height, 1.3);
	// Motes of light drifting up the shaft.
	float drift = 0.85 + 0.15 * sin(height * 18.0 - TIME * 3.0);

	// Distance to the scene behind, in view space: small where the shaft
	// meets the ground.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float gap = VERTEX.z - behind.z / behind.w;
	// The shaft thins out into the ground rather than stopping at it, and
	// leaves a faint glow where it meets it.
	float sink = smoothstep(0.0, 1.0, gap);
	float ring = 1.0 - smoothstep(0.0, 0.35, gap);
	ring *= ring;

	float pulse = 0.9 + 0.1 * sin(TIME * 4.0);
	float glow = (body * drift * 1.4 * sink + ring * 0.15) * pulse * strength;
	ALBEDO = color * glow;
}
