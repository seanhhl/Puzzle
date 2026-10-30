class_name Door
extends GridObject

## Doors allow light to pass through regardless of open/closed state.
## When closed and lit, doors block physical movement (is_blocking == true).
## When open or in the dark, doors allow passage (is_blocking == false).

@export var color_id: String = "red"
@export var door_color: Color = Color("#c0392b")
@export var default_is_open: bool = false

var is_open: bool = false

@onready var solid_visual: ColorRect = $SolidVisual
@onready var open_visual: ReferenceRect = $OpenVisual

func _init() -> void:
	object_type = Type.DOOR
	base_blocking = true

func _get_is_blocking() -> bool:
	return base_blocking and not is_open

func _ready() -> void:
	super._ready()
	set_open(default_is_open)

func set_open(open_state: bool) -> void:
	is_open = open_state
	update_state()

func update_state() -> void:
	if solid_visual:
		solid_visual.visible = not is_open
		solid_visual.color = door_color
	if open_visual:
		open_visual.visible = is_open
		open_visual.border_color = door_color

func on_light_changed(lit: bool) -> void:
	modulate.a = LIT_ALPHA if lit else DARK_ALPHA
