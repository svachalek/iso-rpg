shader_type spatial;
render_mode cull_back, specular_disabled;

// Shared by every tile. Three occlusion aids:
//  - knock-down (indoors): wall pieces facing the camera near the character
//    are cut to waist height (one cube over the feet), so the room stays
//    open to view while its far walls and everything in it stand as they are.
//  - occluders: a building standing between the camera and the character
//    (the game finds up to three by footprint) loses everything above the
//    character's waist except its ground-floor furniture, so it stands as
//    half-height ground-floor walls with its doorways showing.
//  - slice (indoors): everything above slice_height within slice_radius of
//    the character, and over the whole footprint of the building they are
//    in, is removed, like lifting the roof off a building. Underground the
//    radius grows to take in the whole view, so the surface lifts away and
//    the cave level shows as a cutaway.
//  - cave walls: a rock cube's vertex colour says, for each of the four
//    camera yaws, whether it stands on the line of sight to a passage;
//    when it does it is knocked down like a house wall.

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform float cutout_exempt = 0.0;   // 1 for furniture and trees, which occluder cuts leave alone
// 1 for a wall. Every wall in the world is one cube filling its cell, so
// the cut takes it whole, the way it takes a cube of terrain; its vertex
// tangent carries the wall's facing axis in mesh space (y for a post,
// which faces every way), turned with the instance like a normal.
// 2 for pieces hung on a wall, whose tangent points from the wall into the
// room: they go by the wall cell behind them, and they alone are still cut
// through, being small enough that a cut across one rarely shows.
// 3 for cave rock, whose COLOR holds a bit per camera yaw: set when the
// cube hides a passage from a camera toward (-x,-z), (+x,-z), (-x,+z), (+x,+z).
uniform float knockdown = 0.0;
uniform float terrain_blend = 0.0;   // 1 for natural ground tiles: blend materials across cells

// One texel per world column, wrapping every MAP_SIZE cells: weights of
// grass, sand, stone and snow; the remainder is water. Sampled bilinearly
// so boundaries between materials blend over a cell or two.
global uniform sampler2D material_map : filter_linear, repeat_enable;
// One texel per world column on the same grid: 1 on a road column, 0 off
// it. A road is rasterised whole cells at a time, so its turns come out as
// stair steps; the 0.5 contour of this map's bilinear samples is taken as
// the road's edge instead of the cell boundary. On a straight stretch the
// contour lies exactly on the boundary, and at a step it rounds the corner
// off, convex or concave as the four columns around it fall. Done by
// fragment, so it costs no geometry and follows any slope the road climbs.
global uniform sampler2D road_map : filter_linear, repeat_enable;
global uniform float blend_enabled;   // 0 shows each cube's own material (B key)
#ifdef WATER
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
#endif
const float MAP_SIZE = 512.0;
const float ATLAS_COLS = 8.0;
const float INSET = 0.5 / 256.0;   // half a texel of a 256 px atlas
global uniform vec3 player_pos;      // character feet, world space
global uniform vec3 cam_forward;
global uniform vec3 sun_forward;    // the sun's direction, to tell its shadow pass from the camera's view
global uniform float cutout_enabled;   // 0..1 strength of the knock-down (C toggles)
global uniform float cutout_floor;     // world y; only what is at or above it is cut
global uniform vec4 occluder_a;        // x0, z0, x1, z1 cells (inclusive) of a building in the way, or empty
global uniform vec4 occluder_b;
global uniform vec4 occluder_c;
global uniform float occluder_strength;
global uniform float occluder_upper;   // world y of the occluders' upper floor: furniture from there up goes too
global uniform vec4 own_building;      // footprint of the building the character is in, or empty
global uniform float slice_height;     // world y; cubes at or above it are hidden
global uniform float slice_strength;   // 0..1, fades the slice in and out
global uniform float slice_radius;     // horizontal distance from the character; the whole view underground
global uniform float underground;      // 0..1: how far below the surface the character is
uniform float slice_fade = 2.0;
uniform float knock_radius = 14.0;     // the knock-down reaches a whole room's front walls

const float BAYER[16] = float[16](
	0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
	3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
	15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0);

// World y of the centre of the cell this fragment's piece sits in. Cut
// heights are whole cubes, so cubes, floors and furniture are cut by cell
// rather than by fragment: a face lying exactly on the cut plane then
// belongs wholly to one side, and no edge pixels scatter along the cut.
// Wall pieces are three cubes tall and cut mid-panel by fragment.
varying float cell_y;

void vertex() {
	cell_y = (INV_VIEW_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0))).y - VERTEX.y;
}

// Whether cell c lies in the footprint r = (x0, z0, x1, z1), inclusive.
bool in_rect(vec2 c, vec4 r) {
	return c.x >= r.x && c.y >= r.y && c.x <= r.z && c.y <= r.w;
}

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
#endif
#if defined(CUTOUT) || defined(NATURE)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
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
			// A stone or snow tile whose material has no weight here was
			// placed by hand (a stone wall in grass): keep its own texture.
			// Grass and sand are only ever natural, and always blend: sand
			// fades out of the map just as grass cubes begin, so the last
			// sand cubes before the grass carry next to no sand weight, and
			// keeping their own texture drew them as a hard-edged patch.
			// Gravel is only ever a road or a street, so it blends too: the
			// ground it was laid over is what shows wherever the road
			// contour has left its cell.
			bool natural = own == 0 || own == 1 || own == 4 || own == 11
				|| (own == 3 && w.b > 0.001) || (own == 6 && w.a > 0.001);
			// Explicit derivatives from the baked UV: the remapped
			// coordinates jump at face edges and would pick a blurry mip.
			vec2 dx = dFdx(UV);
			vec2 dy = dFdy(UV);
			if (natural && land > 0.001) {
				int g = top_face ? 0 : 1;
				ALBEDO = (w.r * textureGrad(atlas, slot_uv(g, local), dx, dy).rgb
					+ w.g * textureGrad(atlas, slot_uv(4, local), dx, dy).rgb
					+ w.b * textureGrad(atlas, slot_uv(3, local), dx, dy).rgb
					+ w.a * textureGrad(atlas, slot_uv(6, local), dx, dy).rgb) / land;
			}
			// The road over the ground, cut at the map's 0.5 contour and
			// carried a pixel or so past it so the edge does not crawl.
			if (top_face) {
				float road = texture(road_map, world_pos.xz / MAP_SIZE).r;
				float aa = max(fwidth(road), 0.002);
				ALBEDO = mix(ALBEDO, textureGrad(atlas, slot_uv(11, local), dx, dy).rgb,
					smoothstep(0.5 - aa, 0.5 + aa, road));
			}
			// Wet ground at the waterline.
			ALBEDO *= 1.0 - 0.3 * water;
		}
	}

	// Only cut from the cell above the feet upward, so ramps and slabs
	// around the character stay put. Everything goes by whole cells; only
	// what hangs on a wall is cut through, at the plane itself.
	bool wall = knockdown > 0.5 && knockdown < 1.5;
	bool hung = knockdown > 1.5 && knockdown < 2.5;
	// A wall goes as soon as its own cell reaches the cut, a cube before
	// anything else, so what is left of it stands one cube: waist height
	// on a two-cube figure, which is the point of knocking it down.
	float above = hung ? (world_pos.y >= cutout_floor ? 1.0 : 0.0)
		: ((wall ? cell_y >= cutout_floor : cell_y > cutout_floor) ? 1.0 : 0.0);
	float dxz = length(rel.xz);
	// The cell this fragment belongs to, nudged inward off its face so the
	// outer faces of edge cubes count with their cube.
	vec2 cellxz = floor(world_pos.xz - world_n.xz * 0.01);
	bool has_own = own_building.x <= own_building.z;
	float cut = 0.0;

	// Occluding buildings: cubes and walls inside their footprint above the
	// character's waist go; furniture stays on the ground floor but goes
	// with the upper floors, so nothing is left hanging in the air.
	if (occluder_strength > 0.0 && (in_rect(cellxz, occluder_a) || in_rect(cellxz, occluder_b) || in_rect(cellxz, occluder_c))) {
		bool building = knockdown > 0.5 || cutout_exempt < 0.5;
		float upstairs = cell_y > occluder_upper ? 1.0 : 0.0;
		cut = (building ? above : upstairs) * occluder_strength;
	}

	// Knock-down. A wall piece is in front of the character when its cell
	// lies on the camera's side of theirs along the axis the wall faces, or
	// in their own row (the wall they stand in the doorway of). A post
	// where walls meet belongs to both, and stays while either stands.
	if ((wall || hung) && cutout_enabled > 0.0) {
		vec3 facing = (INV_VIEW_MATRIX * vec4(TANGENT, 0.0)).xyz;
		// Only a hung piece goes by the wall cell behind it.
		vec2 wallcell = hung ? cellxz - round(facing.xz) : cellxz;
		vec2 relcell = wallcell - floor(player_pos.xz);
		vec2 camside = -cam_forward.xz;
		bool on_x = relcell.x * camside.x >= 0.0;
		bool on_z = relcell.y * camside.y >= 0.0;
		bool front;
		if (abs(facing.y) > 0.5) {
			front = on_x && on_z;
		} else if (abs(facing.x) > abs(facing.z)) {
			front = on_x;
		} else {
			front = on_z;
		}
		// The character's own building, whole; under other cover (a tree,
		// a bridge) whatever wall pieces are within reach.
		float near = has_own ? (in_rect(cellxz, own_building) ? 1.0 : 0.0)
			: clamp((knock_radius - dxz) / slice_fade, 0.0, 1.0);
		cut = max(cut, (front ? 1.0 : 0.0) * above * near * cutout_enabled);
	}

	// Cave walls. A rock cube that hides a passage from this yaw goes;
	// underground every such wall, nearer the surface those within reach.
	if (knockdown > 2.5 && cutout_enabled > 0.0) {
		vec2 camside = -cam_forward.xz;
		int yaw = (camside.x > 0.0 ? 1 : 0) + (camside.y > 0.0 ? 2 : 0);
		float bit = yaw == 0 ? COLOR.r : (yaw == 1 ? COLOR.g : (yaw == 2 ? COLOR.b : COLOR.a));
		bool front = bit > 0.5;
		float near = max(underground, clamp((knock_radius - dxz) / slice_fade, 0.0, 1.0));
		cut = max(cut, (front ? 1.0 : 0.0) * above * near * cutout_enabled);
	}

	// Level slice.
	// Indoors the whole of the character's own building is sliced and
	// nothing else (other roofs are left to the occluder cut, so none
	// half-fades into a ghost); elsewhere the radius handles trees and the
	// like overhead.
	float slice_reach = has_own ? (in_rect(cellxz, own_building) ? 1.0 : 0.0)
		: clamp((slice_radius - dxz) / slice_fade, 0.0, 1.0);
#ifdef NATURE
	// A tree is one item in its root cell, so cut it where the slice plane
	// (the floor of the first hidden cell) crosses the trunk.
	float over = world_pos.y > slice_height + 0.5 ? 1.0 : 0.0;
#elif defined(WATER)
	// The water sheet is one mesh to the chunk, so cell_y is the chunk's
	// own y, not the water's: cut it where the plane crosses the surface.
	float over = world_pos.y > slice_height + 0.5 ? 1.0 : 0.0;
#else
	float over = cell_y > slice_height ? 1.0 : 0.0;
#endif
	float sliced = over * slice_reach * slice_strength;
	cut = max(cut, sliced);
	// Every cut above is a way of seeing the character, not a hole in the
	// world. Underground it must not be one for the light either: rock cut
	// away there keeps its shadow, so a knocked-down wall still stands in
	// the torch's way and the lifted ground still keeps the sun out of the
	// cave, which has only the torch and a dim fill of its own. A fragment
	// is being drawn into a shadow map when it is seen from a light rather
	// than from the camera: down the sun's own direction, or along an axis,
	// which is how the six faces of an omni light's cube look and is a
	// direction the camera never takes. The cut fades out of the shadow
	// pass with depth, so it does not switch over in a step.
	vec3 view_dir = normalize(-(INV_VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 axis = abs(view_dir);
	bool shadow_pass = dot(view_dir, sun_forward) > 0.999 || max(axis.x, max(axis.y, axis.z)) > 0.999;
	float cut_here = shadow_pass ? cut * (1.0 - underground) : cut;
	if (cut_here > 0.0) {
		ivec2 px = ivec2(FRAGCOORD.xy) % 4;
		if (cut_here > BAYER[px.y * 4 + px.x]) {
			discard;
		}
	}
}
