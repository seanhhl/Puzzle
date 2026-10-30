class_name LdtkLoader
extends RefCounted

class EntityData:
	var identifier: String = ""
	var grid_pos: Vector2i = Vector2i.ZERO
	var iid: String = ""
	var fields: Dictionary = {}

class LdtkLevelData:
	var index: int = 0
	var identifier: String = ""
	var name: String = ""
	var file_path: String = ""
	var width: int = 0
	var height: int = 0
	var entities: Array[EntityData] = []

static func load_all_levels_from_dir(dir_path: String = "res://data/levels/") -> Array[LdtkLevelData]:
	var result: Array[LdtkLevelData] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		push_warning("Levels directory not found: %s" % dir_path)
		return result

	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Failed to open levels directory: %s" % dir_path)
		return result

	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var ext := file_name.get_extension().to_lower()
			if ext == "ldtk" or ext == "json" or ext == "ldtkl":
				files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Sort files naturally (e.g. level_01, level_02, level_10)
	files.sort_custom(func(a: String, b: String) -> bool:
		return a.naturalnocasecmp_to(b) < 0
	)

	var counter := 0
	for f in files:
		counter += 1
		var full_path := dir_path.path_join(f)
		var level_data := load_level_from_file(full_path)
		if level_data != null:
			level_data.index = counter
			result.append(level_data)

	return result

static func load_level_from_file(file_path: String) -> LdtkLevelData:
	if not FileAccess.file_exists(file_path):
		push_error("LDtk level file not found: %s" % file_path)
		return null

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to read file: %s" % file_path)
		return null

	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON content in: %s" % file_path)
		return null

	var root_dict: Dictionary = parsed
	var level_dict: Dictionary = {}

	# Handle both: standalone .ldtk project (has "levels" array) and separate level file (level at root)
	if root_dict.has("levels") and root_dict["levels"] is Array and not root_dict["levels"].is_empty():
		level_dict = root_dict["levels"][0]
		# If level is stored externally (.ldtkl), redirect to the external level file
		if level_dict.get("layerInstances") == null and level_dict.has("externalRelPath") and level_dict["externalRelPath"] != null:
			var rel_path: String = str(level_dict["externalRelPath"])
			var ext_full_path := file_path.get_base_dir().path_join(rel_path)
			var ext_level := load_level_from_file(ext_full_path)
			if ext_level != null:
				return ext_level
	elif root_dict.has("layerInstances"):
		level_dict = root_dict
	else:
		push_error("No valid level data found in JSON: %s" % file_path)
		return null

	var level_data := LdtkLevelData.new()
	level_data.file_path = file_path
	level_data.identifier = level_dict.get("identifier", file_path.get_file().get_basename())
	level_data.name = level_data.identifier

	# Check custom level fields for human-readable level_name
	if level_dict.has("fieldInstances") and level_dict["fieldInstances"] is Array:
		for field in level_dict["fieldInstances"]:
			if field is Dictionary and field.get("__identifier") == "level_name":
				var custom_name = field.get("__value")
				if custom_name != null and str(custom_name).strip_edges() != "":
					level_data.name = str(custom_name)

	var grid_size := 64
	var px_wid: int = int(level_dict.get("pxWid", 640))
	var px_hei: int = int(level_dict.get("pxHei", 640))

	# Find entity layers
	if level_dict.has("layerInstances") and level_dict["layerInstances"] is Array:
		for layer in level_dict["layerInstances"]:
			if not (layer is Dictionary):
				continue
			var layer_grid: int = int(layer.get("__gridSize", 64))
			if layer_grid > 0:
				grid_size = layer_grid

			# Process entity instances from layer
			if layer.has("entityInstances") and layer["entityInstances"] is Array:
				for entity in layer["entityInstances"]:
					if not (entity is Dictionary):
						continue
					var ent_data := EntityData.new()
					ent_data.identifier = entity.get("__identifier", "")
					ent_data.iid = entity.get("iid", "")

					var grid_arr = entity.get("__grid", [0, 0])
					if grid_arr is Array and grid_arr.size() >= 2:
						ent_data.grid_pos = Vector2i(int(grid_arr[0]), int(grid_arr[1]))

					# Parse custom field instances
					if entity.has("fieldInstances") and entity["fieldInstances"] is Array:
						for f in entity["fieldInstances"]:
							if f is Dictionary and f.has("__identifier"):
								ent_data.fields[f["__identifier"]] = f.get("__value")

					level_data.entities.append(ent_data)

			# Process IntGrid layers (e.g. Walls drawn directly using tile grid brush)
			if layer.has("intGridCsv") and layer["intGridCsv"] is Array:
				var csv: Array = layer["intGridCsv"]
				var c_wid: int = int(layer.get("__cWid", px_wid / grid_size))
				if not csv.is_empty() and c_wid > 0:
					var layer_ident: String = str(layer.get("__identifier", "Wall"))
					var ent_ident := "Wall"
					for idx in range(csv.size()):
						var val: int = int(csv[idx])
						if val > 0:
							var gx := idx % c_wid
							var gy := idx / c_wid
							var ent_data := EntityData.new()
							ent_data.identifier = ent_ident
							ent_data.grid_pos = Vector2i(gx, gy)
							ent_data.iid = "intgrid_%s_%d_%d" % [layer_ident, gx, gy]
							level_data.entities.append(ent_data)

	level_data.width = px_wid / grid_size
	level_data.height = px_hei / grid_size

	return level_data

