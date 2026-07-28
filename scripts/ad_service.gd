extends Node

signal banner_visibility_changed(visible: bool)
signal interstitial_started
signal interstitial_finished

var mode := "mock"
var banner_visible := true
var interstitial_count := 0

func _ready() -> void:
	var config_path := "res://config/game_config.json"
	if FileAccess.file_exists(config_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(config_path))
		if parsed is Dictionary:
			mode = str(parsed.get("ads_mode", "mock"))

func show_banner() -> void:
	banner_visible = true
	banner_visibility_changed.emit(true)

func hide_banner() -> void:
	banner_visible = false
	banner_visibility_changed.emit(false)

func begin_interstitial() -> void:
	interstitial_count += 1
	interstitial_started.emit()

func finish_interstitial() -> void:
	interstitial_finished.emit()

func is_mock_mode() -> bool:
	return mode != "admob"
