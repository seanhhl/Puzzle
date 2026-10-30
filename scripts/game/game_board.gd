class_name GameBoard
extends Node2D

@onready var grid_manager: GridManager = $GridManager
@onready var world_container: Node2D = $WorldContainer
@onready var ground_view: GroundView = $WorldContainer/GroundView
@onready var camera: Camera2D = $Camera2D

# UI Nodes
@onready var level_title_label: Label = %LevelTitleLabel
@onready var hint_label: Label = %HintLabel
@onready var win_banner: PanelContainer = %WinBanner
@onready var select_level_button: Button = %SelectLevelButton
@onready var level_select_dialog: LevelSelectDialog = %LevelSelectDialog

var levels: Array = []
var current_level_index: int = 0
var is_level_won: bool = false

func _ready() -> void:
	ground_view.grid_manager = grid_manager

	# Connect GridManager signals
	grid_manager.level_completed.connect(_on_level_completed)
	grid_manager.state_updated.connect(_on_state_updated)

	# Connect LevelSelectDialog signals
	if level_select_dialog != null:
		level_select_dialog.level_selected.connect(_on_level_selected)

	if select_level_button != null:
		select_level_button.pressed.connect(open_level_select)

	# Priority 1: Scan separate LDtk / JSON level files from res://data/levels/
	levels = LdtkLoader.load_all_levels_from_dir("res://data/levels/")
	# Priority 2: Fallback to legacy levels.txt if directory is empty
	if levels.is_empty():
		levels = LevelLoader.load_levels_from_file("res://data/levels.txt")

	# Check command-line arguments: e.g. --level <filename>
	var cli_level := _get_cli_level_arg()
	if not cli_level.is_empty() and load_level_by_filename(cli_level):
		if level_select_dialog != null:
			level_select_dialog.close()
		return

	# Load default level in the background
	if not levels.is_empty():
		load_level(0)

	# Prompt the level selection dialog at startup
	if level_select_dialog != null:
		open_level_select()

## Opens the level selection modal with available level candidates.
func open_level_select() -> void:
	if level_select_dialog == null:
		return
	var suggested := get_available_level_filenames()
	level_select_dialog.open(suggested)

## Scans for available level files in res://data/levels/ and res://data/.
func get_available_level_filenames() -> Array[String]:
	var result: Array[String] = []
	var dir_path := "res://data/levels/"
	if DirAccess.dir_exists_absolute(dir_path):
		var dir := DirAccess.open(dir_path)
		if dir != null:
			dir.list_dir_begin()
			var file_name := dir.get_next()
			while file_name != "":
				if not dir.current_is_dir():
					var ext := file_name.get_extension().to_lower()
					if ext in ["ldtkl", "json", "ldtk"]:
						result.append(file_name)
				file_name = dir.get_next()
			dir.list_dir_end()
	result.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	if FileAccess.file_exists("res://data/levels.txt"):
		result.append("levels.txt")
	return result

func load_level(idx: int) -> void:
	if idx < 0 or idx >= levels.size():
		return

	current_level_index = idx
	is_level_won = false
	win_banner.visible = false

	var data = levels[idx]
	level_title_label.text = "Level %d - %s" % [data.index, data.name]

	if data is LdtkLoader.LdtkLevelData:
		grid_manager.build_level_ldtk(data, world_container)
	elif data is LevelLoader.LevelData:
		grid_manager.build_level(data, world_container)

	_center_camera(data.width, data.height)
	ground_view.queue_redraw()

## Loads a level given a query (filename, level name, or numeric index).
## Returns true on success, false if file is not found.
func load_level_by_filename(query: String) -> bool:
	var trimmed := query.strip_edges()
	if trimmed.is_empty():
		return false

	# 1. 1-based number index matching existing loaded levels
	if trimmed.is_valid_int():
		var target_idx := trimmed.to_int() - 1
		if target_idx >= 0 and target_idx < levels.size():
			load_level(target_idx)
			return true

	# 2. Match currently loaded levels by identifier, name, or filename
	var query_lower := trimmed.to_lower()
	for i in range(levels.size()):
		var lvl = levels[i]
		if lvl is LdtkLoader.LdtkLevelData:
			var ldtk_data: LdtkLoader.LdtkLevelData = lvl
			if ldtk_data.identifier.to_lower() == query_lower or ldtk_data.name.to_lower() == query_lower:
				load_level(i)
				return true
			var base_file: String = ldtk_data.file_path.get_file().to_lower()
			if base_file == query_lower or base_file.get_basename() == query_lower:
				load_level(i)
				return true
		elif lvl is LevelLoader.LevelData:
			var txt_data: LevelLoader.LevelData = lvl
			if txt_data.name.to_lower() == query_lower or ("level " + str(txt_data.index)) == query_lower:
				load_level(i)
				return true

	# 3. Resolve possible file paths on disk
	var resolved_path := _resolve_level_file_path(trimmed)
	if resolved_path.is_empty() or not FileAccess.file_exists(resolved_path):
		return false

	var ext := resolved_path.get_extension().to_lower()
	if ext == "txt":
		var txt_levels := LevelLoader.load_levels_from_file(resolved_path)
		if not txt_levels.is_empty():
			levels = txt_levels
			load_level(0)
			return true
	elif ext in ["ldtk", "json", "ldtkl"]:
		var ldtk_lvl := LdtkLoader.load_level_from_file(resolved_path)
		if ldtk_lvl != null:
			var found_idx := -1
			for i in range(levels.size()):
				if levels[i] is LdtkLoader.LdtkLevelData:
					var existing_ldtk: LdtkLoader.LdtkLevelData = levels[i]
					if existing_ldtk.file_path == ldtk_lvl.file_path:
						found_idx = i
						break
			if found_idx >= 0:
				load_level(found_idx)
			else:
				levels.append(ldtk_lvl)
				load_level(levels.size() - 1)
			return true

	return false

func _resolve_level_file_path(query: String) -> String:
	var q_clean := query.strip_edges()
	var q_lower := q_clean.to_lower()

	# Exact candidate paths
	var direct_candidates := [
		q_clean,
		"res://" + q_clean if not q_clean.begins_with("res://") else q_clean,
		"res://data/levels/".path_join(q_clean),
		"res://data/".path_join(q_clean)
	]
	for p in direct_candidates:
		if FileAccess.file_exists(p):
			return p
		for ext in [".ldtkl", ".json", ".ldtk", ".txt"]:
			if FileAccess.file_exists(p + ext):
				return p + ext

	# Case-insensitive scan in res://data/levels/
	var dir := DirAccess.open("res://data/levels/")
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				var f_lower := fname.to_lower()
				if f_lower == q_lower or f_lower.get_basename() == q_lower:
					return "res://data/levels/".path_join(fname)
			fname = dir.get_next()
		dir.list_dir_end()

	return ""

func _get_cli_level_arg() -> String:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg: String = str(args[i])
		if arg == "--level" and i + 1 < args.size():
			return args[i + 1]
		if arg.begins_with("--level="):
			return arg.substr(8)
	return ""

func _on_level_selected(query: String) -> void:
	if query.is_empty():
		if not levels.is_empty():
			load_level(0)
			level_select_dialog.close()
		else:
			level_select_dialog.show_error("No default levels available!")
		return

	if load_level_by_filename(query):
		level_select_dialog.close()
	else:
		level_select_dialog.show_error("找不到關卡或檔案不存在: \"%s\"" % query)

func _center_camera(width: int, height: int) -> void:
	var tile_size := GridObject.TILE_SIZE
	var center_x := (width * tile_size) / 2.0
	var center_y := (height * tile_size) / 2.0
	camera.position = Vector2(center_x, center_y)

func _unhandled_input(event: InputEvent) -> void:
	# Ignore gameplay inputs when level select dialog is open
	if level_select_dialog != null and level_select_dialog.visible:
		return

	if not (event is InputEventKey and event.is_pressed() and not event.is_echo()):
		return

	# Level select hotkey
	if event.keycode == KEY_L:
		open_level_select()
		return

	# Level completed: only allow level switching and reset
	if is_level_won:
		match event.keycode:
			KEY_N:
				if current_level_index + 1 < levels.size():
					load_level(current_level_index + 1)
			KEY_R:
				load_level(current_level_index)
			KEY_P:
				if current_level_index - 1 >= 0:
					load_level(current_level_index - 1)
		return

	var move_dir := Vector2i.ZERO

	match event.keycode:
		KEY_W, KEY_UP:
			move_dir = Vector2i.UP
		KEY_S, KEY_DOWN:
			move_dir = Vector2i.DOWN
		KEY_A, KEY_LEFT:
			move_dir = Vector2i.LEFT
		KEY_D, KEY_RIGHT:
			move_dir = Vector2i.RIGHT
		KEY_R:
			load_level(current_level_index)
			return
		KEY_Z:
			grid_manager.undo()
			return
		KEY_N:
			if current_level_index + 1 < levels.size():
				load_level(current_level_index + 1)
			return
		KEY_P:
			if current_level_index - 1 >= 0:
				load_level(current_level_index - 1)
			return

	if move_dir != Vector2i.ZERO:
		grid_manager.try_move_player(move_dir)

func _on_state_updated() -> void:
	ground_view.queue_redraw()
	var won := grid_manager.check_win_condition()
	if won and not is_level_won:
		is_level_won = true
		win_banner.visible = true

func _on_level_completed() -> void:
	pass
