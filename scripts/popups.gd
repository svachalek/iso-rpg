class_name Popups
extends CanvasLayer

## Words over the heads of figures: a speech bubble for what somebody says
## and a number that floats up off whatever was hit. Both are drawn on the
## screen, not in the world, so they stay one size at any zoom, and follow
## their figure's head each frame; either hides while its figure is not
## drawn (the cuts have taken its floor away).

const HEAD := 1.9               # world units from the feet to over the head
const SAY_SECONDS := 2.6
const FADE_SECONDS := 0.35
const TAIL := 9.0               # pixels the bubble's tail points down
const BUBBLE_FILL := Color(0.98, 0.96, 0.9)
const BUBBLE_EDGE := Color(0.2, 0.16, 0.12)
const BUBBLE_TEXT := Color(0.12, 0.1, 0.08)
const NUMBER_SECONDS := 1.0
const NUMBER_RISE := 46.0       # pixels a damage number floats up over its life
const NUMBER_COLOR := Color(1.0, 0.33, 0.22)


class Floater:
	var fig: Node3D
	var node: Control
	var age := 0.0
	var life := 0.0
	var rise := 0.0             # pixels it has floated up by the end
	var at := Vector3.ZERO      # the world point it floats from, kept once its figure is gone


var camera: Camera3D
var _bubbles: Array[Floater] = []
var _numbers: Array[Floater] = []


## Puts `text` in a bubble over `fig`. Said again while its bubble still
## shows, the bubble only stays longer, so a held key does not chatter.
func say(fig: Node3D, text: String) -> void:
	for b in _bubbles:
		if b.fig == fig:
			b.age = minf(b.age, FADE_SECONDS)
			return
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BUBBLE_FILL
	style.border_color = BUBBLE_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", BUBBLE_TEXT)
	label.add_theme_font_size_override("font_size", 15)
	panel.add_child(label)
	# The bubble and its tail side by side in a plain Control: inside the
	# PanelContainer the tail would be stretched over the whole panel.
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	# The tail: a wedge under the middle of the bubble, its outline drawn
	# over the border so the two read as one shape.
	var tail := Control.new()
	tail.draw.connect(func() -> void:
		var w := TAIL
		var pts := PackedVector2Array([Vector2(-w, -2), Vector2(w, -2), Vector2(0, TAIL)])
		tail.draw_colored_polygon(pts, BUBBLE_FILL)
		tail.draw_line(Vector2(-w, 0), Vector2(0, TAIL), BUBBLE_EDGE, 2.0, true)
		tail.draw_line(Vector2(w, 0), Vector2(0, TAIL), BUBBLE_EDGE, 2.0, true))
	root.add_child(tail)
	panel.resized.connect(func() -> void:
		tail.position = Vector2(panel.size.x * 0.5, panel.size.y - 2.0))
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var b := Floater.new()
	b.fig = fig
	b.node = root
	b.life = SAY_SECONDS
	_bubbles.append(b)
	_place(b)


## A number floating up off `fig`.
func damage(fig: Node3D, amount: int) -> void:
	var label := Label.new()
	label.text = str(amount)
	label.add_theme_color_override("font_color", NUMBER_COLOR)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 32)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	var n := Floater.new()
	n.fig = fig
	n.node = label
	n.life = NUMBER_SECONDS
	n.rise = NUMBER_RISE
	_numbers.append(n)
	_place(n)


func _process(delta: float) -> void:
	for list: Array[Floater] in [_bubbles, _numbers]:
		for i in range(list.size() - 1, -1, -1):
			var p := list[i]
			p.age += delta
			if p.age >= p.life:
				p.node.queue_free()
				list.remove_at(i)
				continue
			_place(p)


## Keeps a popup over its figure's head, fading it out at the end of its
## life. A bubble is sized by its panel, the root's first child.
func _place(p: Floater) -> void:
	if is_instance_valid(p.fig):
		p.at = p.fig.global_position
	var shown := camera != null and (not is_instance_valid(p.fig) or p.fig.is_visible_in_tree())
	p.node.visible = shown
	if not shown:
		return
	var k := p.age / p.life
	var screen := camera.unproject_position(p.at + Vector3(0, HEAD, 0))
	var sized: Control = p.node.get_child(0) if p.node.get_child_count() > 0 else p.node
	var size := sized.get_combined_minimum_size()
	var lift := p.rise * k
	var tail := TAIL if p.rise == 0.0 else 0.0
	p.node.position = (screen - Vector2(size.x * 0.5, size.y + tail + lift)).round()
	p.node.modulate.a = clampf((p.life - p.age) / FADE_SECONDS, 0.0, 1.0)
