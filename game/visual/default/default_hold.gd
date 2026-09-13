extends NoteView
## A gesture-art head with a coloured trail showing the hold's duration.

const GestureArt := preload("res://visual/default/gesture_art.gd")
const THICK := 0.34
const DEPTH := 0.12

var _mesh: MeshInstance3D
var _head: Sprite3D
var _color: Color
var _material: StandardMaterial3D


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	add_child(_mesh)
	_head = GestureArt.new()
	add_child(_head)
	_material = Emissive.make(Color.WHITE)
	_mesh.material_override = _material


func configure(note: Note, skin: GameSkin) -> void:
	_color = skin.slot_color(note.slot)
	var b := BoxMesh.new()
	var length: float = maxf(note.length * Field3D.SCROLL, 0.6)
	b.size = Vector3(DEPTH, THICK, length)
	_mesh.mesh = b
	# Anchor the near end at the hit moment; the trail extends up the panel.
	_mesh.position.z = -length * 0.5
	_head.configure(note.gesture)
	visible = true


func update_view(approach: float, progress: float) -> void:
	var c := _color
	c.a = clampf(1.15 - approach, 0.25, 1.0)
	c = c.lerp(Color(1, 1, 1, c.a), progress * 0.7)
	_material.albedo_color = c
	_material.emission = c
	_head.update_approach(approach)
