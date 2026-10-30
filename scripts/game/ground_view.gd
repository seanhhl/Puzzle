class_name GroundView
extends Node2D

var grid_manager: GridManager

func _draw() -> void:
	if grid_manager == null or grid_manager.bounds.size == Vector2i.ZERO:
		return

	var tile_size := GridObject.TILE_SIZE
	var bounds := grid_manager.bounds
	var lit := grid_manager.lit_tiles

	for y in range(bounds.size.y):
		for x in range(bounds.size.x):
			var cell := Vector2i(x, y)
			var rect := Rect2(Vector2(cell * tile_size), Vector2(tile_size, tile_size))
			var is_lit: bool = lit.get(cell, false)

			draw_rect(rect, GridObject.Colors.GROUND_LIT if is_lit else GridObject.Colors.GROUND_DARK, true)
			draw_rect(rect, GridObject.Colors.GROUND_GRID_LINE, false, 1.0)
