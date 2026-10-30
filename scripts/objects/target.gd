class_name Target
extends GridObject

@onready var visual: ColorRect = $Visual
@onready var center: ColorRect = $Visual/Center

func _init() -> void:
	object_type = Type.TARGET

func on_light_changed(lit: bool) -> void:
	modulate.a = LIT_ALPHA if lit else DARK_ALPHA
