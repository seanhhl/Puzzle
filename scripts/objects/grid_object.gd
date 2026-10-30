class_name GridObject
extends Node2D

enum Type {
	WALL,
	PLAYER,
	CRATE,
	LIGHT_BALL,
	DOOR,
	BUTTON,
	TARGET
}

@export var object_type: Type = Type.WALL
@export var grid_pos: Vector2i = Vector2i.ZERO
@export var is_lit: bool = false

## Base blocking property. Wall and Door are true; others are false by default.
@export var base_blocking: bool = false

## Base pushable property. Crate and LightBall are true; others are false by default.
@export var base_pushable: bool = false

## Dynamic blocking property. Returns true only if illuminated (is_lit) and base_blocking is true.
## If not illuminated, it is always false.
var is_blocking: bool:
	get:
		if not is_lit:
			return false
		return _get_is_blocking()

func _get_is_blocking() -> bool:
	return base_blocking

## Dynamic pushable property. Returns true only if illuminated (is_lit) and base_pushable is true.
## If not illuminated, it is always false.
var is_pushable: bool:
	get:
		if not is_lit:
			return false
		return _get_is_pushable()

func _get_is_pushable() -> bool:
	return base_pushable

const TILE_SIZE: int = 64
const HALF_TILE: int = TILE_SIZE / 2

# 共用色票常數 — 所有子類別引用，避免魔術字串分散
class Colors:
	# Player
	const PLAYER_LIT = Color("#f39c12")
	const PLAYER_LIT_INNER = Color("#f1c40f")
	const PLAYER_DARK = Color("#34495e")
	const PLAYER_DARK_INNER = Color("#2c3e50")
	# Crate
	const CRATE_LIT = Color("#e67e22")
	const CRATE_LIT_BORDER = Color("#d35400")
	const CRATE_DARK = Color("#7f8c8d")
	const CRATE_DARK_BORDER = Color("#34495e")
	# Wall
	const WALL_LIT = Color("#555555")
	const WALL_DARK = Color("#222222")
	# Ground
	const GROUND_LIT = Color("#2e261f")
	const GROUND_DARK = Color("#121317")
	const GROUND_GRID_LINE = Color("#1f2026", 0.5)

const LIT_ALPHA: float = 1.0
const DARK_ALPHA: float = 0.35

func _ready() -> void:
	update_visual_position(false)

func set_grid_pos(new_pos: Vector2i, animate: bool = false) -> void:
	grid_pos = new_pos
	update_visual_position(animate)

func update_visual_position(animate: bool = false) -> void:
	var target_pos := Vector2(grid_pos * TILE_SIZE) + Vector2(HALF_TILE, HALF_TILE)
	if animate and is_inside_tree():
		var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "position", target_pos, 0.1)
	else:
		position = target_pos

func set_lit(lit: bool) -> void:
	if is_lit != lit:
		is_lit = lit
		on_light_changed(lit)

func on_light_changed(_lit: bool) -> void:
	# 由子類別實作外觀或狀態更新
	pass
