class_name LightBall
extends GridObject

@onready var visual: ColorRect = $Visual
@onready var core: ColorRect = $Visual/Core

func _init() -> void:
	object_type = Type.LIGHT_BALL
	is_lit = true
	base_pushable = true

func _ready() -> void:
	super._ready()
	# 光球本身自帶發光特性，恆定保持發光
	is_lit = true
