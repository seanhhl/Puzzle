class_name LightSystem
extends RefCounted

static func calculate_lit_tiles(
	bounds: Rect2i,
	light_sources: Array[Vector2i],
	blocker_positions: Dictionary # Vector2i -> bool (true if blocks light)
) -> Dictionary: # Vector2i -> bool
	var lit_tiles: Dictionary = {}
	var queue: Array[Vector2i] = []

	for source in light_sources:
		if not lit_tiles.has(source):
			lit_tiles[source] = true
			queue.append(source)

	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	while queue.size() > 0:
		var current := queue.pop_front() as Vector2i

		# 若當前格本身是阻擋物，照亮但不繼續傳播
		if blocker_positions.get(current, false):
			continue

		for dir in directions:
			var neighbor := current + dir

			# 邊界檢測
			if not bounds.has_point(neighbor):
				continue

			if not lit_tiles.has(neighbor):
				lit_tiles[neighbor] = true
				# 規則13：光線會照亮障礙物所在的格子，但無法穿透障礙物繼續傳播
				# 阻擋格加入 lit_tiles 但不加入 queue（由下一輪 blocker check 跳過）
				queue.append(neighbor)

	return lit_tiles
