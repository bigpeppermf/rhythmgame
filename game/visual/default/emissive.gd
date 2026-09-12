class_name Emissive
extends RefCounted
## Shared material helper for the default views. Your own skin scenes are free
## to ignore this entirely and use whatever materials you like.

static func make(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.4
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
