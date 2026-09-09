shader_type spatial;
render_mode cull_back, specular_disabled;

// Shared by every tile. Two occlusion aids, both dithered:
//  - cutout: fragments between the camera and the character, near them on
//    screen and above their feet, are removed so they stay visible.
//  - slice: everything above slice_height within slice_radius of the
//    character is removed, like lifting the roof off a building.

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform float cutout_fade = 0.8;     // width of the dither ramp at the edge
uniform float cutout_exempt = 0.0;   // 1 for materials the cutout must leave alone (trees)
uniform float terrain_blend = 0.0;   // 1 for natural ground tiles: blend materials across cells

// One texel per world column, wrapping every MAP_SIZE cells: weights of
// grass, sand, stone and snow; the remainder is water. Sampled bilinearly
// so boundaries between materials blend over a cell or two.
global uniform sampler2D material_map : filter_linear, repeat_enable;
global uniform float blend_enabled;   // 0 shows each cube's own material (B key)
#ifdef WATER
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
#endif
const float MAP_SIZE = 512.0;
const float ATLAS_COLS = 8.0;
const float INSET = 0.5 / 256.0;   // half a texel of a 256 px atlas
uniform float character_height = 1.8;

global uniform vec3 player_pos;      // character feet, world space
global uniform vec3 cam_right;
global uniform vec3 cam_up;
global uniform vec3 cam_forward;
global uniform float cutout_enabled;   // 0..1 strength (C cycles modes)
global uniform float cutout_radius;    // screen-plane distance from the character's body
global uniform float cutout_floor;     // world y; only cubes at or above it are cut
global uniform float slice_height;     // world y; cubes at or above it are hidden
global uniform float slice_strength;   // 0..1, fades the slice in and out
uniform float slice_radius = 9.0;      // horizontal distance from the character
uniform float slice_fade = 2.0;

const float BAYER[16] = float[16](
	0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
	3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
	15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0);

// Atlas coordinates of the same point in another slot.
vec2 slot_uv(int slot, vec2 local) {
	vec2 origin = vec2(float(slot % 8), float(slot / 8)) / ATLAS_COLS;
	return origin + INSET + local * (1.0 / ATLAS_COLS - 2.0 * INSET);
}

void fragment() {
	vec4 tex = texture(atlas, UV);
	ALBEDO = tex.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
#ifdef CUTOUT
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
#endif
#ifdef CANOPY
	ALPHA = 0.9;  // a hint of what is under the foliage; shadows come from a twin item
#endif
#ifdef GLOW
	EMISSION = tex.rgb * 1.6;  // flames
#endif

	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rel = world_pos - player_pos;
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 w = texture(material_map, world_pos.xz / MAP_SIZE);
	float land = w.r + w.g + w.b + w.a;
	float water = clamp(1.0 - land, 0.0, 1.0);

#ifdef WATER
	// Depth of the water under this fragment, from the scene depth behind
	// it: clear in the shallows, dark and opaque a few cubes down, so the
	// stepped lakebed fades out of view.
	// Averaged over a few taps so the darkening does not trace every edge
	// of the lakebed.
	vec2 px = 6.0 / VIEWPORT_SIZE;
	float thickness = 0.0;
	for (int i = 0; i < 5; i++) {
		vec2 off = vec2(0.0);
		if (i == 1) { off = vec2(px.x, 0.0); }
		else if (i == 2) { off = vec2(-px.x, 0.0); }
		else if (i == 3) { off = vec2(0.0, px.y); }
		else if (i == 4) { off = vec2(0.0, -px.y); }
		vec2 suv = clamp(SCREEN_UV + off, vec2(0.0), vec2(1.0));
		float scene_z = texture(depth_tex, suv).r;
		vec4 behind = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, scene_z, 1.0);
		behind.xyz /= behind.w;
		thickness += max(behind.z - VERTEX.z, 0.0) * 0.577;  // along the ray to vertical at the iso pitch
	}
	thickness /= 5.0;
	ALBEDO = mix(tex.rgb, tex.rgb * 0.5, smoothstep(0.4, 3.0, thickness));
	// Fade out where the map says the shore begins.
	ALPHA = mix(0.78, 0.97, smoothstep(0.0, 2.0, thickness)) * smoothstep(0.15, 0.7, water);
#endif

	if (terrain_blend > 0.5 && blend_enabled > 0.5) {
		// Which slot this face was baked with, and where in it we are.
		vec2 cell = floor(UV * ATLAS_COLS);
		int own = int(cell.x) + int(cell.y) * 8;
		vec2 local = clamp((UV - cell / ATLAS_COLS - INSET) / (1.0 / ATLAS_COLS - 2.0 * INSET), 0.0, 1.0);
		bool top_face = world_n.y > 0.35;
		// Top faces blend the top textures; the sides of surface cubes (grass
		// side, sand) blend the side textures. Dirt and stone courses below
		// the surface keep their own look.
		bool blend_side = !top_face && (own == 1 || own == 4);
		if (top_face || blend_side) {
			// A tile whose material has no weight here was placed by hand
			// (a stone wall in grass): keep its own texture.
			float own_w = (own == 0 || own == 1) ? w.r : (own == 4 ? w.g : (own == 3 ? w.b : (own == 6 ? w.a : 0.0)));
			if (own_w > 0.001 && land > 0.001) {
				int g = top_face ? 0 : 1;
				// Explicit derivatives from the baked UV: the remapped
				// coordinates jump at face edges and would pick a blurry mip.
				vec2 dx = dFdx(UV);
				vec2 dy = dFdy(UV);
				ALBEDO = (w.r * textureGrad(atlas, slot_uv(g, local), dx, dy).rgb
					+ w.g * textureGrad(atlas, slot_uv(4, local), dx, dy).rgb
					+ w.b * textureGrad(atlas, slot_uv(3, local), dx, dy).rgb
					+ w.a * textureGrad(atlas, slot_uv(6, local), dx, dy).rgb) / land;
			}
			// Wet ground at the waterline.
			ALBEDO *= 1.0 - 0.3 * water;
		}
	}

	// How far in front of the character this fragment is, along the view axis.
	float in_front = -dot(rel, cam_forward);
	// Screen-plane distance from the character's body (a vertical segment).
	vec2 p = vec2(dot(rel, cam_right), dot(rel, cam_up));
	float body_top = character_height * cam_up.y;
	vec2 nearest = vec2(0.0, clamp(p.y, 0.0, body_top));
	float d = length(p - nearest);

	// Only cut whole cubes from the cell above the feet upward, so ramps and
	// slabs around the character stay put and nothing is cut mid-cube.
	float above = step(cutout_floor + 0.001, world_pos.y);
	float front = clamp((in_front - 0.4) / 0.6, 0.0, 1.0);
	float near = clamp((cutout_radius - d) / cutout_fade, 0.0, 1.0);
	float cut = above * front * near * cutout_enabled * (1.0 - cutout_exempt);

	// Level slice. The tiny offset keeps the top face of the cube just below
	// the cut, which sits exactly at slice_height, from being removed.
	float dxz = length(rel.xz);
	float sliced = step(slice_height + 0.001, world_pos.y)
		* clamp((slice_radius - dxz) / slice_fade, 0.0, 1.0) * slice_strength;
	cut = max(cut, sliced);
	if (cut > 0.0) {
		ivec2 px = ivec2(FRAGCOORD.xy) % 4;
		if (cut > BAYER[px.y * 4 + px.x]) {
			discard;
		}
	}
}
