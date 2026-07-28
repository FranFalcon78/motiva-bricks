extends Node2D

const LEVEL_FACTORY_SCRIPT: Script = preload("res://scripts/level_factory.gd")

# Motiva Bricks v0.1.2
# Motor de juego 2D propio, dibujado en un único CanvasItem para poder manejar
# cientos o miles de bloques sin crear un nodo por ladrillo.

enum ScreenState { MENU, PLAYING, PAUSED, INTERSTITIAL, RESULT }

const VIEW_SIZE := Vector2(720.0, 1280.0)
const PLAY_LEFT := 18.0
const PLAY_RIGHT := 702.0
const PLAY_TOP := 112.0
const PADDLE_Y := 1085.0
const PADDLE_HEIGHT := 22.0
const DEATH_Y := 1162.0
const SHIELD_Y := 1144.0
const BANNER_RECT := Rect2(18.0, 1192.0, 684.0, 72.0)
const MENU_CARD_X := 46.0
const MENU_CARD_Y := 207.0
const MENU_CARD_W := 628.0
const MENU_CARD_H := 146.0
const MENU_CARD_GAP := 12.0
const MAX_SPEED := 920.0
const MIN_SPEED := 470.0
const POWERUP_SPEED := 185.0

var state := ScreenState.MENU
var levels: Array = []
var previews: Array = []
var current_level_index := 0
var current_level: Dictionary = {}
var generated: Dictionary = {}
var bricks: Array = []
var grid_lookup: Dictionary = {}
var balls: Array = []
var powerups: Array = []
var particles: Array = []
var stars: Array = []
var sound_players: Array[AudioStreamPlayer] = []
var sound_cursor := 0
var sounds: Dictionary = {}

var score := 0
var coins := 0
var lives := 3
var remaining_bricks := 0
var destroyed_bricks := 0
var total_destructible := 0
var paddle_x := 360.0
var paddle_target_x := 360.0
var paddle_base_width := 156.0
var paddle_width := 156.0
var paddle_speed := 760.0
var max_bounce_angle := deg_to_rad(68.0)
var wide_timer := 0.0
var shield_timer := 0.0
var message_text := ""
var message_timer := 0.0
var level_elapsed := 0.0
var pending_win := false
var interstitial_timer := 0.0
var interstitial_duration := 2.8
var result_delay := 0.0
var pointer_active := false
var remote_status := "5 escenarios locales preparados"
var rng := RandomNumberGenerator.new()
var config: Dictionary = {}
var max_balls := 30
var best_scores: Dictionary = {}
var game_was_started := false
var ui_font: Font

func _ready() -> void:
	rng.randomize()
	ui_font = ThemeDB.fallback_font
	config = LevelRepository.get_config()
	max_balls = int(config.get("max_balls", 30))
	levels = LevelRepository.get_levels()
	LevelRepository.levels_changed.connect(_on_levels_changed)
	LevelRepository.remote_status_changed.connect(_on_remote_status_changed)
	_build_previews()
	_create_stars()
	_load_best_scores()
	_prepare_audio()
	AdService.show_banner()
	set_process(true)
	set_physics_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_update_particles(delta)
	for preview in previews:
		preview["pulse"] = fmod(float(preview.get("pulse", 0.0)) + delta, TAU)
	if state == ScreenState.INTERSTITIAL:
		interstitial_timer = maxf(0.0, interstitial_timer - delta)
		if interstitial_timer <= 0.0:
			AdService.finish_interstitial()
			state = ScreenState.RESULT
			_play_sound("result")
	if result_delay > 0.0:
		result_delay = maxf(0.0, result_delay - delta)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if state != ScreenState.PLAYING:
		return
	level_elapsed += delta
	_update_paddle(delta)
	_update_effect_timers(delta)
	_update_powerups(delta)
	_update_balls(delta)
	if message_timer > 0.0:
		message_timer = maxf(0.0, message_timer - delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_active = true
		paddle_target_x = event.position.x
	elif event is InputEventScreenDrag:
		pointer_active = true
		paddle_target_x = event.position.x
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_pointer_press(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_handle_pointer_press(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)

func _handle_key(event: InputEventKey) -> void:
	if state == ScreenState.MENU:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			var index := int(event.keycode - KEY_1)
			if index < levels.size():
				_start_level(index)
		elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_start_level(0)
	elif state == ScreenState.PLAYING:
		if event.keycode == KEY_SPACE:
			_launch_stuck_balls()
		elif event.keycode == KEY_P or event.keycode == KEY_ESCAPE:
			state = ScreenState.PAUSED
	elif state == ScreenState.PAUSED:
		if event.keycode == KEY_P or event.keycode == KEY_SPACE:
			state = ScreenState.PLAYING
		elif event.keycode == KEY_ESCAPE:
			_return_to_menu()
	elif state == ScreenState.RESULT:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_start_level(current_level_index)
		elif event.keycode == KEY_ESCAPE:
			_return_to_menu()
	elif state == ScreenState.INTERSTITIAL and event.keycode == KEY_ESCAPE and interstitial_timer <= 1.0:
		interstitial_timer = 0.0

func _handle_pointer_press(position: Vector2) -> void:
	match state:
		ScreenState.MENU:
			for index in range(levels.size()):
				if _menu_card_rect(index).has_point(position):
					_start_level(index)
					return
			var refresh_rect := Rect2(466.0, 146.0, 208.0, 42.0)
			if refresh_rect.has_point(position):
				LevelRepository.refresh_remote_levels()
		ScreenState.PLAYING:
			paddle_target_x = position.x
			pointer_active = true
			if position.y < 104.0:
				state = ScreenState.PAUSED
			else:
				_launch_stuck_balls()
		ScreenState.PAUSED:
			if Rect2(170.0, 536.0, 380.0, 72.0).has_point(position):
				state = ScreenState.PLAYING
			elif Rect2(170.0, 626.0, 380.0, 72.0).has_point(position):
				_return_to_menu()
		ScreenState.INTERSTITIAL:
			if interstitial_timer <= 1.0 and Rect2(235.0, 790.0, 250.0, 58.0).has_point(position):
				interstitial_timer = 0.0
		ScreenState.RESULT:
			if Rect2(100.0, 775.0, 520.0, 76.0).has_point(position):
				_start_level(current_level_index)
			elif Rect2(100.0, 871.0, 520.0, 68.0).has_point(position):
				_return_to_menu()

func _on_levels_changed(new_levels: Array) -> void:
	levels = new_levels
	_build_previews()
	queue_redraw()

func _on_remote_status_changed(status: String) -> void:
	remote_status = status
	message_text = status
	message_timer = 3.0
	queue_redraw()

func _build_previews() -> void:
	previews.clear()
	for level in levels:
		var preview_generated: Dictionary = LEVEL_FACTORY_SCRIPT.generate(level, 720.0)
		previews.append({
			"generated": preview_generated,
			"pulse": rng.randf_range(0.0, TAU)
		})

func _create_stars() -> void:
	stars.clear()
	var star_rng := RandomNumberGenerator.new()
	star_rng.seed = 20260728
	for _index in range(82):
		stars.append({
			"pos": Vector2(star_rng.randf_range(10.0, 710.0), star_rng.randf_range(8.0, 1180.0)),
			"size": star_rng.randf_range(0.7, 2.2),
			"alpha": star_rng.randf_range(0.16, 0.72)
		})

func _start_level(index: int) -> void:
	if levels.is_empty():
		return
	current_level_index = clampi(index, 0, levels.size() - 1)
	current_level = levels[current_level_index].duplicate(true)
	generated = LEVEL_FACTORY_SCRIPT.generate(current_level, 720.0)
	bricks = generated.get("bricks", []).duplicate(true)
	grid_lookup.clear()
	var cols := int(generated.get("columns", 1))
	for brick_index in range(bricks.size()):
		var brick: Dictionary = bricks[brick_index]
		grid_lookup[int(brick.get("grid_y", 0)) * cols + int(brick.get("grid_x", 0))] = brick_index
	total_destructible = int(generated.get("destructible_count", 0))
	remaining_bricks = total_destructible
	destroyed_bricks = 0
	score = 0
	coins = 0
	lives = int(current_level.get("rules", {}).get("lives", 3))
	level_elapsed = 0.0
	wide_timer = 0.0
	shield_timer = 0.0
	paddle_base_width = float(current_level.get("physics", {}).get("paddleWidth", 156.0))
	paddle_width = paddle_base_width
	max_bounce_angle = deg_to_rad(float(current_level.get("physics", {}).get("maxBounceAngleDeg", 68.0)))
	paddle_x = 360.0
	paddle_target_x = 360.0
	balls.clear()
	powerups.clear()
	particles.clear()
	_spawn_stuck_ball()
	message_text = "TOCA O PULSA ESPACIO PARA LANZAR"
	message_timer = 5.0
	pending_win = false
	game_was_started = true
	state = ScreenState.PLAYING
	_play_sound("start")
	queue_redraw()

func _return_to_menu() -> void:
	state = ScreenState.MENU
	balls.clear()
	powerups.clear()
	particles.clear()
	message_timer = 0.0
	queue_redraw()

func _spawn_stuck_ball() -> void:
	var physics: Dictionary = current_level.get("physics", {})
	var radius := float(physics.get("ballRadius", 8.0))
	balls.append({
		"pos": Vector2(paddle_x, PADDLE_Y - radius - 6.0),
		"vel": Vector2.ZERO,
		"radius": radius,
		"stuck": true,
		"trail": [],
		"last_brick": -1,
		"hit_cooldown": 0.0
	})

func _launch_stuck_balls() -> void:
	if state != ScreenState.PLAYING:
		return
	var base_speed := _configured_ball_speed()
	var launched := false
	for ball in balls:
		if bool(ball.get("stuck", false)):
			var direction_x := rng.randf_range(-0.46, 0.46)
			ball["vel"] = Vector2(direction_x, -1.0).normalized() * base_speed
			ball["stuck"] = false
			launched = true
	if launched:
		message_timer = 0.0
		_play_sound("launch")

func _configured_ball_speed() -> float:
	var raw := float(current_level.get("physics", {}).get("ballSpeed", 8.5))
	# Los niveles heredados usan una escala de 8-10; en Godot se expresa en px/s.
	return clampf(raw * 68.0, MIN_SPEED, 760.0)

func _update_paddle(delta: float) -> void:
	var keyboard_axis := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		keyboard_axis -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		keyboard_axis += 1.0
	if absf(keyboard_axis) > 0.05:
		pointer_active = false
		paddle_x += keyboard_axis * paddle_speed * delta
	elif pointer_active:
		paddle_x = move_toward(paddle_x, paddle_target_x, paddle_speed * 1.45 * delta)
	var half_width := paddle_width * 0.5
	paddle_x = clampf(paddle_x, PLAY_LEFT + half_width, PLAY_RIGHT - half_width)
	for ball in balls:
		if bool(ball.get("stuck", false)):
			ball["pos"] = Vector2(paddle_x, PADDLE_Y - float(ball.get("radius", 8.0)) - 6.0)

func _update_effect_timers(delta: float) -> void:
	if wide_timer > 0.0:
		wide_timer = maxf(0.0, wide_timer - delta)
		if wide_timer <= 0.0:
			paddle_width = paddle_base_width
	if shield_timer > 0.0:
		shield_timer = maxf(0.0, shield_timer - delta)

func _update_balls(delta: float) -> void:
	if balls.is_empty():
		_lose_life()
		return
	var max_speed_seen := _configured_ball_speed()
	var min_radius := 8.0
	for ball in balls:
		max_speed_seen = maxf(max_speed_seen, Vector2(ball.get("vel", Vector2.ZERO)).length())
		min_radius = minf(min_radius, float(ball.get("radius", 8.0)))
	var substeps := clampi(int(ceil(max_speed_seen * delta / maxf(3.0, min_radius * 0.7))), 1, 10)
	var step_delta := delta / float(substeps)
	for _step in range(substeps):
		for ball_index in range(balls.size() - 1, -1, -1):
			var ball: Dictionary = balls[ball_index]
			if bool(ball.get("stuck", false)):
				continue
			ball["hit_cooldown"] = maxf(0.0, float(ball.get("hit_cooldown", 0.0)) - step_delta)
			if not _advance_ball(ball, step_delta):
				balls.remove_at(ball_index)
		if state != ScreenState.PLAYING:
			return
	_update_ball_trails(delta)
	if balls.is_empty() and state == ScreenState.PLAYING:
		_lose_life()

func _advance_ball(ball: Dictionary, delta: float) -> bool:
	var position: Vector2 = ball.get("pos", Vector2.ZERO)
	var velocity: Vector2 = ball.get("vel", Vector2.ZERO)
	var radius := float(ball.get("radius", 8.0))
	position += velocity * delta

	if position.x - radius < PLAY_LEFT:
		position.x = PLAY_LEFT + radius
		velocity.x = absf(velocity.x)
		_play_sound("wall", 0.34)
	elif position.x + radius > PLAY_RIGHT:
		position.x = PLAY_RIGHT - radius
		velocity.x = -absf(velocity.x)
		_play_sound("wall", 0.34)
	if position.y - radius < PLAY_TOP:
		position.y = PLAY_TOP + radius
		velocity.y = absf(velocity.y)
		_play_sound("wall", 0.34)

	if shield_timer > 0.0 and velocity.y > 0.0 and position.y + radius >= SHIELD_Y and position.y < SHIELD_Y + 16.0:
		position.y = SHIELD_Y - radius
		velocity.y = -absf(velocity.y)
		_spawn_sparks(position, Color("28dfff"), 5)
		_play_sound("shield")

	var paddle_rect := Rect2(paddle_x - paddle_width * 0.5, PADDLE_Y, paddle_width, PADDLE_HEIGHT)
	if velocity.y > 0.0 and _circle_intersects_rect(position, radius, paddle_rect):
		var relative := clampf((position.x - paddle_x) / maxf(1.0, paddle_width * 0.5), -1.0, 1.0)
		var angle := relative * max_bounce_angle
		var speed := clampf(velocity.length() * 1.004, MIN_SPEED, MAX_SPEED)
		velocity = Vector2(sin(angle), -cos(angle)) * speed
		position.y = PADDLE_Y - radius - 0.5
		_spawn_sparks(Vector2(position.x, PADDLE_Y), _theme_color("accent", Color("ff4f87")), 5)
		_play_sound("paddle")

	ball["pos"] = position
	ball["vel"] = velocity
	_check_brick_collision(ball)
	position = ball.get("pos", position)
	if position.y - radius > DEATH_Y:
		return false
	return true

func _check_brick_collision(ball: Dictionary) -> void:
	if bricks.is_empty() or float(ball.get("hit_cooldown", 0.0)) > 0.0:
		return
	var position: Vector2 = ball.get("pos", Vector2.ZERO)
	var radius := float(ball.get("radius", 8.0))
	var area: Rect2 = generated.get("area", Rect2())
	var cell_width := float(generated.get("cell_width", 12.0))
	var cell_height := float(generated.get("cell_height", 12.0))
	var start_y := float(generated.get("start_y", area.position.y))
	var cols := int(generated.get("columns", 1))
	var rows := int(generated.get("rows", 1))
	var center_col := int(floor((position.x - area.position.x) / cell_width))
	var center_row := int(floor((position.y - start_y) / cell_height))
	for grid_y in range(center_row - 1, center_row + 2):
		if grid_y < 0 or grid_y >= rows:
			continue
		for grid_x in range(center_col - 1, center_col + 2):
			if grid_x < 0 or grid_x >= cols:
				continue
			var key := grid_y * cols + grid_x
			if not grid_lookup.has(key):
				continue
			var brick_index := int(grid_lookup[key])
			var brick: Dictionary = bricks[brick_index]
			if not bool(brick.get("alive", false)):
				continue
			var rect: Rect2 = brick.get("rect", Rect2())
			if not _circle_intersects_rect(position, radius, rect):
				continue
			_resolve_brick_hit(ball, brick, brick_index)
			return

func _resolve_brick_hit(ball: Dictionary, brick: Dictionary, brick_index: int) -> void:
	var position: Vector2 = ball.get("pos", Vector2.ZERO)
	var radius := float(ball.get("radius", 8.0))
	var rect: Rect2 = brick.get("rect", Rect2())
	var normal := _collision_normal(position, radius, rect, Vector2(ball.get("vel", Vector2.UP)))
	var velocity: Vector2 = ball.get("vel", Vector2.UP)
	velocity = velocity.bounce(normal)
	if velocity.length() < MIN_SPEED:
		velocity = velocity.normalized() * MIN_SPEED
	ball["vel"] = velocity
	ball["pos"] = position + normal * 1.25
	ball["last_brick"] = brick_index
	ball["hit_cooldown"] = 0.012
	brick["flash"] = 0.14

	if bool(brick.get("indestructible", false)):
		_spawn_sparks(position, Color(brick.get("color", Color.GRAY)), 3)
		_play_sound("metal", 0.60)
		return

	brick["hp"] = int(brick.get("hp", 1)) - 1
	if int(brick["hp"]) <= 0:
		brick["alive"] = false
		remaining_bricks = maxi(0, remaining_bricks - 1)
		destroyed_bricks += 1
		score += 90 + int(brick.get("max_hp", 1)) * 35 + balls.size() * 4
		var center := rect.get_center()
		_spawn_burst(center, Color(brick.get("color", Color.WHITE)), 8)
		_try_drop_powerup(center)
		_play_sound("break")
		if remaining_bricks <= 0:
			_finish_game(true)
	else:
		score += 20
		_spawn_sparks(position, Color(brick.get("color", Color.WHITE)), 4)
		_play_sound("brick")

func _collision_normal(center: Vector2, radius: float, rect: Rect2, velocity: Vector2) -> Vector2:
	var closest := Vector2(
		clampf(center.x, rect.position.x, rect.end.x),
		clampf(center.y, rect.position.y, rect.end.y)
	)
	var difference := center - closest
	if difference.length_squared() > 0.0001:
		return difference.normalized()
	var left_penetration := absf((center.x + radius) - rect.position.x)
	var right_penetration := absf(rect.end.x - (center.x - radius))
	var top_penetration := absf((center.y + radius) - rect.position.y)
	var bottom_penetration := absf(rect.end.y - (center.y - radius))
	var minimum := minf(minf(left_penetration, right_penetration), minf(top_penetration, bottom_penetration))
	if minimum == left_penetration:
		return Vector2.LEFT
	if minimum == right_penetration:
		return Vector2.RIGHT
	if minimum == top_penetration:
		return Vector2.UP
	if minimum == bottom_penetration:
		return Vector2.DOWN
	return -velocity.normalized()

func _circle_intersects_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest_x := clampf(center.x, rect.position.x, rect.end.x)
	var closest_y := clampf(center.y, rect.position.y, rect.end.y)
	var dx := center.x - closest_x
	var dy := center.y - closest_y
	return dx * dx + dy * dy <= radius * radius

func _lose_life() -> void:
	if state != ScreenState.PLAYING:
		return
	lives -= 1
	wide_timer = 0.0
	paddle_width = paddle_base_width
	if lives <= 0:
		_finish_game(false)
		return
	_spawn_stuck_ball()
	message_text = "BOLA PERDIDA · QUEDAN %d VIDAS" % lives
	message_timer = 2.6
	_play_sound("life")

func _finish_game(win: bool) -> void:
	if state != ScreenState.PLAYING:
		return
	pending_win = win
	var time_bonus := maxi(0, int(6000.0 - level_elapsed * 18.0)) if win else 0
	score += time_bonus + coins * 75
	_save_best_score()
	state = ScreenState.INTERSTITIAL
	interstitial_timer = interstitial_duration
	AdService.begin_interstitial()
	_play_sound("win" if win else "lose")

func _try_drop_powerup(position: Vector2) -> void:
	var powerup_data: Dictionary = current_level.get("powerups", {})
	var drop_rate := float(powerup_data.get("dropRate", 0.12))
	if rng.randf() > drop_rate:
		return
	var weights: Dictionary = powerup_data.get("weights", {"triple": 0.34, "wide": 0.33, "shield": 0.33})
	var roll := rng.randf()
	var triple_weight := float(weights.get("triple", 0.34))
	var wide_weight := float(weights.get("wide", 0.33))
	var power_type := "shield"
	if roll < triple_weight:
		power_type = "triple"
	elif roll < triple_weight + wide_weight:
		power_type = "wide"
	powerups.append({
		"pos": position,
		"type": power_type,
		"rotation": rng.randf_range(-0.4, 0.4),
		"pulse": rng.randf_range(0.0, TAU),
		"radius": 17.0
	})

func _update_powerups(delta: float) -> void:
	var paddle_rect := Rect2(paddle_x - paddle_width * 0.5, PADDLE_Y - 4.0, paddle_width, PADDLE_HEIGHT + 8.0)
	for index in range(powerups.size() - 1, -1, -1):
		var powerup: Dictionary = powerups[index]
		powerup["pos"] = Vector2(powerup.get("pos", Vector2.ZERO)) + Vector2(0.0, POWERUP_SPEED * delta)
		powerup["rotation"] = float(powerup.get("rotation", 0.0)) + delta * 2.1
		powerup["pulse"] = float(powerup.get("pulse", 0.0)) + delta * 4.0
		var position: Vector2 = powerup.get("pos", Vector2.ZERO)
		if _circle_intersects_rect(position, float(powerup.get("radius", 17.0)), paddle_rect):
			_apply_powerup(str(powerup.get("type", "wide")))
			powerups.remove_at(index)
		elif position.y > DEATH_Y + 40.0:
			powerups.remove_at(index)

func _apply_powerup(power_type: String) -> void:
	coins += 1
	score += 250
	match power_type:
		"triple":
			_triple_balls()
			message_text = "MONEDA ×3 · BOLAS MULTIPLICADAS"
		"wide":
			var data: Dictionary = current_level.get("powerups", {})
			wide_timer = float(data.get("wideSeconds", 15.0))
			paddle_width = minf(300.0, paddle_base_width * float(data.get("wideMultiplier", 1.65)))
			message_text = "MONEDA W · CARRO AMPLIADO"
		"shield":
			shield_timer = float(current_level.get("powerups", {}).get("shieldSeconds", 12.0))
			message_text = "MONEDA S · FOSO CERRADO"
	message_timer = 2.4
	_spawn_burst(Vector2(paddle_x, PADDLE_Y), _powerup_color(power_type), 15)
	_play_sound("power")

func _triple_balls() -> void:
	var originals := balls.duplicate(true)
	for source in originals:
		if balls.size() >= max_balls:
			break
		var source_velocity: Vector2 = source.get("vel", Vector2(0.0, -_configured_ball_speed()))
		if bool(source.get("stuck", false)):
			source_velocity = Vector2(0.0, -_configured_ball_speed())
		for angle_degrees in [-22.0, 22.0]:
			if balls.size() >= max_balls:
				break
			var copy: Dictionary = source.duplicate(true)
			copy["stuck"] = false
			copy["vel"] = source_velocity.rotated(deg_to_rad(angle_degrees))
			copy["trail"] = []
			copy["hit_cooldown"] = 0.03
			balls.append(copy)

func _update_ball_trails(delta: float) -> void:
	for ball in balls:
		var trail: Array = ball.get("trail", [])
		trail.push_front({"pos": ball.get("pos", Vector2.ZERO), "life": 0.22})
		for item in trail:
			item["life"] = float(item.get("life", 0.0)) - delta
		while not trail.is_empty() and (trail.size() > 7 or float(trail.back().get("life", 0.0)) <= 0.0):
			trail.pop_back()
		ball["trail"] = trail

func _spawn_burst(position: Vector2, color: Color, amount: int) -> void:
	for _index in range(amount):
		var angle := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(55.0, 215.0)
		particles.append({
			"pos": position,
			"vel": Vector2.from_angle(angle) * speed,
			"life": rng.randf_range(0.22, 0.55),
			"max_life": 0.55,
			"color": color,
			"size": rng.randf_range(1.5, 4.5)
		})

func _spawn_sparks(position: Vector2, color: Color, amount: int) -> void:
	_spawn_burst(position, color, amount)

func _update_particles(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[index]
		particle["life"] = float(particle.get("life", 0.0)) - delta
		if float(particle["life"]) <= 0.0:
			particles.remove_at(index)
			continue
		particle["pos"] = Vector2(particle.get("pos", Vector2.ZERO)) + Vector2(particle.get("vel", Vector2.ZERO)) * delta
		particle["vel"] = Vector2(particle.get("vel", Vector2.ZERO)) * pow(0.08, delta) + Vector2(0.0, 90.0 * delta)

func _prepare_audio() -> void:
	for _index in range(8):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		sound_players.append(player)
	var paths := {
		"start": "res://assets/start.wav",
		"launch": "res://assets/launch.wav",
		"wall": "res://assets/wall.wav",
		"paddle": "res://assets/paddle.wav",
		"brick": "res://assets/brick.wav",
		"break": "res://assets/break.wav",
		"metal": "res://assets/metal.wav",
		"shield": "res://assets/shield.wav",
		"power": "res://assets/power.wav",
		"life": "res://assets/life.wav",
		"win": "res://assets/win.wav",
		"lose": "res://assets/lose.wav",
		"result": "res://assets/result.wav"
	}
	for key in paths:
		if ResourceLoader.exists(paths[key]):
			sounds[key] = load(paths[key])

func _play_sound(key: String, volume: float = 1.0) -> void:
	if not sounds.has(key) or sound_players.is_empty():
		return
	var player := sound_players[sound_cursor % sound_players.size()]
	sound_cursor += 1
	player.stream = sounds[key]
	player.volume_db = linear_to_db(clampf(volume, 0.01, 1.0))
	player.pitch_scale = rng.randf_range(0.96, 1.04)
	player.play()

func _load_best_scores() -> void:
	var save := ConfigFile.new()
	if save.load("user://motiva_bricks_scores.cfg") != OK:
		return
	for level in levels:
		var id := str(level.get("id", ""))
		best_scores[id] = int(save.get_value("scores", id, 0))

func _save_best_score() -> void:
	var id := str(current_level.get("id", ""))
	var previous := int(best_scores.get(id, 0))
	if score <= previous:
		return
	best_scores[id] = score
	var save := ConfigFile.new()
	for key in best_scores:
		save.set_value("scores", str(key), int(best_scores[key]))
	save.save("user://motiva_bricks_scores.cfg")

func _theme_color(key: String, fallback: Color) -> Color:
	var theme: Dictionary = current_level.get("theme", {})
	return Color.from_string(str(theme.get(key, fallback.to_html())), fallback)

func _powerup_color(power_type: String) -> Color:
	match power_type:
		"triple":
			return Color("ff4f87")
		"wide":
			return Color("ffe75b")
		_:
			return Color("28dfff")

func _menu_card_rect(index: int) -> Rect2:
	return Rect2(MENU_CARD_X, MENU_CARD_Y + float(index) * (MENU_CARD_H + MENU_CARD_GAP), MENU_CARD_W, MENU_CARD_H)

func _draw() -> void:
	_draw_background()
	match state:
		ScreenState.MENU:
			_draw_menu()
		ScreenState.PLAYING, ScreenState.PAUSED:
			_draw_game()
			if state == ScreenState.PAUSED:
				_draw_pause_overlay()
		ScreenState.INTERSTITIAL:
			_draw_game()
			_draw_interstitial()
		ScreenState.RESULT:
			_draw_result()
	_draw_particles()

func _draw_background() -> void:
	var top := Color("26004f")
	var bottom := Color("070012")
	if not current_level.is_empty() and state != ScreenState.MENU:
		top = _theme_color("backgroundTop", top)
		bottom = _theme_color("backgroundBottom", bottom)
	for index in range(32):
		var ratio := float(index) / 31.0
		var color := top.lerp(bottom, ratio)
		draw_rect(Rect2(0.0, ratio * VIEW_SIZE.y, VIEW_SIZE.x, VIEW_SIZE.y / 31.0 + 2.0), color)
	for star in stars:
		var alpha := float(star.get("alpha", 0.3))
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.0014 + Vector2(star.get("pos", Vector2.ZERO)).x)
		draw_circle(star.get("pos", Vector2.ZERO), float(star.get("size", 1.0)), Color(1.0, 1.0, 1.0, alpha * pulse))

func _draw_menu() -> void:
	_draw_text("MOTIVA", Vector2(0.0, 72.0), 25, Color("ffb6de"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_text("BRICKS", Vector2(0.0, 132.0), 58, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_text("ROMPE · MULTIPLICA · EXCAVA", Vector2(0.0, 167.0), 17, Color("d8c9ff"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_text(remote_status, Vector2(48.0, 191.0), 13, Color("b9adcf"))
	_draw_button(Rect2(466.0, 146.0, 208.0, 42.0), "ACTUALIZAR NIVELES", Color("3d1b64"), 13)

	for index in range(mini(levels.size(), 5)):
		_draw_level_card(index)

	var help_y := 1055.0
	_draw_text("Ratón o táctil: mueve el carro · Espacio: lanza · P/Esc: pausa", Vector2(0.0, help_y), 14, Color("c9bddb"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_text("Versión 0.1.0 · 5 escenarios JSON · preparada para Android", Vector2(0.0, help_y + 28.0), 13, Color("8e80a9"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_ad_banner()

func _draw_level_card(index: int) -> void:
	var level: Dictionary = levels[index]
	var rect := _menu_card_rect(index)
	var theme: Dictionary = level.get("theme", {})
	var accent := Color.from_string(str(theme.get("accent", "#ff4f87")), Color("ff4f87"))
	_draw_panel(rect, Color(0.075, 0.035, 0.14, 0.94), accent.darkened(0.25), 2.0)
	var preview_rect := Rect2(rect.position + Vector2(14.0, 14.0), Vector2(178.0, rect.size.y - 28.0))
	draw_rect(preview_rect, Color(0.02, 0.01, 0.06, 0.92), true)
	_draw_preview(index, preview_rect.grow(-5.0))
	var text_x := rect.position.x + 210.0
	_draw_text("ESCENARIO %02d" % (index + 1), Vector2(text_x, rect.position.y + 31.0), 13, accent)
	_draw_text(str(level.get("name", "Escenario")), Vector2(text_x, rect.position.y + 66.0), 25, Color.WHITE)
	_draw_text(str(level.get("subtitle", "")), Vector2(text_x, rect.position.y + 91.0), 13, Color("c8bcd8"))
	var generated_preview: Dictionary = previews[index].get("generated", {})
	var count := int(generated_preview.get("total_count", 0))
	var best := int(best_scores.get(str(level.get("id", "")), 0))
	_draw_text("%d bloques · récord %s" % [count, _format_number(best)], Vector2(text_x, rect.position.y + 119.0), 13, Color("968aa9"))
	draw_circle(Vector2(rect.end.x - 37.0, rect.get_center().y), 22.0, accent)
	draw_colored_polygon(PackedVector2Array([
		Vector2(rect.end.x - 43.0, rect.get_center().y - 10.0),
		Vector2(rect.end.x - 43.0, rect.get_center().y + 10.0),
		Vector2(rect.end.x - 28.0, rect.get_center().y)
	]), Color.WHITE)

func _draw_preview(index: int, rect: Rect2) -> void:
	if index >= previews.size():
		return
	var preview_data: Dictionary = previews[index].get("generated", {})
	var preview_bricks: Array = preview_data.get("bricks", [])
	var source_area: Rect2 = preview_data.get("area", Rect2(20.0, 150.0, 680.0, 620.0))
	var scale_x := rect.size.x / source_area.size.x
	var scale_y := rect.size.y / source_area.size.y
	var step := maxi(1, int(ceil(float(preview_bricks.size()) / 235.0)))
	for brick_index in range(0, preview_bricks.size(), step):
		var brick: Dictionary = preview_bricks[brick_index]
		var source_rect: Rect2 = brick.get("rect", Rect2())
		var preview_position := Vector2(
			rect.position.x + (source_rect.position.x - source_area.position.x) * scale_x,
			rect.position.y + (source_rect.position.y - source_area.position.y) * scale_y
		)
		var preview_size := Vector2(maxf(1.0, source_rect.size.x * scale_x), maxf(1.0, source_rect.size.y * scale_y))
		var color: Color = brick.get("color", Color.WHITE)
		if bool(brick.get("indestructible", false)):
			color = color.darkened(0.05)
		draw_rect(Rect2(preview_position, preview_size), color, true)

func _draw_game() -> void:
	_draw_hud()
	_draw_playfield_frame()
	_draw_bricks()
	_draw_powerups()
	_draw_shield()
	_draw_paddle()
	_draw_balls()
	if message_timer > 0.0:
		var box := Rect2(105.0, 942.0, 510.0, 54.0)
		_draw_panel(box, Color(0.035, 0.01, 0.09, 0.88), _theme_color("accent", Color("ff4f87")), 1.0)
		_draw_text(message_text, Vector2(box.position.x, box.position.y + 34.0), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	_draw_ad_banner()

func _draw_hud() -> void:
	draw_rect(Rect2(0.0, 0.0, 720.0, 104.0), Color(0.015, 0.005, 0.04, 0.88), true)
	_draw_text("MOTIVA BRICKS", Vector2(22.0, 36.0), 19, Color.WHITE)
	_draw_text("%02d · %s" % [current_level_index + 1, str(current_level.get("name", ""))], Vector2(22.0, 67.0), 14, _theme_color("accent", Color("ff4f87")))
	_draw_text("PUNTOS", Vector2(238.0, 27.0), 11, Color("9286a5"), HORIZONTAL_ALIGNMENT_CENTER, 132.0)
	_draw_text(_format_number(score), Vector2(238.0, 60.0), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 132.0)
	_draw_text("BLOQUES", Vector2(376.0, 27.0), 11, Color("9286a5"), HORIZONTAL_ALIGNMENT_CENTER, 126.0)
	_draw_text("%d/%d" % [destroyed_bricks, total_destructible], Vector2(376.0, 59.0), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 126.0)
	_draw_text("VIDAS", Vector2(514.0, 27.0), 11, Color("9286a5"), HORIZONTAL_ALIGNMENT_CENTER, 82.0)
	_draw_text("●".repeat(maxi(0, lives)), Vector2(514.0, 59.0), 19, Color("ff4f87"), HORIZONTAL_ALIGNMENT_CENTER, 82.0)
	_draw_button(Rect2(611.0, 20.0, 84.0, 62.0), "Ⅱ", Color("2c164a"), 25)

func _draw_playfield_frame() -> void:
	var frame := Rect2(PLAY_LEFT - 4.0, PLAY_TOP - 4.0, PLAY_RIGHT - PLAY_LEFT + 8.0, DEATH_Y - PLAY_TOP + 7.0)
	draw_rect(frame, Color(0.01, 0.003, 0.025, 0.28), true)
	draw_line(Vector2(PLAY_LEFT, PLAY_TOP), Vector2(PLAY_LEFT, DEATH_Y), Color(0.55, 0.34, 0.85, 0.45), 2.0)
	draw_line(Vector2(PLAY_RIGHT, PLAY_TOP), Vector2(PLAY_RIGHT, DEATH_Y), Color(0.55, 0.34, 0.85, 0.45), 2.0)

func _draw_bricks() -> void:
	for brick in bricks:
		if not bool(brick.get("alive", false)):
			continue
		var rect: Rect2 = brick.get("rect", Rect2())
		var color: Color = brick.get("color", Color.WHITE)
		var hp := int(brick.get("hp", 1))
		var max_hp := int(brick.get("max_hp", 1))
		if max_hp > 1:
			color = color.darkened(float(max_hp - hp) * 0.13)
		if float(brick.get("flash", 0.0)) > 0.0:
			color = color.lightened(0.32)
			brick["flash"] = maxf(0.0, float(brick.get("flash", 0.0)) - 0.016)
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.40), true)
		draw_rect(Rect2(rect.position + Vector2(0.7, 0.7), rect.size - Vector2(1.4, 1.4)), color, true)
		if bool(brick.get("indestructible", false)):
			draw_line(rect.position + Vector2(2.0, 2.0), rect.end - Vector2(2.0, 2.0), Color(1.0, 1.0, 1.0, 0.34), 1.0)
		elif hp >= 2 and rect.size.x >= 7.0:
			draw_circle(rect.get_center(), minf(2.0, rect.size.y * 0.18), Color(1.0, 1.0, 1.0, 0.52))

func _draw_paddle() -> void:
	var rect := Rect2(paddle_x - paddle_width * 0.5, PADDLE_Y, paddle_width, PADDLE_HEIGHT)
	var start_color := _theme_color("paddleStart", Color("ff4f87"))
	var middle_color := _theme_color("paddleMiddle", Color("ffe75b"))
	var end_color := _theme_color("paddleEnd", Color("28dfff"))
	for index in range(18):
		var ratio := float(index) / 17.0
		var color := start_color.lerp(middle_color, ratio * 2.0) if ratio < 0.5 else middle_color.lerp(end_color, (ratio - 0.5) * 2.0)
		var segment_width := rect.size.x / 18.0 + 1.0
		draw_rect(Rect2(rect.position.x + float(index) * rect.size.x / 18.0, rect.position.y, segment_width, rect.size.y), color, true)
	draw_line(rect.position + Vector2(4.0, 3.0), Vector2(rect.end.x - 4.0, rect.position.y + 3.0), Color(1.0, 1.0, 1.0, 0.65), 2.0)
	draw_circle(Vector2(rect.position.x, rect.get_center().y), rect.size.y * 0.5, start_color)
	draw_circle(Vector2(rect.end.x, rect.get_center().y), rect.size.y * 0.5, end_color)
	if wide_timer > 0.0:
		_draw_text("W %.0f" % ceil(wide_timer), Vector2(rect.position.x, rect.position.y - 10.0), 11, Color("ffe75b"), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _draw_balls() -> void:
	var ball_color := _theme_color("ball", Color.WHITE)
	var glow_color := _theme_color("ballGlow", Color("ffe9ff"))
	for ball in balls:
		var trail: Array = ball.get("trail", [])
		for index in range(trail.size() - 1, -1, -1):
			var item: Dictionary = trail[index]
			var alpha := clampf(float(item.get("life", 0.0)) / 0.22, 0.0, 1.0) * 0.22
			draw_circle(item.get("pos", Vector2.ZERO), float(ball.get("radius", 8.0)) * (0.35 + alpha), Color(glow_color, alpha))
		var position: Vector2 = ball.get("pos", Vector2.ZERO)
		var radius := float(ball.get("radius", 8.0))
		draw_circle(position, radius * 2.1, Color(glow_color, 0.09))
		draw_circle(position, radius * 1.45, Color(glow_color, 0.18))
		draw_circle(position, radius, ball_color)
		draw_circle(position + Vector2(-radius * 0.28, -radius * 0.32), radius * 0.23, Color(1.0, 1.0, 1.0, 0.95))

func _draw_powerups() -> void:
	for powerup in powerups:
		var position: Vector2 = powerup.get("pos", Vector2.ZERO)
		var power_type := str(powerup.get("type", "wide"))
		var color := _powerup_color(power_type)
		var pulse := 1.0 + sin(float(powerup.get("pulse", 0.0))) * 0.08
		draw_circle(position, 23.0 * pulse, Color(color, 0.12))
		draw_circle(position, 17.0 * pulse, color)
		draw_arc(position, 13.0 * pulse, 0.0, TAU, 24, Color.WHITE, 2.0)
		var label := "×3" if power_type == "triple" else ("W" if power_type == "wide" else "S")
		_draw_text(label, Vector2(position.x - 22.0, position.y + 6.0), 14, Color("160024"), HORIZONTAL_ALIGNMENT_CENTER, 44.0)

func _draw_shield() -> void:
	if shield_timer <= 0.0:
		return
	var color := Color("28dfff")
	draw_line(Vector2(PLAY_LEFT + 4.0, SHIELD_Y), Vector2(PLAY_RIGHT - 4.0, SHIELD_Y), Color(color, 0.18), 10.0)
	draw_line(Vector2(PLAY_LEFT + 4.0, SHIELD_Y), Vector2(PLAY_RIGHT - 4.0, SHIELD_Y), Color(color, 0.78), 3.0)
	_draw_text("FOSO CERRADO %.0fs" % ceil(shield_timer), Vector2(0.0, SHIELD_Y - 11.0), 12, color, HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)

func _draw_ad_banner() -> void:
	if not AdService.banner_visible:
		return
	_draw_panel(BANNER_RECT, Color(0.07, 0.055, 0.095, 0.96), Color(0.35, 0.30, 0.43, 0.75), 1.0)
	_draw_text("ESPACIO RESERVADO PARA BANNER ADMOB", Vector2(BANNER_RECT.position.x, BANNER_RECT.position.y + 31.0), 15, Color("ddd7e7"), HORIZONTAL_ALIGNMENT_CENTER, BANNER_RECT.size.x)
	_draw_text("anuncio de prueba · sin identificadores reales", Vector2(BANNER_RECT.position.x, BANNER_RECT.position.y + 52.0), 11, Color("8f879a"), HORIZONTAL_ALIGNMENT_CENTER, BANNER_RECT.size.x)

func _draw_pause_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0.01, 0.0, 0.03, 0.76), true)
	_draw_panel(Rect2(95.0, 382.0, 530.0, 380.0), Color(0.055, 0.018, 0.105, 0.98), _theme_color("accent", Color("ff4f87")), 2.0)
	_draw_text("PARTIDA EN PAUSA", Vector2(95.0, 460.0), 35, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 530.0)
	_draw_text("Los temporizadores también están detenidos", Vector2(95.0, 502.0), 15, Color("bfb2d1"), HORIZONTAL_ALIGNMENT_CENTER, 530.0)
	_draw_button(Rect2(170.0, 536.0, 380.0, 72.0), "CONTINUAR", _theme_color("accent", Color("ff4f87")), 20)
	_draw_button(Rect2(170.0, 626.0, 380.0, 72.0), "VOLVER A ESCENARIOS", Color("302044"), 17)

func _draw_interstitial() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0.01, 0.0, 0.025, 0.90), true)
	_draw_panel(Rect2(72.0, 255.0, 576.0, 650.0), Color(0.075, 0.045, 0.095, 0.99), Color("8b7c99"), 2.0)
	_draw_text("ANUNCIO DE PRUEBA", Vector2(72.0, 334.0), 21, Color("d9d2df"), HORIZONTAL_ALIGNMENT_CENTER, 576.0)
	_draw_text("ADMOB INTERSTITIAL", Vector2(72.0, 382.0), 38, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 576.0)
	var center := Vector2(360.0, 548.0)
	draw_circle(center, 93.0, Color("7e26d9"))
	draw_circle(center, 69.0, Color("ff4f87"))
	_draw_text("M", Vector2(center.x - 68.0, center.y + 28.0), 76, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 136.0)
	_draw_text("En producción aparecerá después de cada partida", Vector2(72.0, 688.0), 16, Color("c9bed2"), HORIZONTAL_ALIGNMENT_CENTER, 576.0)
	_draw_text("No se realiza ninguna conexión publicitaria en esta versión", Vector2(72.0, 721.0), 13, Color("94889e"), HORIZONTAL_ALIGNMENT_CENTER, 576.0)
	if interstitial_timer > 1.0:
		_draw_text("Continuando en %.0f…" % ceil(interstitial_timer), Vector2(72.0, 811.0), 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 576.0)
	else:
		_draw_button(Rect2(235.0, 790.0, 250.0, 58.0), "CERRAR", Color("46304e"), 17)

func _draw_result() -> void:
	var accent := _theme_color("accent", Color("ff4f87"))
	_draw_text("MOTIVA BRICKS", Vector2(0.0, 102.0), 22, Color("d7c6ed"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	var title := "¡ESCENARIO SUPERADO!" if pending_win else "FIN DE LA PARTIDA"
	_draw_text(title, Vector2(0.0, 184.0), 39, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_text(str(current_level.get("name", "")), Vector2(0.0, 226.0), 20, accent, HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_panel(Rect2(74.0, 285.0, 572.0, 430.0), Color(0.055, 0.02, 0.10, 0.95), accent.darkened(0.25), 2.0)
	_draw_text("PUNTUACIÓN", Vector2(74.0, 350.0), 14, Color("a99bb9"), HORIZONTAL_ALIGNMENT_CENTER, 572.0)
	_draw_text(_format_number(score), Vector2(74.0, 423.0), 58, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 572.0)
	_draw_result_stat("BLOQUES", "%d/%d" % [destroyed_bricks, total_destructible], 492.0)
	_draw_result_stat("MONEDAS", str(coins), 548.0)
	_draw_result_stat("TIEMPO", _format_time(level_elapsed), 604.0)
	var best := int(best_scores.get(str(current_level.get("id", "")), score))
	_draw_result_stat("RÉCORD", _format_number(best), 660.0)
	_draw_button(Rect2(100.0, 775.0, 520.0, 76.0), "JUGAR DE NUEVO", accent, 21)
	_draw_button(Rect2(100.0, 871.0, 520.0, 68.0), "ELEGIR OTRO ESCENARIO", Color("332044"), 17)
	_draw_text("El anuncio intersticial de prueba se mostró al terminar", Vector2(0.0, 1003.0), 14, Color("9c90aa"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_ad_banner()

func _draw_result_stat(label: String, value: String, y: float) -> void:
	_draw_text(label, Vector2(118.0, y), 14, Color("a99bb9"))
	_draw_text(value, Vector2(350.0, y), 18, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 250.0)

func _draw_particles() -> void:
	for particle in particles:
		var life := float(particle.get("life", 0.0))
		var max_life := maxf(0.001, float(particle.get("max_life", 0.55)))
		var alpha := clampf(life / max_life, 0.0, 1.0)
		var color: Color = particle.get("color", Color.WHITE)
		draw_circle(particle.get("pos", Vector2.ZERO), float(particle.get("size", 2.0)) * alpha, Color(color, alpha))

func _draw_panel(rect: Rect2, fill: Color, border: Color, border_width: float = 1.0) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, border_width)

func _draw_button(rect: Rect2, label: String, color: Color, font_size: int) -> void:
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.24), true)
	draw_rect(Rect2(rect.position + Vector2(0.0, 3.0), rect.size - Vector2(0.0, 3.0)), color, true)
	draw_rect(rect, color.lightened(0.28), false, 1.2)
	_draw_text(label, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.64), font_size, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _draw_text(text: String, position: Vector2, size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string(ui_font, position, text, alignment, width, size, color)

func _format_number(value: int) -> String:
	var source := str(maxi(0, value))
	var result := ""
	var count := 0
	for index in range(source.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "." + result
		result = source.substr(index, 1) + result
		count += 1
	return result

func _format_time(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	return "%02d:%02d" % [int(total / 60), total % 60]
