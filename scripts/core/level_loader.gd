class_name LevelLoader
extends RefCounted

class LevelData:
	var index: int = 0
	var name: String = ""
	var width: int = 0
	var height: int = 0
	var rows: Array[String] = []

static func load_levels_from_file(file_path: String = "res://data/levels.txt") -> Array[LevelData]:
	var result: Array[LevelData] = []
	if not FileAccess.file_exists(file_path):
		push_error("Level file not found: %s" % file_path)
		return result
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	var current_level: LevelData = null
	var reading_map: bool = false
	var level_counter: int = 0
	
	while not file.eof_reached():
		var raw_line = file.get_line()
		var line = raw_line.strip_edges()
		
		if line.begins_with("[Level"):
			if current_level != null and current_level.rows.size() > 0:
				current_level.height = current_level.rows.size()
				result.append(current_level)
			
			level_counter += 1
			current_level = LevelData.new()
			current_level.index = level_counter
			reading_map = false
			continue
		
		if current_level == null:
			continue
		
		if line.begins_with("name="):
			current_level.name = line.substr(5).strip_edges()
		elif line == "map=":
			reading_map = true
		elif reading_map:
			if line.length() > 0:
				current_level.rows.append(line)
				current_level.width = max(current_level.width, line.length())
			elif current_level.rows.size() > 0:
				# 空行代表當前地圖結束
				reading_map = false
	
	if current_level != null and current_level.rows.size() > 0:
		current_level.height = current_level.rows.size()
		result.append(current_level)
	
	return result

