class_name Wall
extends GridObject

@onready var visual: ColorRect = $Visual

func _init() -> void:
	object_type = Type.WALL
	base_blocking = true

func on_light_changed(lit: bool) -> void:
	if visual:
		visual.color = Colors.WALL_LIT if lit else Colors.WALL_DARK
