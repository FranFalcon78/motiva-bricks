extends "res://scripts/main.gd"

# Motiva Bricks v0.1.3
# Controlador de gameplay actual. El motor base permanece separado por responsabilidad,
# no como copia de una versión anterior.

const GRID_COLUMNS := 2
const GRID_CARD_X := 30.0
const GRID_CARD_Y := 205.0
const GRID_CARD_W := 322.0
const GRID_CARD_H := 151.0
const GRID_CARD_GAP_X := 16.0
const GRID_CARD_GAP_Y := 14.0
const BRICK_SCALE := 0.75
const PADDLE_SCALE := 0.70
const POWERUP_RATE_SCALE := 0.25
const HARD_MAX_BALLS := 300
const BULLET_SPEED := 850.0
const BULLET_INTERVAL := 0.30
const BULLET_SIZE := Vector2(5.0, 18.0)
const STUCK_SAMPLE_SECONDS := 0.60
const STUCK_DISTANCE_FACTOR := 3.0
const STUCK_COLLISION_LIMIT := 7
const ESCAPE_COOLDOWN_SECONDS := 0.42

var bullets: Array = []
var shooter_active := false
var shooter_cooldown := 0.0

func _ready() -> void:
	super._ready()
	max_balls = clampi(int(config.get("max_balls", HARD_MAX_BALLS)), 1, HARD_MAX_BALLS)
	remote_status = "%d escenarios locales preparados" % levels.size()

func _physics_process(delta: float) -> void:
	if state != ScreenState.PLAYING:
		return
	super._physics_process(delta)
	if state != ScreenState.PLAYING:
		return
	_update_ball_escape_control(delta)
	_update_shooter(delta)
	_update_bullets(delta)

func _handle_key(event: InputEventKey) -> void:
	if state == ScreenState.MENU:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var index := int(event.keycode - KEY_1)
			if index < levels.size():
				_start_level(index)
			return
		if event.keycode == KEY_0 and levels.size() >= 10:
			_start_level(9)
			return
	super._handle_key(event)

func _start_level(index: int) -> void:
	super._start_level(index)
	if state != ScreenState.PLAYING:
		return
	shooter_active = false
	shooter_cooldown = 0.0
	bullets.clear()

	# Carro un 30 % más pequeño.
	paddle_base_width = maxf(72.0, paddle_base_width * PADDLE_SCALE)
	paddle_width = paddle_base_width

	# Ladrillos un 25 % más pequeños conservando el centro de cada celda.
	for brick in bricks:
		var rect: Rect2 = brick.get("rect", Rect2())
		var scaled_size := rect.size * BRICK_SCALE
		brick["rect"] = Rect2(rect.get_center() - scaled_size * 0.5, scaled_size)

	# El diámetro de todas las bolas coincide con la altura real del ladrillo.
	var radius := _current_ball_radius()
	for ball in balls:
		ball["radius"] = radius
		if bool(ball.get("stuck", false)):
			ball["pos"] = Vector2(paddle_x, PADDLE_Y - radius - 6.0)
		_register_ball_monitor(ball)

func _return_to_menu() -> void:
	bullets.clear()
	shooter_active = false
	shooter_cooldown = 0.0
	super._return_to_menu()

func _spawn_stuck_ball() -> void:
	super._spawn_stuck_ball()
	if balls.is_empty():
		return
	var ball: Dictionary = balls.back()
	var radius := _current_ball_radius()
	ball["radius"] = radius
	ball["pos"] = Vector2(paddle_x, PADDLE_Y - radius - 6.0)
	_register_ball_monitor(ball)

func _current_ball_radius() -> float:
	if not bricks.is_empty():
		var rect: Rect2 = bricks[0].get("rect", Rect2(0.0, 0.0, 12.0, 12.0))
		return maxf(3.0, rect.size.y * 0.5)
	return maxf(3.0, float(current_level.get("physics", {}).get("ballRadius", 8.0)))

func _register_ball_monitor(ball: Dictionary) -> void:
	var position: Vector2 = ball.get("pos", Vector2.ZERO)
	ball["monitor_anchor"] = position
	ball["monitor_time"] = 0.0
	ball["stagnant_samples"] = 0
	ball["collision_burst"] = 0
	ball["collision_anchor"] = position
	ball["escape_cooldown"] = 0.0
	ball["escape_attempt"] = 0

func _update_ball_escape_control(delta: float) -> void:
	for ball in balls:
		if bool(ball.get("stuck", false)):
			_register_ball_monitor(ball)
			continue
		var cooldown := maxf(0.0, float(ball.get("escape_cooldown", 0.0)) - delta)
		ball["escape_cooldown"] = cooldown
		ball["monitor_time"] = float(ball.get("monitor_time", 0.0)) + delta
		if float(ball["monitor_time"]) < STUCK_SAMPLE_SECONDS:
			continue

		var position: Vector2 = ball.get("pos", Vector2.ZERO)
		var anchor: Vector2 = ball.get("monitor_anchor", position)
		var radius := float(ball.get("radius", _current_ball_radius()))
		var minimum_progress := maxf(12.0, radius * STUCK_DISTANCE_FACTOR)
		var stagnant := int(ball.get("stagnant_samples", 0))
		if position.distance_to(anchor) < minimum_progress:
			stagnant += 1
		else:
			stagnant = maxi(0, stagnant - 1)
		ball["stagnant_samples"] = stagnant
		ball["monitor_anchor"] = position
		ball["monitor_time"] = 0.0
		ball["collision_burst"] = maxi(0, int(ball.get("collision_burst", 0)) - 1)

		var repeated_hits := int(ball.get("collision_burst", 0)) >= 4
		if cooldown <= 0.0 and (stagnant >= 3 or (stagnant >= 2 and repeated_hits)):
			_escape_ball(ball)

func _resolve_brick_hit(ball: Dictionary, brick: Dictionary, brick_index: int) -> void:
	super._resolve_brick_hit(ball, brick, brick_index)
	if state != ScreenState.PLAYING:
		return
	var position: Vector2 = ball.get("pos", Vector2.ZERO)
	var radius := float(ball.get("radius", _current_ball_radius()))
	var previous: Vector2 = ball.get("collision_anchor", position)
	var burst := int(ball.get("collision_burst", 0))
	if position.distance_to(previous) <= maxf(10.0, radius * 3.2):
		burst += 1
	else:
		burst = 1
	ball["collision_anchor"] = position
	ball["collision_burst"] = burst
	if burst >= STUCK_COLLISION_LIMIT and float(ball.get("escape_cooldown", 0.0)) <= 0.0:
		_escape_ball(ball)

func _escape_ball(ball: Dictionary) -> void:
	var position: Vector2 = ball.get("pos", Vector2.ZERO)
	var velocity: Vector2 = ball.get("vel", Vector2(0.0, -_configured_ball_speed()))
	var speed := clampf(velocity.length(), MIN_SPEED, MAX_SPEED)
	if speed < MIN_SPEED:
		speed = _configured_ball_speed()
	var attempt := int(ball.get("escape_attempt", 0)) % 4
	var direction := velocity.normalized()
	if direction.length_squared() < 0.5:
		direction = Vector2(0.35, -1.0).normalized()

	match attempt:
		0:
			var turn := rng.randf_range(22.0, 36.0)
			if rng.randf() < 0.5:
				turn = -turn
			direction = direction.rotated(deg_to_rad(turn))
		1:
			var vertical_sign := -1.0 if velocity.y >= 0.0 else 1.0
			direction = Vector2(rng.randf_range(-0.95, 0.95), vertical_sign).normalized()
		2:
			direction = Vector2(-direction.x + rng.randf_range(-0.35, 0.35), -direction.y).normalized()
		_:
			direction = Vector2(rng.randf_range(-0.75, 0.75), -1.0).normalized()

	if absf(direction.x) < 0.22:
		direction.x = 0.22 if rng.randf() >= 0.5 else -0.22
	if absf(direction.y) < 0.30:
		direction.y = 0.30 if direction.y >= 0.0 else -0.30
	direction = direction.normalized()

	var radius := float(ball.get("radius", _current_ball_radius()))
	ball["pos"] = _find_escape_position(position, radius, direction)
	ball["vel"] = direction * speed
	ball["hit_cooldown"] = 0.08
	ball["escape_cooldown"] = ESCAPE_COOLDOWN_SECONDS
	ball["escape_attempt"] = int(ball.get("escape_attempt", 0)) + 1
	ball["monitor_anchor"] = ball["pos"]
	ball["monitor_time"] = 0.0
	ball["stagnant_samples"] = 0
	ball["collision_burst"] = 0
	_spawn_sparks(ball["pos"], _theme_color("accent", Color("ff4f87")), 4)

func _find_escape_position(origin: Vector2, radius: float, preferred: Vector2) -> Vector2:
	var direction := preferred.normalized()
	if direction.length_squared() < 0.5:
		direction = Vector2.UP
	var angle_offsets := [0.0, 24.0, -24.0, 48.0, -48.0, 90.0, -90.0, 180.0]
	var distance_scales := [2.6, 4.2, 6.2, 8.5]
	for distance_scale in distance_scales:
		for angle_degrees in angle_offsets:
			var candidate := origin + direction.rotated(deg_to_rad(float(angle_degrees))) * radius * float(distance_scale)
			candidate.x = clampf(candidate.x, PLAY_LEFT + radius + 2.0, PLAY_RIGHT - radius - 2.0)
			candidate.y = clampf(candidate.y, PLAY_TOP + radius + 2.0, DEATH_Y - radius - 4.0)
			if not _position_overlaps_alive_brick(candidate, radius):
				return candidate

	var area: Rect2 = generated.get("area", Rect2(PLAY_LEFT, PLAY_TOP, PLAY_RIGHT - PLAY_LEFT, 650.0))
	var fallback_y := clampf(minf(PADDLE_Y - radius * 6.0, area.end.y + radius * 4.0), PLAY_TOP + radius, PADDLE_Y - radius * 3.0)
	var fallback_x_values := [origin.x, paddle_x, VIEW_SIZE.x * 0.5, rng.randf_range(PLAY_LEFT + radius, PLAY_RIGHT - radius)]
	for fallback_x in fallback_x_values:
		var fallback := Vector2(clampf(float(fallback_x), PLAY_LEFT + radius, PLAY_RIGHT - radius), fallback_y)
		if not _position_overlaps_alive_brick(fallback, radius):
			return fallback
	return Vector2(VIEW_SIZE.x * 0.5, fallback_y)

func _position_overlaps_alive_brick(position: Vector2, radius: float) -> bool:
	for brick in bricks:
		if bool(brick.get("alive", false)) and _circle_intersects_rect(position, radius, brick.get("rect", Rect2())):
			return true
	return false

func _triple_balls() -> void:
	if balls.is_empty():
		return
	var canonical_radius := _current_ball_radius()
	for ball in balls:
		ball["radius"] = canonical_radius

	var originals: Array = balls.duplicate(true)
	var target_count := mini(max_balls, originals.size() * 3)
	if target_count <= balls.size():
		return

	for source in originals:
		if balls.size() >= target_count:
			break
		var source_velocity: Vector2 = source.get("vel", Vector2(0.0, -_configured_ball_speed()))
		if bool(source.get("stuck", false)) or source_velocity.length_squared() < 1.0:
			source_velocity = Vector2(0.0, -_configured_ball_speed())
		var source_position: Vector2 = source.get("pos", Vector2(paddle_x, PADDLE_Y - canonical_radius - 6.0))
		var perpendicular := source_velocity.normalized().orthogonal()
		for angle_degrees in [-22.0, 22.0]:
			if balls.size() >= target_count:
				break
			var copy: Dictionary = source.duplicate(true)
			copy["stuck"] = false
			copy["radius"] = canonical_radius
			copy["vel"] = source_velocity.rotated(deg_to_rad(angle_degrees))
			var side := -1.0 if angle_degrees < 0.0 else 1.0
			copy["pos"] = _find_escape_position(source_position, canonical_radius, perpendicular * side)
			copy["trail"] = []
			copy["hit_cooldown"] = 0.06
			_register_ball_monitor(copy)
			balls.append(copy)

func _menu_card_rect(index: int) -> Rect2:
	var column := index % GRID_COLUMNS
	var row := int(index / GRID_COLUMNS)
	return Rect2(
		GRID_CARD_X + float(column) * (GRID_CARD_W + GRID_CARD_GAP_X),
		GRID_CARD_Y + float(row) * (GRID_CARD_H + GRID_CARD_GAP_Y),
		GRID_CARD_W,
		GRID_CARD_H
	)

func _draw_menu() -> void:
	_draw_text("MOTIVA", Vector2(0.0, 59.0), 21, Color("ffb6de"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_text("BRICKS", Vector2(0.0, 112.0), 50, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_text("ELIGE UNO DE LOS 10 ESCENARIOS", Vector2(0.0, 146.0), 15, Color("d8c9ff"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_text(remote_status, Vector2(31.0, 180.0), 12, Color("b9adcf"))
	_draw_button(Rect2(485.0, 151.0, 205.0, 38.0), "ACTUALIZAR NIVELES", Color("3d1b64"), 12)

	for index in range(mini(levels.size(), 10)):
		_draw_level_card(index)

	var help_y := 1042.0
	_draw_text("Ratón o táctil: mueve el carro · Espacio: lanza · P/Esc: pausa", Vector2(0.0, help_y), 13, Color("c9bddb"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_text("Versión 0.1.3 · hasta 300 bolas · control antiatasco", Vector2(0.0, help_y + 25.0), 12, Color("8e80a9"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
	_draw_ad_banner()

func _draw_level_card(index: int) -> void:
	var level: Dictionary = levels[index]
	var rect := _menu_card_rect(index)
	var theme: Dictionary = level.get("theme", {})
	var accent := Color.from_string(str(theme.get("accent", "#ff4f87")), Color("ff4f87"))
	_draw_panel(rect, Color(0.075, 0.035, 0.14, 0.95), accent.darkened(0.25), 1.5)

	var preview_rect := Rect2(rect.position + Vector2(9.0, 9.0), Vector2(112.0, rect.size.y - 18.0))
	draw_rect(preview_rect, Color(0.02, 0.01, 0.06, 0.92), true)
	_draw_preview(index, preview_rect.grow(-4.0))

	var text_x := rect.position.x + 131.0
	_draw_text("NIVEL %02d" % (index + 1), Vector2(text_x, rect.position.y + 27.0), 11, accent)
	_draw_text(str(level.get("name", "Escenario")), Vector2(text_x, rect.position.y + 57.0), 18, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 140.0)
	_draw_text(str(level.get("subtitle", "")), Vector2(text_x, rect.position.y + 80.0), 10, Color("c8bcd8"), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 140.0)
	var generated_preview: Dictionary = previews[index].get("generated", {})
	var count := int(generated_preview.get("total_count", 0))
	var best := int(best_scores.get(str(level.get("id", "")), 0))
	_draw_text("%d bloques" % count, Vector2(text_x, rect.position.y + 109.0), 11, Color("968aa9"))
	_draw_text("récord %s" % _format_number(best), Vector2(text_x, rect.position.y + 130.0), 10, Color("968aa9"))

func _try_drop_powerup(position: Vector2) -> void:
	var powerup_data: Dictionary = current_level.get("powerups", {})
	var drop_rate := float(powerup_data.get("dropRate", 0.12)) * POWERUP_RATE_SCALE
	if rng.randf() > drop_rate:
		return

	var weights: Dictionary = powerup_data.get("weights", {})
	var options := ["triple", "wide", "shield", "shooter"]
	var option_weights := [
		float(weights.get("triple", 0.28)),
		float(weights.get("wide", 0.27)),
		float(weights.get("shield", 0.27)),
		float(weights.get("shooter", 0.18))
	]
	var total := 0.0
	for weight in option_weights:
		total += maxf(0.0, float(weight))
	var roll := rng.randf() * maxf(total, 0.001)
	var accumulated := 0.0
	var power_type := "shooter"
	for option_index in range(options.size()):
		accumulated += maxf(0.0, float(option_weights[option_index]))
		if roll <= accumulated:
			power_type = str(options[option_index])
			break

	powerups.append({
		"pos": position,
		"type": power_type,
		"rotation": rng.randf_range(-0.4, 0.4),
		"pulse": rng.randf_range(0.0, TAU),
		"radius": 17.0
	})

func _apply_powerup(power_type: String) -> void:
	coins += 1
	score += 250
	match power_type:
		"triple":
			_triple_balls()
			message_text = "MONEDA ×3 · %d BOLAS" % balls.size()
			_play_sound("launch")
		"wide":
			var data: Dictionary = current_level.get("powerups", {})
			wide_timer = float(data.get("wideSeconds", 15.0))
			paddle_width = minf(240.0, paddle_base_width * float(data.get("wideMultiplier", 1.65)))
			message_text = "MONEDA W · CARRO AMPLIADO"
			_play_sound("power")
		"shield":
			shield_timer = float(current_level.get("powerups", {}).get("shieldSeconds", 12.0))
			message_text = "MONEDA S · FOSO CERRADO"
			_play_sound("shield")
		"shooter":
			shooter_active = true
			shooter_cooldown = 0.0
			message_text = "MONEDA F · DISPARO PERMANENTE"
			_play_sound("brick")
	message_timer = 2.4
	_spawn_burst(Vector2(paddle_x, PADDLE_Y), _powerup_color(power_type), 15)

func _powerup_color(power_type: String) -> Color:
	match power_type:
		"triple":
			return Color("ff4f87")
		"wide":
			return Color("ffe75b")
		"shield":
			return Color("28dfff")
		"shooter":
			return Color("79ff8d")
		_:
			return Color.WHITE

func _cannon_positions() -> Array:
	var outer_half_width := paddle_width * 0.5 + PADDLE_HEIGHT * 0.42
	return [
		clampf(paddle_x - outer_half_width, PLAY_LEFT + BULLET_SIZE.x * 0.5, PLAY_RIGHT - BULLET_SIZE.x * 0.5),
		clampf(paddle_x + outer_half_width, PLAY_LEFT + BULLET_SIZE.x * 0.5, PLAY_RIGHT - BULLET_SIZE.x * 0.5)
	]

func _update_shooter(delta: float) -> void:
	if not shooter_active:
		return
	shooter_cooldown -= delta
	if shooter_cooldown > 0.0:
		return
	shooter_cooldown = BULLET_INTERVAL
	for cannon_x in _cannon_positions():
		bullets.append({"pos": Vector2(float(cannon_x), PADDLE_Y - 10.0)})
	_play_sound("wall", 0.22)

func _update_bullets(delta: float) -> void:
	for bullet_index in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[bullet_index]
		var previous: Vector2 = bullet.get("pos", Vector2.ZERO)
		var position := previous + Vector2(0.0, -BULLET_SPEED * delta)
		bullet["pos"] = position
		if position.y < PLAY_TOP - 24.0:
			bullets.remove_at(bullet_index)
			continue

		var travel_height := absf(previous.y - position.y) + BULLET_SIZE.y
		var bullet_rect := Rect2(
			Vector2(position.x - BULLET_SIZE.x * 0.5, position.y - BULLET_SIZE.y * 0.5),
			Vector2(BULLET_SIZE.x, travel_height)
		)
		var hit := false
		for brick in bricks:
			if not bool(brick.get("alive", false)):
				continue
			# Los proyectiles pasan visual y físicamente por detrás de los indestructibles.
			if bool(brick.get("indestructible", false)):
				continue
			var rect: Rect2 = brick.get("rect", Rect2())
			if bullet_rect.intersects(rect):
				_destroy_brick_with_bullet(brick, rect)
				hit = true
				break
		if hit:
			bullets.remove_at(bullet_index)
		if state != ScreenState.PLAYING:
			return

func _destroy_brick_with_bullet(brick: Dictionary, rect: Rect2) -> void:
	brick["hp"] = 0
	brick["alive"] = false
	remaining_bricks = maxi(0, remaining_bricks - 1)
	destroyed_bricks += 1
	score += 110 + int(brick.get("max_hp", 1)) * 30
	_spawn_burst(rect.get_center(), Color(brick.get("color", Color.WHITE)), 6)
	_play_sound("break", 0.72)
	if remaining_bricks <= 0:
		_finish_game(true)

func _draw_game() -> void:
	_draw_hud()
	_draw_playfield_frame()
	_draw_bullets()
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

func _draw_bullets() -> void:
	var color := Color("79ff8d")
	for bullet in bullets:
		var position: Vector2 = bullet.get("pos", Vector2.ZERO)
		draw_rect(Rect2(position - BULLET_SIZE * 0.5, BULLET_SIZE), Color(color, 0.95), true)
		draw_rect(Rect2(position - Vector2(1.0, 9.0), Vector2(2.0, 14.0)), Color.WHITE, true)

func _draw_paddle() -> void:
	super._draw_paddle()
	if shooter_active:
		for cannon_x in _cannon_positions():
			draw_rect(Rect2(float(cannon_x) - 4.0, PADDLE_Y - 10.0, 8.0, 14.0), Color("79ff8d"), true)
		_draw_text("FUEGO", Vector2(paddle_x - paddle_width * 0.5, PADDLE_Y - 13.0), 10, Color("79ff8d"), HORIZONTAL_ALIGNMENT_CENTER, paddle_width)

func _draw_powerups() -> void:
	for powerup in powerups:
		var position: Vector2 = powerup.get("pos", Vector2.ZERO)
		var power_type := str(powerup.get("type", "wide"))
		var color := _powerup_color(power_type)
		var pulse := 1.0 + sin(float(powerup.get("pulse", 0.0))) * 0.08
		draw_circle(position, 23.0 * pulse, Color(color, 0.12))
		draw_circle(position, 17.0 * pulse, color)
		draw_arc(position, 13.0 * pulse, 0.0, TAU, 24, Color.WHITE, 2.0)
		var label := "×3"
		if power_type == "wide":
			label = "W"
		elif power_type == "shield":
			label = "S"
		elif power_type == "shooter":
			label = "F"
		_draw_text(label, Vector2(position.x - 22.0, position.y + 6.0), 14, Color("160024"), HORIZONTAL_ALIGNMENT_CENTER, 44.0)
