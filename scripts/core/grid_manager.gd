class_name GridManager
extends Node

signal level_completed
signal state_updated

var player: Player
var walls: Array[Wall] = []
var crates: Array[Crate] = []
var crate_clusters: Array[CrateCluster] = []
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
var _entity_map: Dictionary = {} # Vector2i -> GridObject

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
	crate_clusters.clear()
	light_balls.clear()
	doors.clear()
	buttons.clear()
	targets.clear()
	all_objects.clear()
	lit_tiles.clear()
	history.clear()
	_wall_set.clear()
	_entity_map.clear()

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

	# Build connected crate clusters
	_build_crate_clusters(crate_map, crate_connections)

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

	# Every crate is its own single cluster in legacy format
	_build_crate_clusters({}, {})

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

func _build_crate_clusters(crate_map: Dictionary, connections: Dictionary) -> void:
	crate_clusters.clear()
	var visited: Dictionary = {}

	# 1. Process explicit clusters from connections
	for iid in crate_map:
		if visited.has(iid):
			continue

		var cluster := CrateCluster.new()
		cluster.id = crate_clusters.size() + 1

		var queue: Array[String] = [iid]
		visited[iid] = true

		while not queue.is_empty():
			var curr_iid := queue.pop_front() as String
			var curr_crate: Crate = crate_map[curr_iid]
			cluster.crates.append(curr_crate)
			curr_crate.cluster = cluster

			var neighbors: Array = connections.get(curr_iid, [])
			for neighbor_iid in neighbors:
				if crate_map.has(neighbor_iid):
					var neighbor_crate: Crate = crate_map[neighbor_iid]
					if not curr_crate.connected_crates.has(neighbor_crate):
						curr_crate.connected_crates.append(neighbor_crate)
					if not neighbor_crate.connected_crates.has(curr_crate):
						neighbor_crate.connected_crates.append(curr_crate)

					if not visited.has(neighbor_iid):
						visited[neighbor_iid] = true
						queue.append(neighbor_iid)

		crate_clusters.append(cluster)

	# 2. Ensure any remaining crate without links gets its own 1-crate cluster
	for c in crates:
		if c.cluster == null:
			var single_cluster := CrateCluster.new()
			single_cluster.id = crate_clusters.size() + 1
			single_cluster.crates.append(c)
			c.cluster = single_cluster
			crate_clusters.append(single_cluster)

# region 空間索引

func _rebuild_wall_set() -> void:
	_wall_set.clear()
	for w in walls:
		_wall_set[w.grid_pos] = true

func _rebuild_entity_map() -> void:
	_entity_map.clear()
	# Only illuminated crates possess collision volume
	for c in crates:
		if c.is_lit:
			_entity_map[c.grid_pos] = c
	# Lightballs always possess collision volume
	for lb in light_balls:
		_entity_map[lb.grid_pos] = lb

func is_blocking_at(pos: Vector2i) -> bool:
	for w in walls:
		if w.grid_pos == pos and w.is_blocking:
			return true
	for d in doors:
		if d.grid_pos == pos and d.is_blocking:
			return true
	return false

func is_wall_at(pos: Vector2i) -> bool:
	return is_blocking_at(pos)

func is_closed_door_at(pos: Vector2i) -> bool:
	for d in doors:
		if d.grid_pos == pos and d.is_blocking:
			return true
	return false

func get_solid_entity_at(pos: Vector2i) -> GridObject:
	return _entity_map.get(pos, null)

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

	# 3b. Any-Lit rule for connected crate clusters:
	# If ANY crate in a cluster is illuminated, the ENTIRE cluster is illuminated!
	for cluster in crate_clusters:
		var any_lit := false
		for c in cluster.crates:
			if lit_tiles.get(c.grid_pos, false):
				any_lit = true
				break
		cluster.set_all_lit(any_lit)

	# 4. Rebuild entity spatial map (crate solidity depends on is_lit)
	_rebuild_entity_map()

	# 5. Update button states
	for btn in buttons:
		var pressed := false
		if player and player.grid_pos == btn.grid_pos and player.is_lit:
			pressed = true
		if not pressed:
			for c in crates:
				if c.grid_pos == btn.grid_pos and c.is_lit:
					pressed = true
					break
		if not pressed:
			for lb in light_balls:
				if lb.grid_pos == btn.grid_pos:
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

	# Multi-push validation for rigid crate clusters and pushable entities
	var moving_entities: Array[GridObject] = []
	var moving_set: Dictionary = {} # GridObject -> bool
	var frontier: Array[Vector2i] = [target_pos]

	var can_move := true

	while not frontier.is_empty():
		var check_pos: Vector2i = frontier.pop_front()

		# Check impassable obstacle (wall or closed door)
		if is_blocking_at(check_pos):
			can_move = false
			break

		var solid_entity := get_solid_entity_at(check_pos)
		if solid_entity == null:
			# Reached an empty space (or unlit passable crate)
			continue

		# Already added to moving_set (internal movement within the same cluster or chain)
		if moving_set.has(solid_entity):
			continue

		# Non-pushable or blocking entity stops movement
		if not solid_entity.is_pushable or solid_entity.is_blocking:
			can_move = false
			break

		if solid_entity is Crate:
			var crate := solid_entity as Crate
			var cluster := crate.cluster
			if cluster != null and not cluster.crates.is_empty():
				# All crates in the cluster must move together as a single rigid body
				for member in cluster.crates:
					if not moving_set.has(member):
						moving_set[member] = true
						moving_entities.append(member)
						frontier.append(member.grid_pos + dir)
			else:
				moving_set[crate] = true
				moving_entities.append(crate)
				frontier.append(crate.grid_pos + dir)
		elif solid_entity is LightBall:
			moving_set[solid_entity] = true
			moving_entities.append(solid_entity)
			frontier.append(solid_entity.grid_pos + dir)
		else:
			can_move = false
			break

	if not can_move:
		return false

	save_state()

	# Move all entities in reverse order of addition
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
