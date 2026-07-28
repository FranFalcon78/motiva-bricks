extends "res://scripts/main.gd"

# Motiva Bricks v0.1.3
# Capa de actualización sobre el motor v0.1.2 para mantener la versión inicial intacta.

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
const BULLET_SPEED := 850.0
const BULLET_INTERVAL := 0.30
const BULLET_SIZE := Vector2(5.0, 18.0)

var bullets: Array = []
var shooter_active := false
var shooter_cooldown := 0.0

func _physics_process(delta: float) -> void:
	if state != ScreenState.PLAYING:
		return
	super._physics_process(delta)
	if state != ScreenState.PLAYING:
		return
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

	# El diámetro de la bola coincide con la altura real del ladrillo.
	var brick_height := 12.0
	if not bricks.is_empty():
		brick_height = float(Rect2(bricks[0].get("rect", Rect2(0.0, 0.0, 12.0, 12.0))).size.y)
	var radius := maxf(3.0, brick_height * 0.5)
	for ball in balls:
		ball["radius"] = radius
		if bool(ball.get("stuck", false)):
			ball["pos"] = Vector2(paddle_x, PADDLE_Y - radius - 6.0)

func _return_to_menu() -> void:
	bullets.clear()
	shooter_active = false
	shooter_cooldown = 0.0
	super._return_to_menu()

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
	_draw_text("Versión 0.1.3 · 10 escenarios · disparo permanente", Vector2(0.0, help_y + 25.0), 12, Color("8e80a9"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x)
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
			message_text = "MONEDA ×3 · BOLAS MULTIPLICADAS"
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

func _update_shooter(delta: float) -> void:
	if not shooter_active:
		return
	shooter_cooldown -= delta
	if shooter_cooldown > 0.0:
		return
	shooter_cooldown = BULLET_INTERVAL
	var half_span := maxf(13.0, paddle_width * 0.32)
	for offset in [-half_span, half_span]:
		bullets.append({"pos": Vector2(paddle_x + offset, PADDLE_Y - 7.0)})
	_play_sound("wall", 0.22)

func _update_bullets(delta: float) -> void:
	for bullet_index in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[bullet_index]
		var position: Vector2 = bullet.get("pos", Vector2.ZERO)
		position.y -= BULLET_SPEED * delta
		bullet["pos"] = position
		if position.y < PLAY_TOP - 24.0:
			bullets.remove_at(bullet_index)
			continue
		var hit := false
		for brick in bricks:
			if not bool(brick.get("alive", false)):
				continue
			# Los proyectiles ignoran los ladrillos indestructibles y se dibujan detrás de ellos.
			if bool(brick.get("indestructible", false)):
				continue
			var rect: Rect2 = brick.get("rect", Rect2())
			if rect.has_point(position):
				_destroy_brick_with_bullet(brick, rect)
				hit = true
				break
		if hit and bullet_index < bullets.size():
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
		var left_x := paddle_x - maxf(13.0, paddle_width * 0.32)
		var right_x := paddle_x + maxf(13.0, paddle_width * 0.32)
		for cannon_x in [left_x, right_x]:
			draw_rect(Rect2(cannon_x - 4.0, PADDLE_Y - 10.0, 8.0, 14.0), Color("79ff8d"), true)
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
