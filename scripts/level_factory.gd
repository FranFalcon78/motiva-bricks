class_name LevelFactory
extends RefCounted

const DEFAULT_PALETTE := ["#ff4f2f", "#ff8a2b", "#ffe75b", "#28dfff", "#a855f7"]
const HASH_MODULUS := 2147483647
const HASH_MULTIPLIER := 48271

static func generate(level: Dictionary, world_width: float = 720.0) -> Dictionary:
	var generator: Dictionary = level.get("generator", {})
	var cols: int = clampi(int(round(float(generator.get("cols", 52)))), 18, 72)
	var rows: int = clampi(int(round(float(generator.get("rows", 38)))), 14, 56)
	var gap: float = clampf(float(generator.get("gap", 2.0)), 1.0, 4.0)
	var area_x: float = float(generator.get("x", 20.0))
	var area_y: float = float(generator.get("y", 150.0))
	var area_width: float = float(generator.get("width", world_width - 40.0))
	var area_height: float = float(generator.get("height", 635.0))
	var cell_width: float = area_width / float(cols)
	var cell_height: float = minf(cell_width, area_height / float(rows))
	var brick_width: float = maxf(4.0, cell_width - gap)
	var brick_height: float = maxf(4.0, cell_height - gap)
	var used_height: float = float(rows) * cell_height
	var start_y: float = area_y + maxf(0.0, (area_height - used_height) * 0.08)
	var pattern_type: String = str(generator.get("pattern", "neon-gates"))
	var seed_value: int = int(level.get("seed", generator.get("seed", 1)))
	var theme: Dictionary = level.get("theme", {})
	var palette_source: Array = theme.get("palette", DEFAULT_PALETTE)
	var palette: Array[Color] = []
	for color_text in palette_source:
		palette.append(_parse_color(str(color_text), Color("ff8a2b")))
	if palette.is_empty():
		for color_text in DEFAULT_PALETTE:
			palette.append(_parse_color(color_text, Color("ff8a2b")))
	var hard_rate: float = clampf(float(generator.get("hardRate", 0.16)), 0.0, 0.60)
	var very_hard_rate: float = clampf(float(generator.get("veryHardRate", 0.035)), 0.0, 0.35)
	var indestructible_rate: float = clampf(float(generator.get("indestructibleRate", 0.025)), 0.0, 0.25)
	var structural_every: int = maxi(0, int(round(float(generator.get("structuralEvery", 0)))))
	var indestructible_color: Color = _parse_color(str(theme.get("indestructible", "#7f8491")), Color("7f8491"))
	var bricks: Array = []
	var destructible_count := 0

	for grid_y in range(rows):
		for grid_x in range(cols):
			var pattern_random := _cell_random(seed_value, grid_x, grid_y, 0)
			if not _pattern_matches(pattern_type, grid_x, grid_y, cols, rows, pattern_random):
				continue
			var roll := _cell_random(seed_value, grid_x, grid_y, 1)
			var linear_index := grid_x + grid_y * cols
			var structural := structural_every > 0 and linear_index % structural_every == 0
			var indestructible := structural or roll < indestructible_rate
			var hp := 1
			if not indestructible:
				var hp_roll := _cell_random(seed_value, grid_x, grid_y, 2)
				if hp_roll < very_hard_rate:
					hp = 3
				elif hp_roll < very_hard_rate + hard_rate:
					hp = 2
				destructible_count += 1
			var brick_color := indestructible_color if indestructible else _palette_color(
				palette, grid_x, grid_y, cols, rows, pattern_type, hp
			)
			var brick_rect := Rect2(
				area_x + float(grid_x) * cell_width + gap * 0.5,
				start_y + float(grid_y) * cell_height + gap * 0.5,
				brick_width,
				brick_height
			)
			bricks.append({
				"id": "%s-%d-%d" % [str(level.get("id", "level")), grid_x, grid_y],
				"grid_x": grid_x,
				"grid_y": grid_y,
				"rect": brick_rect,
				"hp": hp,
				"max_hp": hp,
				"indestructible": indestructible,
				"alive": true,
				"color": brick_color,
				"flash": 0.0
			})

	return {
		"bricks": bricks,
		"columns": cols,
		"rows": rows,
		"area": Rect2(area_x, area_y, area_width, area_height),
		"cell_width": cell_width,
		"cell_height": cell_height,
		"start_y": start_y,
		"destructible_count": destructible_count,
		"total_count": bricks.size()
	}

static func _cell_random(base_seed: int, grid_x: int, grid_y: int, salt: int) -> float:
	var value := absi(base_seed) % HASH_MODULUS
	value = (value + (grid_x + 1) * 73856093 + (grid_y + 1) * 19349663 + (salt + 1) * 83492791) % HASH_MODULUS
	value = (value * HASH_MULTIPLIER + 1) % HASH_MODULUS
	value = (value * HASH_MULTIPLIER + 1) % HASH_MODULUS
	return float(value) / float(HASH_MODULUS)

static func _pattern_matches(pattern_type: String, x: int, y: int, cols: int, rows: int, random_value: float) -> bool:
	match pattern_type:
		"concentric":
			return _pattern_concentric(x, y, cols, rows, random_value)
		"guardian":
			return _pattern_guardian(x, y, cols, rows, random_value)
		"circuit-maze":
			return _pattern_circuit_maze(x, y, cols, rows, random_value)
		"reactor":
			return _pattern_reactor(x, y, cols, rows, random_value)
		"wave-tunnel":
			return _pattern_wave_tunnel(x, y, cols, rows, random_value)
		_:
			return _pattern_neon_gates(x, y, cols, rows, random_value)

static func _pattern_neon_gates(x: int, y: int, cols: int, rows: int, random_value: float) -> bool:
	var top_band := y <= 4
	var outer_wall := (x <= 1 or x >= cols - 2) and y >= 8
	var lower_rail := y >= rows - 3
	var column_width := 3
	var column_stride := 7
	var in_column := y >= 9 and y <= rows - 7 and x % column_stride < column_width
	var middle_y := int(floor(float(rows) * 0.46))
	var middle_bridge := y >= middle_y and y <= middle_y + 2 and x > 5 and x < cols - 6
	var deliberate_gap := (int(floor(float(x) / column_stride)) + int(floor(float(y) / 8.0))) % 5 == 0 and random_value < 0.34
	return (top_band or outer_wall or lower_rail or in_column or middle_bridge) and not deliberate_gap

static func _pattern_concentric(x: int, y: int, cols: int, rows: int, random_value: float) -> bool:
	var distance := mini(mini(x, cols - 1 - x), mini(y, rows - 1 - y))
	var ring := distance % 5
	var ring_brick := ring <= 1
	var center_x := float(cols - 1) * 0.5
	var center_y := float(rows - 1) * 0.5
	var cross := (absf(float(x) - center_x) <= 1.0 or absf(float(y) - center_y) <= 1.0) and distance > 5
	var gate := (absf(float(x) - center_x) <= 2.0 and float(y) < float(rows) * 0.19) or (absf(float(y) - center_y) <= 1.0 and float(x) > float(cols) * 0.78)
	var texture := random_value < 0.045 and distance > 3
	return (ring_brick or cross or texture) and not gate

static func _pattern_guardian(x: int, y: int, cols: int, rows: int, random_value: float) -> bool:
	var nx := float(x) / float(maxi(1, cols - 1))
	var ny := float(y) / float(maxi(1, rows - 1))
	var symmetry_x := absf(nx - 0.5)
	var helmet := ny < 0.17 and symmetry_x < 0.46
	var side_frame := ny >= 0.14 and ny < 0.83 and symmetry_x > 0.38 and symmetry_x < 0.47
	var face_frame := ny > 0.17 and ny < 0.75 and symmetry_x > 0.25 and symmetry_x < 0.34
	var eye_left := nx > 0.25 and nx < 0.42 and ny > 0.27 and ny < 0.43
	var eye_right := nx > 0.58 and nx < 0.75 and ny > 0.27 and ny < 0.43
	var eye_cut_left := nx > 0.30 and nx < 0.38 and ny > 0.31 and ny < 0.39
	var eye_cut_right := nx > 0.62 and nx < 0.70 and ny > 0.31 and ny < 0.39
	var nose := symmetry_x < 0.08 and ny > 0.42 and ny < 0.61
	var mouth_frame := nx > 0.25 and nx < 0.75 and ny > 0.56 and ny < 0.75
	var mouth_cut := nx > 0.34 and nx < 0.66 and ny > 0.61 and ny < 0.68
	var jaw := ny > 0.72 and ny < 0.82 and symmetry_x < 0.34
	var circuit := ny > 0.18 and ny < 0.78 and (x + y * 2) % 11 == 0 and random_value > 0.25
	return helmet or side_frame or face_frame or (eye_left and not eye_cut_left) or (eye_right and not eye_cut_right) or nose or (mouth_frame and not mouth_cut) or jaw or circuit

static func _pattern_circuit_maze(x: int, y: int, cols: int, rows: int, random_value: float) -> bool:
	var border := x <= 1 or x >= cols - 2 or y <= 1 or y >= rows - 2
	var vertical_track := x % 6 <= 1
	var horizontal_track := y % 7 <= 1
	var checker_block := (int(floor(float(x) / 6.0)) + int(floor(float(y) / 7.0))) % 2 == 0
	var track := (vertical_track and checker_block) or (horizontal_track and not checker_block)
	var open_gate := (vertical_track or horizontal_track) and random_value < 0.12
	var node := x % 6 <= 1 and y % 7 <= 1
	return border or node or (track and not open_gate)

static func _pattern_reactor(x: int, y: int, cols: int, rows: int, random_value: float) -> bool:
	var center_x := float(cols - 1) * 0.5
	var center_y := float(rows - 1) * 0.5
	var dx := (float(x) - center_x) / (float(cols) * 0.5)
	var dy := (float(y) - center_y) / (float(rows) * 0.5)
	var radius := sqrt(dx * dx + dy * dy)
	var angle := atan2(dy, dx)
	var ring_index := int(floor(radius * 28.0))
	var ring := ring_index % 4 <= 1 and radius < 0.96 and radius > 0.09
	var spoke_phase := absf(sin(angle * 6.0))
	var spoke := spoke_phase < 0.16 and radius > 0.17 and radius < 0.90
	var core := radius < 0.18 and (x + y) % 2 == 0
	var fracture := random_value < 0.035 and radius > 0.30
	return ring or spoke or core or fracture

static func _pattern_wave_tunnel(x: int, y: int, cols: int, rows: int, random_value: float) -> bool:
	var nx := float(x) / float(maxi(1, cols - 1))
	var wave_a := sin(nx * PI * 5.5) * 4.0 + float(rows) * 0.27
	var wave_b := cos(nx * PI * 4.2) * 5.0 + float(rows) * 0.54
	var wave_c := sin(nx * PI * 7.3 + 1.2) * 3.0 + float(rows) * 0.76
	var thick_wave := absf(float(y) - wave_a) <= 2.0 or absf(float(y) - wave_b) <= 2.0 or absf(float(y) - wave_c) <= 2.0
	var ceiling := y < 3
	var vertical_sparks := x % 8 <= 1 and y > 4 and random_value > 0.58
	var edge := x <= 1 or x >= cols - 2
	return ceiling or edge or thick_wave or vertical_sparks

static func _palette_color(palette: Array[Color], x: int, y: int, cols: int, rows: int, pattern_type: String, max_hp: int) -> Color:
	var index := 0
	if pattern_type == "reactor":
		var center_x := float(cols - 1) * 0.5
		var center_y := float(rows - 1) * 0.5
		var radius := Vector2(float(x) - center_x, float(y) - center_y).length()
		index = int(floor(radius / 3.0))
	elif pattern_type == "concentric":
		index = int(floor(float(mini(mini(x, cols - 1 - x), mini(y, rows - 1 - y))) / 2.0))
	else:
		index = int(floor((float(x) / float(cols)) * float(palette.size()) + (float(y) / float(rows)) * 2.0))
	if max_hp >= 3:
		index += 1
	return palette[absi(index) % palette.size()]

static func _parse_color(value: String, fallback: Color) -> Color:
	return Color.from_string(value, fallback)
