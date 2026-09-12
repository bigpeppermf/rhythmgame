## Silhouettes for the default note views, one per hand shape.
##
## Shape rather than colour, because colour does not survive the far end of
## the panel and the player has to read the required gesture while the note is
## still small. Any note with no gesture requirement keeps the plain dash.
##
## Meshes are built in the panel basis the playfield hands every view: -Z runs
## away down the panel, +Y is up, X is the panel's normal.
extends RefCounted

const DEPTH := 0.10


static func head_mesh(gesture: StringName) -> Mesh:
	match gesture:
		&"FIST":
			# A solid disc: the closed hand.
			var c := CylinderMesh.new()
			c.top_radius = 0.34
			c.bottom_radius = 0.34
			c.height = DEPTH
			return c
		&"THUMBS_UP":
			# A triangle pointing up.
			var pr := PrismMesh.new()
			pr.size = Vector3(0.76, 0.70, DEPTH)
			return pr
		&"PINCH":
			# A small diamond: two fingertips meeting.
			var b := BoxMesh.new()
			b.size = Vector3(DEPTH, 0.46, 0.46)
			return b
		_:
			# OPEN_PALM and "any": the plain dash.
			var d := BoxMesh.new()
			d.size = Vector3(DEPTH, 0.30, 1.5)
			return d


## Rotation to apply to head_mesh() so it faces along the panel's normal.
static func head_rotation(gesture: StringName) -> Vector3:
	match gesture:
		&"FIST": return Vector3(0, 0, 90)      # cylinder axis Y -> X (panel normal)
		&"THUMBS_UP": return Vector3(0, 90, 0) # prism faces Z -> X
		&"PINCH": return Vector3(45, 0, 0)     # square -> diamond, in the panel plane
		_: return Vector3.ZERO
