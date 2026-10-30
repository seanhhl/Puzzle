class_name GridManager
extends Node

signal level_completed
signal state_updated

var player: Player
var walls: Array[Wall] = []
var crates: Array[Crate] = []
var light_balls: Array[LightBall] = []
var doors: Array[Door] = []
var buttons: Array[GameButton] = []
var targets: Array[Target] = []
var all_objects: Array[GridObject] = []

var bounds: Rect2i = Rect2i()
var lit_tiles: Dictionary = {} # Vector2i -> bool
var history: Array[Dictionary] = []

# Spatial indices: rebuilt in update_all_states() for O(1) lookups
var _wall_set: Dictionary = {} # Vector2i -> bool
var _spatial_map: Dictionary = {} # Vector2i -> Array[GridObject]

# Scene preloads
const SCENE_WALL: PackedScene = preload("res://scenes/objects/wall.tscn")
const SCENE_PLAYER: PackedScene = preload("res://scenes/objects/player.tscn")
const SCENE_CRATE: PackedScene = preload("res://scenes/objects/crate.tscn")
const SCENE_LIGHT_BALL: PackedScene = preload("res://scenes/objects/light_ball.tscn")
const SCENE_DOOR: PackedScene = preload("res://scenes/objects/door.tscn")
const SCENE_BUTTON: PackedScene = preload("res://scenes/objects/button.tscn")
const SCENE_TARGET: PackedScene = preload("res://scenes/objects/target.tscn")

func clear() -> void:
	for obj in all_objects:
		if is_instance_valid(obj):
			obj.queue_free()

	player = null
	walls.clear()
	crates.clear()
	light_balls.clear()
	doors.clear()
	buttons.clear()
	targets.clear()
	all_objects.clear()
	lit_tiles.clear()
	history.clear()
	_wall_set.clear()
	_spatial_map.clear()

## Builds a level from an LDtk level data instance
func build_level_ldtk(level_data: LdtkLoader.LdtkLevelData, parent_node: Node2D) -> void:
	clear()

	bounds = Rect2i(0, 0, level_data.width, level_data.height)

	var crate_map: Dictionary = {} # iid -> Crate
	var crate_connections: Dictionary = {} # iid -> Array[String]

	for ent in level_data.entities:
		var pos := ent.grid_pos
		match ent.identifier:
			"Wall":
				var wall: Wall = SCENE_WALL.instantiate()
				wall.set_grid_pos(pos)
				parent_node.add_child(wall)
				walls.append(wall)
				all_objects.append(wall)
			"Player":
				player = SCENE_PLAYER.instantiate()
				player.set_grid_pos(pos)
				parent_node.add_child(player)
				all_objects.append(player)
			"LightBall":
				var lb: LightBall = SCENE_LIGHT_BALL.instantiate()
				lb.set_grid_pos(pos)
				parent_node.add_child(lb)
				light_balls.append(lb)
				all_objects.append(lb)
			"Crate":
				var crate: Crate = SCENE_CRATE.instantiate()
				crate.iid = ent.iid
				crate.set_grid_pos(pos)
				parent_node.add_child(crate)
				crates.append(crate)
				all_objects.append(crate)
				crate_map[ent.iid] = crate

				# Parse connected_crates field
				var raw_links = ent.fields.get("connected_crates", [])
				if raw_links is Array:
					for link in raw_links:
						var target_iid := ""
						if link is Dictionary:
							target_iid = str(link.get("entityIid", ""))
						elif link is String:
							target_iid = str(link)
						if target_iid != "":
							if not crate_connections.has(ent.iid):
								crate_connections[ent.iid] = []
							crate_connections[ent.iid].append(target_iid)
							if not crate_connections.has(target_iid):
								crate_connections[target_iid] = []
							crate_connections[target_iid].append(ent.iid)
			"Door":
				var door: Door = SCENE_DOOR.instantiate()
				door.color_id = str(ent.fields.get("color_id", "red"))
				door.default_is_open = bool(ent.fields.get("default_is_open", false))
				door.set_grid_pos(pos)
				parent_node.add_child(door)
				doors.append(door)
				all_objects.append(door)
			"Button":
				var btn: GameButton = SCENE_BUTTON.instantiate()
				btn.color_id = str(ent.fields.get("color_id", "red"))
				btn.set_grid_pos(pos)
				parent_node.add_child(btn)
				buttons.append(btn)
				all_objects.append(btn)
			"Target":
				var target: Target = SCENE_TARGET.instantiate()
				target.set_grid_pos(pos)
				parent_node.add_child(target)
				targets.append(target)
				all_objects.append(target)

	# Setup bidirectional crate connections
	_setup_crate_connections(crate_map, crate_connections)

	_rebuild_wall_set()
	update_all_states()

## Legacy fallback for LevelLoader.LevelData (pure text format)
func build_level(level_data: LevelLoader.LevelData, parent_node: Node2D) -> void:
	clear()

	bounds = Rect2i(0, 0, level_data.width, level_data.height)

	for y in range(level_data.rows.size()):
		var line: String = level_data.rows[y]
		for x in range(line.length()):
			var tile_char: String = line[x]
			var grid_pos := Vector2i(x, y)
			_spawn_object_by_char(tile_char, grid_pos, parent_node)

	# In legacy format, no interconnected crates
	_setup_crate_connections({}, {})

	_rebuild_wall_set()
	update_all_states()

func _spawn_object_by_char(tile_char: String, pos: Vector2i, parent_node: Node2D) -> void:
	match tile_char:
		"#":
			var wall: Wall = SCENE_WALL.instantiate()
			wall.set_grid_pos(pos)
			parent_node.add_child(wall)
			walls.append(wall)
			all_objects.append(wall)
		"P":
			player = SCENE_PLAYER.instantiate()
			player.set_grid_pos(pos)
			parent_node.add_child(player)
			all_objects.append(player)
		"@":
			var lb: LightBall = SCENE_LIGHT_BALL.instantiate()
			lb.set_grid_pos(pos)
			parent_node.add_child(lb)
			light_balls.append(lb)
			all_objects.append(lb)
		"C":
			var crate: Crate = SCENE_CRATE.instantiate()
			crate.set_grid_pos(pos)
			parent_node.add_child(crate)
			crates.append(crate)
			all_objects.append(crate)
		"B":
			var btn: GameButton = SCENE_BUTTON.instantiate()
			btn.color_id = "red"
			btn.set_grid_pos(pos)
			parent_node.add_child(btn)
			buttons.append(btn)
			all_objects.append(btn)
		"D":
			var door: Door = SCENE_DOOR.instantiate()
			door.color_id = "red"
			door.default_is_open = false
			door.set_grid_pos(pos)
			parent_node.add_child(door)
			doors.append(door)
			all_objects.append(door)
		"T":
			var target: Target = SCENE_TARGET.instantiate()
			target.set_grid_pos(pos)
			parent_node.add_child(target)
			targets.append(target)
			all_objects.append(target)

## Setup bidirectional pointers between interconnected crates
func _setup_crate_connections(crate_map: Dictionary, connections: Dictionary) -> void:
	for c in crates:
		c.connected_crates.clear()

	for iid in connections:
		if not crate_map.has(iid):
			continue
		var crate_a: Crate = crate_map[iid]
		var neighbors: Array = connections[iid]
		for target_iid in neighbors:
			if crate_map.has(target_iid):
				var crate_b: Crate = crate_map[target_iid]
				if not crate_a.connected_crates.has(crate_b):
					crate_a.connected_crates.append(crate_b)
				if not crate_b.connected_crates.has(crate_a):
					crate_b.connected_crates.append(crate_a)

## Finds all connected crates in the same connected component via BFS.
## Uses crate.iid as visited key (or instance ID if iid is empty).
func get_connected_crates(start_crate: Crate) -> Array[Crate]:
	var result: Array[Crate] = []
	if start_crate == null or not is_instance_valid(start_crate):
		return result

	var visited: Dictionary = {}
	var queue: Array[Crate] = [start_crate]
	var start_key: String = start_crate.iid if not start_crate.iid.is_empty() else str(start_crate.get_instance_id())
	visited[start_key] = true

	while not queue.is_empty():
		var curr := queue.pop_front() as Crate
		result.append(curr)

		for neighbor in curr.connected_crates:
			if not is_instance_valid(neighbor):
				continue
			var n_key: String = neighbor.iid if not neighbor.iid.is_empty() else str(neighbor.get_instance_id())
			if not visited.has(n_key):
				visited[n_key] = true
				queue.append(neighbor)

	return result

# region 空間索引

func _rebuild_wall_set() -> void:
	_wall_set.clear()
	for w in walls:
		_wall_set[w.grid_pos] = true

func _rebuild_spatial_map() -> void:
	_spatial_map.clear()
	for obj in all_objects:
		if is_instance_valid(obj):
			var pos: Vector2i = obj.grid_pos
			if not _spatial_map.has(pos):
				_spatial_map[pos] = [] as Array[GridObject]
			_spatial_map[pos].append(obj)

func get_objects_at(pos: Vector2i) -> Array[GridObject]:
	return _spatial_map.get(pos, [] as Array[GridObject])

func is_blocking_at(pos: Vector2i) -> bool:
	for obj in get_objects_at(pos):
		if obj.is_blocking and not obj.is_pushable:
			return true
	return false

# endregion

func update_all_states() -> void:
	# 1. Collect light blockers (doors transmit light; only walls and crates block light)
	var blockers: Dictionary = {}
	for pos in _wall_set:
		blockers[pos] = true
	for c in crates:
		blockers[c.grid_pos] = true

	# 2. Calculate light propagation
	var sources: Array[Vector2i] = []
	for lb in light_balls:
		sources.append(lb.grid_pos)

	lit_tiles = LightSystem.calculate_lit_tiles(bounds, sources, blockers)

	# 3. Update base illumination state on all objects
	for obj in all_objects:
		obj.set_lit(lit_tiles.get(obj.grid_pos, false))

	# 3b. Connected crates illumination sharing:
	# If ANY crate in a connected component is illuminated, all connected crates in that component are illuminated!
	var lit_visited: Dictionary = {}
	for c in crates:
		var c_key: String = c.iid if not c.iid.is_empty() else str(c.get_instance_id())
		if lit_visited.has(c_key):
			continue

		var component := get_connected_crates(c)
		var any_lit := false
		for member in component:
			if lit_tiles.get(member.grid_pos, false):
				any_lit = true
				break

		for member in component:
			var m_key: String = member.iid if not member.iid.is_empty() else str(member.get_instance_id())
			lit_visited[m_key] = true
			member.set_lit(any_lit)

	# 4. Rebuild spatial map
	_rebuild_spatial_map()

	# 5. Update button states
	for btn in buttons:
		var pressed := false
		for obj in get_objects_at(btn.grid_pos):
			if obj != btn and obj.is_lit and (obj.is_pushable or obj is Player):
				pressed = true
				break
		btn.set_pressed(pressed)

	# 6. Update door states (doors transmit light, so changes never alter light propagation)
	for door in doors:
		var matching_buttons: Array[GameButton] = []
		for btn in buttons:
			if btn.color_id == door.color_id and btn.is_lit:
				matching_buttons.append(btn)
		if matching_buttons.is_empty():
			door.set_open(door.default_is_open)
		else:
			var all_lit_pressed := true
			for btn in matching_buttons:
				if not btn.is_pressed:
					all_lit_pressed = false
					break

			if all_lit_pressed:
				door.set_open(not door.default_is_open)
			else:
				door.set_open(door.default_is_open)

	state_updated.emit()

func try_move_player(dir: Vector2i) -> bool:
	if player == null or not is_instance_valid(player):
		return false

	# Rule 16: Player in dark cannot move
	if not player.is_lit:
		return false

	var target_pos := player.grid_pos + dir
	if not bounds.has_point(target_pos):
		return false

	# Push chain validation
	var moving_entities: Array[GridObject] = []
	var moving_set: Dictionary = {} # GridObject -> bool
	var queue: Array[GridObject] = []

	# Player initiates the movement
	moving_set[player] = true
	queue.append(player)

	while not queue.is_empty():
		var entity := queue.pop_front() as GridObject

		# 1. Overlapping check at entity's current grid position
		var overlaps := get_objects_at(entity.grid_pos)
		for overlap_obj in overlaps:
			if overlap_obj == entity or moving_set.has(overlap_obj):
				continue

			# Immovable blocking obstacle (e.g. lit wall, closed door) cancels the entire move
			if overlap_obj.is_blocking and not overlap_obj.is_pushable:
				return false

			# Pushable overlapping object joins the push chain
			if overlap_obj.is_pushable:
				moving_set[overlap_obj] = true
				moving_entities.append(overlap_obj)
				queue.append(overlap_obj)
			# Non-blocking non-pushable objects (buttons, unlit walls/crates) are directly ignored

		# 2. If entity is a Crate, find all transitively connected crates via BFS
		if entity is Crate:
			var connected := get_connected_crates(entity as Crate)
			for c in connected:
				if not moving_set.has(c):
					moving_set[c] = true
					moving_entities.append(c)
					queue.append(c)

		# 3. Check destination position (entity.grid_pos + dir)
		var dest_pos := entity.grid_pos + dir
		if not bounds.has_point(dest_pos):
			return false

		var dest_objects := get_objects_at(dest_pos)
		for dest_obj in dest_objects:
			if moving_set.has(dest_obj):
				continue

			# Immovable blocking obstacle (lit wall, closed lit door) at destination cancels the entire move
			if dest_obj.is_blocking and not dest_obj.is_pushable:
				return false

			# Pushable object at destination is pushed and joins the push chain
			if dest_obj.is_pushable:
				moving_set[dest_obj] = true
				moving_entities.append(dest_obj)
				queue.append(dest_obj)
			# Non-blocking non-pushable objects (buttons, targets, unlit walls/doors/crates) are directly ignored

	save_state()

	# Move all pushed entities
	for i in range(moving_entities.size() - 1, -1, -1):
		var item := moving_entities[i]
		item.set_grid_pos(item.grid_pos + dir, true)

	player.set_grid_pos(target_pos, true)

	update_all_states()
	return true

func check_win_condition() -> bool:
	if targets.is_empty():
		return false

	for t in targets:
		var has_lit_crate := false
		for c in crates:
			if c.grid_pos == t.grid_pos and c.is_lit:
				has_lit_crate = true
				break
		if not has_lit_crate:
			return false
	return true

func save_state() -> void:
	var state: Dictionary = {
		"player": player.grid_pos if player else Vector2i.ZERO,
		"crates": [] as Array[Vector2i],
		"light_balls": [] as Array[Vector2i],
	}
	for c in crates:
		state["crates"].append(c.grid_pos)
	for lb in light_balls:
		state["light_balls"].append(lb.grid_pos)
	history.append(state)

func undo() -> bool:
	if history.is_empty():
		return false

	var prev_state: Dictionary = history.pop_back()

	if player:
		player.set_grid_pos(prev_state["player"], true)
	for i in range(crates.size()):
		if i < prev_state["crates"].size():
			crates[i].set_grid_pos(prev_state["crates"][i], true)
	for i in range(light_balls.size()):
		if i < prev_state["light_balls"].size():
			light_balls[i].set_grid_pos(prev_state["light_balls"][i], true)

	update_all_states()
	return true
