extends Node

signal levels_changed(levels: Array)
signal remote_status_changed(message: String)

const CONFIG_PATH := "res://config/game_config.json"
const LOCAL_INDEX_PATH := "res://levels/index.json"
const CACHE_PATH := "user://motiva_bricks_remote_levels.json"

var config: Dictionary = {}
var levels: Array = []
var local_levels: Array = []
var remote_levels: Array = []
var _http: HTTPRequest
var _request_mode := ""
var _remote_index_url := ""
var _pending_level_urls: Array[String] = []

func _ready() -> void:
	config = _read_json_dictionary(CONFIG_PATH)
	local_levels = _load_local_collection()
	levels = local_levels.duplicate(true)
	_http = HTTPRequest.new()
	_http.timeout = float(config.get("request_timeout_seconds", 6.0))
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	call_deferred("_emit_initial_levels")
	if bool(config.get("remote_enabled", false)):
		call_deferred("refresh_remote_levels")

func _emit_initial_levels() -> void:
	levels_changed.emit(get_levels())

func get_levels() -> Array:
	return levels.duplicate(true)

func get_level(index: int) -> Dictionary:
	if levels.is_empty():
		return {}
	return levels[clampi(index, 0, levels.size() - 1)].duplicate(true)

func get_config() -> Dictionary:
	return config.duplicate(true)

func refresh_remote_levels() -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_remote_index_url = str(config.get("remote_level_index_url", "")).strip_edges()
	if _remote_index_url.is_empty():
		remote_status_changed.emit("No hay una dirección remota configurada.")
		return
	_request_mode = "index"
	remote_status_changed.emit("Buscando escenarios en motiva.studio…")
	var error := _http.request(_remote_index_url)
	if error != OK:
		_request_mode = ""
		remote_status_changed.emit("No se pudo iniciar la descarga. Se mantienen los escenarios locales.")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_request_mode = ""
		remote_status_changed.emit("Servidor no disponible. Se mantienen los escenarios locales.")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if _request_mode == "index":
		_process_remote_index(parsed)
	elif _request_mode == "level":
		_process_remote_level(parsed)

func _process_remote_index(parsed: Variant) -> void:
	if not (parsed is Dictionary):
		_request_mode = ""
		remote_status_changed.emit("El índice remoto no tiene un formato válido.")
		return
	var entries: Array = parsed.get("levels", [])
	_pending_level_urls.clear()
	for entry in entries:
		if entry is Dictionary:
			var direct_url := str(entry.get("url", ""))
			if not direct_url.is_empty():
				_pending_level_urls.append(_join_url(_remote_index_url, direct_url))
		else:
			var path := str(entry)
			if not path.is_empty():
				_pending_level_urls.append(_join_url(_remote_index_url, path))
	remote_levels.clear()
	if _pending_level_urls.is_empty():
		_request_mode = ""
		remote_status_changed.emit("El servidor no ha publicado escenarios todavía.")
		return
	_request_next_remote_level()

func _request_next_remote_level() -> void:
	if _pending_level_urls.is_empty():
		_finish_remote_collection()
		return
	_request_mode = "level"
	var url: String = _pending_level_urls.pop_front()
	var error := _http.request(url)
	if error != OK:
		_request_mode = ""
		remote_status_changed.emit("Descarga incompleta. Se mantienen los escenarios locales.")

func _process_remote_level(parsed: Variant) -> void:
	if parsed is Dictionary and _is_valid_level(parsed):
		remote_levels.append(parsed)
	_request_next_remote_level()

func _finish_remote_collection() -> void:
	_request_mode = ""
	if remote_levels.is_empty():
		remote_status_changed.emit("No se recibieron escenarios válidos. Se mantienen los locales.")
		return
	remote_levels.sort_custom(_sort_by_order)
	levels = remote_levels.duplicate(true)
	_save_remote_cache(levels)
	levels_changed.emit(get_levels())
	remote_status_changed.emit("Escenarios remotos actualizados: %d" % levels.size())

func _load_local_collection() -> Array:
	var index_data := _read_json_dictionary(LOCAL_INDEX_PATH)
	var result: Array = []
	for entry in index_data.get("levels", []):
		var relative := str(entry).trim_prefix("./")
		var level_data := _read_json_dictionary("res://levels/" + relative)
		if _is_valid_level(level_data):
			result.append(level_data)
	result.sort_custom(_sort_by_order)
	return result

func _sort_by_order(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("order", 0)) < int(b.get("order", 0))

func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _is_valid_level(level: Dictionary) -> bool:
	return not str(level.get("id", "")).is_empty() and level.has("generator") and level.has("physics")

func _join_url(index_url: String, relative_path: String) -> String:
	if relative_path.begins_with("https://") or relative_path.begins_with("http://"):
		return relative_path
	return index_url.get_base_dir().trim_suffix("/") + "/" + relative_path.trim_prefix("./").trim_prefix("/")

func _save_remote_cache(collection: Array) -> void:
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"levels": collection}, "  "))
