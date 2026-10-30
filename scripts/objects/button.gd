class_name GameButton
extends GridObject

@export var color_id: String = "red"
@export var button_color: Color = Color("#e74c3c")
@export var is_pressed: bool = false

@onready var visual: ColorRect = $Visual
@onready var indicator: ColorRect = $Visual/Indicator

func _init() -> void:
	object_type = Type.BUTTON

func _ready() -> void:
	super._ready()
	update_state(is_pressed)

func set_pressed(pressed: bool) -> void:
	if is_pressed != pressed:
		is_pressed = pressed
		update_state(pressed)

func update_state(pressed: bool) -> void:
	if visual:
		visual.color = button_color
	if indicator:
		indicator.visible = pressed

func on_light_changed(lit: bool) -> void:
	modulate.a = LIT_ALPHA if lit else DARK_ALPHA
