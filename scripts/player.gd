class_name Player
extends Figure

## The figure the user drives: the pack's knight, with a sword and shield,
## and the x-ray silhouette that shows it through anything in the way.

const MODEL := "Knight.glb"
const GEAR: Array[String] = ["1H_Sword", "Badge_Shield"]
const XRAY_STENCIL := 1  # the figure's own pixels; shaders/xray.gdshader skips them

var _xray: ShaderMaterial


func _ready() -> void:
	model_file = MODEL
	gear = GEAR
	super()
	_xray = ShaderMaterial.new()
	_xray.shader = load("res://shaders/xray.gdshader")
	_xray.render_priority = 10
	_mark_stencil()
	_add_xray_shell()


## Where the knight shows, it marks the stencil so the x-ray shell leaves
## it be: the helmet and shield stand out of the shell, in front of it.
func _mark_stencil() -> void:
	if _model == null:
		return
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if mat != null:
				mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
				mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
				mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
				mat.stencil_reference = XRAY_STENCIL


## One capsule around the figure, drawn only where it is hidden. A single
## convex shell avoids the body parts x-raying through each other; what
## sticks out of it is kept clear by the stencil.
func _add_xray_shell() -> void:
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.46  # about as wide as the helmet, so the silhouette fits the figure
	capsule.height = 2.0
	mi.mesh = capsule
	mi.material_override = _xray
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 1.0, 0)
	_body.add_child(mi)
