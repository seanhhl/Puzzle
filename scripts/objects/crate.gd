class_name Crate
extends GridObject

var connected_crates: Array[Crate] = []
var iid: String = ""

@onready var visual: ColorRect = $Visual
@onready var border: ColorRect = $Visual/Border

func _init() -> void:
	object_type = Type.CRATE
	base_pushable = true

func _ready() -> void:
	super._ready()
	on_light_changed(is_lit)

func on_light_changed(lit: bool) -> void:
	if visual:
		if lit:
			modulate.a = LIT_ALPHA
			visual.color = Colors.CRATE_LIT
			if border:
				border.color = Colors.CRATE_LIT_BORDER
		else:
			modulate.a = DARK_ALPHA
			visual.color = Colors.CRATE_DARK
			if border:
				border.color = Colors.CRATE_DARK_BORDER
	queue_redraw()

func _draw() -> void:
	# Draw visual link indicators to connected neighbor crates
	if connected_crates.is_empty():
		return

	var link_color := Color("#f39c12") if is_lit else Color("#555555", 0.5)
	for other in connected_crates:
		if is_instance_valid(other):
			var delta: Vector2i = other.grid_pos - grid_pos
			# Only draw orthogonal adjacent connections
			if abs(delta.x) + abs(delta.y) == 1:
				var diff: Vector2 = Vector2(delta) * TILE_SIZE
				var target_offset := diff * 0.5
				draw_line(Vector2.ZERO, target_offset, link_color, 8.0)
				draw_circle(Vector2.ZERO, 5.0, link_color)
