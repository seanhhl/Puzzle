class_name Player
extends GridObject

@onready var visual: ColorRect = $Visual
@onready var inner: ColorRect = $Visual/Inner

func _init() -> void:
	object_type = Type.PLAYER

func _ready() -> void:
	super._ready()
	on_light_changed(is_lit)

func on_light_changed(lit: bool) -> void:
	if visual:
		if lit:
			visual.color = Colors.PLAYER_LIT
			if inner:
				inner.color = Colors.PLAYER_LIT_INNER
		else:
			visual.color = Colors.PLAYER_DARK
			if inner:
				inner.color = Colors.PLAYER_DARK_INNER
