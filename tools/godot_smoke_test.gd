extends SceneTree

func _init() -> void:
	var factory = load("res://scripts/level_factory.gd")
	var index_data = JSON.parse_string(FileAccess.get_file_as_string("res://levels/index.json"))
	if not (index_data is Dictionary):
		printerr("SMOKE TEST: index.json inválido")
		quit(1)
		return
	var checked := 0
	for entry in index_data.get("levels", []):
		var path := "res://levels/" + str(entry).trim_prefix("./")
		var level = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (level is Dictionary):
			printerr("SMOKE TEST: nivel inválido: ", path)
			quit(1)
			return
		var generated = factory.generate(level, 720.0)
		if int(generated.get("destructible_count", 0)) <= 0:
			printerr("SMOKE TEST: nivel sin bloques destruibles: ", path)
			quit(1)
			return
		checked += 1
	print("SMOKE TEST OK: ", checked, " niveles; escena principal: ", ResourceLoader.exists("res://scenes/main.tscn"))
	quit(0)
