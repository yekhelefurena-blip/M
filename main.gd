extends Node3D
## Blocky World - mobile 3D sandbox. The whole world is generated from code,
## so there are no external assets. Godot 4.x, GL Compatibility renderer.

const BlockyScript = preload("res://blocky.gd")
const PlayerScript = preload("res://player.gd")
const ControlsScript = preload("res://touch_controls.gd")
const OnlineScript = preload("res://online.gd")

const WATER_X0 := -34.0
const WATER_X1 := -24.0
const MINI_PAD := Vector3(10.0, 0.0, -16.0)
const START_POS := Vector3(0.0, 0.1, 34.0)
const CHILL_RECT := Rect2(-13.0, 16.0, 8.0, 8.0)
const GAME_LENGTH := 45.0
const PARKOUR_ASSET := "res://assets/parkour_map.glb"
const WORLD_BOUNDS_LIMIT := 94.0
const WORLD_RESPAWN := Vector3(0.0, 1.0, 34.0)
const BASE_FOV := 70.0
const MAGNET_RANGE := 3.4     # coins drift toward the player inside this range
const COMBO_WINDOW := 2.0     # Coin Rush: grab the next coin within this many seconds to keep a streak
const COMBO_BONUS := 3.0      # Coin Rush: +seconds every 5th coin in a streak

var rng := RandomNumberGenerator.new()
var noise_tex: ImageTexture
var mat_cache := {}
var world_root: Node3D
var blocked: Array[Rect2] = []

var player # player.gd instance
var controls # touch_controls.gd instance
var cam_pivot: Node3D
var cam_arm: SpringArm3D
var cam: Camera3D
var online # online.gd instance: other players + chat
var chat_edit: LineEdit
var chat_open := false
var cam_yaw := 0.0
var cam_pitch := -0.42
var sun: DirectionalLight3D

var score_label: Label
var info_label: Label
var toast_label: Label
var toast_tween: Tween

var score := 0 # mirrors Customization.coins (saved between sessions)
var best := 0
var coins: Array[Node3D] = []
var coin_mat: StandardMaterial3D     # bright face (also used for the pickup sparks)
var coin_rim_mat: StandardMaterial3D # darker outer rim
var coin_gem_mat: StandardMaterial3D # little diamond in the middle
var _coin_rim_mesh: CylinderMesh
var _coin_face_mesh: CylinderMesh
var _coin_gem_mesh: BoxMesh
var blades: Node3D
var clouds: Array[Node3D] = []
var npcs: Array = []
var snd_coin: AudioStreamPlayer
var snd_jump: AudioStreamPlayer
var snd_land: AudioStreamPlayer

var pad_mat: StandardMaterial3D
var pad_gem: Node3D
var pad_armed := true
var game_active := false
var game_time := 0.0
var game_coins := 0
var combo := 0
var last_collect_t := -10.0
var chill_timer := 0.0
var chill_cooldown := 0.0
var time_acc := 0.0

## "none" | "coinrush" | "parkour" — which minigame (if any) is running.
var game_mode := "none"
var shift_lock_enabled := false

## Parkour minigame (imported .glb course lives far from the main map).
var parkour_root: Node3D
var parkour_aabb := AABB()
var parkour_spawn := Vector3.ZERO
var parkour_fall_y := -20.0
var parkour_bounds_limit := 60.0
var parkour_time := 0.0

## Community level (Studio) — a level someone published, played through the
## "ألعاب اللاعبين" browser. Built fresh from JSON every time (see
## _build_community_level below), never as code, so a level published by
## anyone else can only ever place the six kinds of block level_script.gd's
## actions and the cells below allow — nothing it contains can run on your
## device as a script.
const COMMUNITY_ORIGIN := Vector3(0.0, 0.0, 700.0) # tucked far from everything else
const COMMUNITY_CELL := 3.0
var community_root: Node3D
var community_title := ""
var community_author := ""
var community_grid_n := 16
var community_spawn := Vector3.ZERO
var community_bounds_limit := 60.0
var community_speed_mult := 1.0     # the level's own setting (Studio "Player speed")
var community_jump_mult := 1.0      # the level's own setting (Studio "Player jump")
var community_finishes: Array = []  # [Vector2(x,z), ...] world-space finish points
var community_triggers: Array = []  # [{"pos":Vector2, "actions":[...], "armed":bool}, ...]
var community_timers: Array = []    # [{"t":float, "action":{...}, "fired":bool}, ...]
var community_time := 0.0
var community_ended := false
var _temp_speed_until := 0.0        # a speed-pad boost reverts to the level's own setting after this


func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	# The home screen uses a portrait 720x1280 UI scale; gameplay is landscape.
	get_window().content_scale_size = Vector2i(1280, 720)
	rng.seed = 20260919
	_make_noise_texture()
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)

	blocked = [
		Rect2(-6, -72, 12, 120),   # main path
		Rect2(-16, -18, 32, 34),   # minigame arena
		Rect2(-20, -36, 44, 22),   # plaza buildings
		Rect2(-37, -100, 15, 200), # river
		Rect2(24, -100, 80, 130),  # desert
		Rect2(-27, -70, 58, 28),   # village
		Rect2(-32, -100, 64, 32),  # castle
		Rect2(-16, 14, 14, 14),    # chill zone
		Rect2(3, 21, 7, 6),        # signpost
		Rect2(-90, -80, 55, 55),   # mountain
	]

	var community_level := Studio.consume_pending() # {} unless we came from "ألعاب اللاعبين"
	var is_community := not community_level.is_empty()

	_setup_environment()
	if not is_community:
		_build_ground()
		_build_river()
		_build_path()
		_build_desert()
		_build_mountains()
		_build_castle()
		_build_village()
		_build_minigames_building()
		_build_signs_and_chill()
		_build_windmill()
		_build_trees()
		_build_flowers()
		_build_clouds()

	# Coin look: darker rim, bright raised face, small diamond in the middle.
	# (the meshes and materials are shared by every coin)
	coin_mat = StandardMaterial3D.new()
	coin_mat.albedo_color = Color(1.0, 0.85, 0.2)
	coin_mat.emission_enabled = true
	coin_mat.emission = Color(0.95, 0.65, 0.05)
	coin_mat.emission_energy_multiplier = 0.7
	coin_rim_mat = StandardMaterial3D.new()
	coin_rim_mat.albedo_color = Color(0.9, 0.55, 0.05)
	coin_rim_mat.emission_enabled = true
	coin_rim_mat.emission = Color(0.6, 0.3, 0.0)
	coin_rim_mat.emission_energy_multiplier = 0.5
	coin_gem_mat = StandardMaterial3D.new()
	coin_gem_mat.albedo_color = Color(1.0, 0.97, 0.7)
	coin_gem_mat.emission_enabled = true
	coin_gem_mat.emission = Color(1.0, 0.9, 0.4)
	coin_gem_mat.emission_energy_multiplier = 1.0
	_coin_rim_mesh = CylinderMesh.new()
	_coin_rim_mesh.top_radius = 0.6
	_coin_rim_mesh.bottom_radius = 0.6
	_coin_rim_mesh.height = 0.16
	_coin_rim_mesh.radial_segments = 16
	_coin_face_mesh = CylinderMesh.new()
	_coin_face_mesh.top_radius = 0.46
	_coin_face_mesh.bottom_radius = 0.46
	_coin_face_mesh.height = 0.22
	_coin_face_mesh.radial_segments = 16
	_coin_gem_mesh = BoxMesh.new()
	_coin_gem_mesh.size = Vector3(0.24, 0.3, 0.24)

	_spawn_player()
	player.landed.connect(_on_player_landed)
	_spawn_camera()
	if not is_community:
		_spawn_npcs()
		_spawn_start_coins()
	_build_hud()
	online = OnlineScript.new()
	add_child(online)
	online.setup(self)
	controls.chat_lines = online.chat_lines
	if not is_community:
		_build_parkour_world()
	_setup_audio()
	_load_best()
	score = Customization.coins
	_update_hud()
	if is_community:
		_build_community_level(community_level)
		_start_community()
	else:
		toast("Welcome! Step on the MINIGAMES pad to choose Coin Rush or Parkour", 4.0)


# ----------------------------------------------------------------- helpers

func _make_noise_texture() -> void:
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGB8)
	for y in 8:
		for x in 8:
			var v := rng.randf_range(0.8, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	noise_tex = ImageTexture.create_from_image(img)


func mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if mat_cache.has(key):
		return mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = noise_tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1, 1, 1)
	m.roughness = 1.0
	mat_cache[key] = m
	return m


func block(pos: Vector3, size: Vector3, color: Color, collide: bool = true, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(color)
	mi.position = pos
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		mi.add_child(body)
	if parent == null:
		world_root.add_child(mi)
	else:
		parent.add_child(mi)
	return mi


func flat(x0: float, x1: float, z0: float, z1: float, y: float, color: Color) -> MeshInstance3D:
	var mi := block(Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5), Vector3(x1 - x0, 0.02, z1 - z0), color, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func label3d(pos: Vector3, text: String, px: float = 0.012, color: Color = Color(1, 1, 1), billboard: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = px
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 1)
	l.modulate = color
	l.position = pos
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	world_root.add_child(l)
	return l


func _is_blocked(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for r in blocked:
		if r.has_point(p):
			return true
	return false


func _rand_in(rect: Rect2) -> Vector3:
	return Vector3(rng.randf_range(rect.position.x, rect.end.x), 0.0, rng.randf_range(rect.position.y, rect.end.y))


# ------------------------------------------------------------- environment

func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.5, 0.95)
	sky_mat.sky_horizon_color = Color(0.72, 0.86, 1.0)
	sky_mat.ground_horizon_color = Color(0.72, 0.86, 1.0)
	sky_mat.ground_bottom_color = Color(0.55, 0.7, 0.85)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 0.95)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.87, 1.0)
	env.fog_density = 0.004

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)


# ------------------------------------------------------------------- world

func _build_ground() -> void:
	block(Vector3(0, -1, 0), Vector3(400, 2, 400), Color(0.36, 0.68, 0.2))
	for i in 45:
		var w := rng.randf_range(4.0, 12.0)
		var d := rng.randf_range(4.0, 12.0)
		var x := rng.randf_range(-90.0, 90.0)
		var z := rng.randf_range(-90.0, 60.0)
		var s := rng.randf_range(-0.07, 0.07)
		flat(x, x + w, z, z + d, 0.02, Color(0.36 + s, 0.68 + s, 0.2 + s * 0.5))


func _build_river() -> void:
	var sand := Color(0.9, 0.82, 0.55)
	flat(WATER_X0 - 2.0, WATER_X0, -100.0, 100.0, 0.05, sand)
	flat(WATER_X1, WATER_X1 + 2.0, -100.0, 100.0, 0.05, sand)
	flat(WATER_X0, WATER_X1, -100.0, 100.0, 0.05, Color(0.2, 0.4, 0.85))
	for i in 30:
		var x := rng.randf_range(WATER_X0, WATER_X1 - 3.0)
		var z := rng.randf_range(-95.0, 95.0)
		flat(x, x + rng.randf_range(1.5, 3.0), z, z + rng.randf_range(2.0, 6.0), 0.065, Color(0.35, 0.55, 0.95))

	# stone bridge you can walk under
	var stone := Color(0.55, 0.55, 0.6)
	block(Vector3(-29, 3.6, -40), Vector3(20, 0.6, 4), stone)
	block(Vector3(-29, 4.3, -41.85), Vector3(20, 0.8, 0.3), stone, false)
	block(Vector3(-29, 4.3, -38.15), Vector3(20, 0.8, 0.3), stone, false)
	for px in [-38.2, -19.8]:
		for pz in [-41.2, -38.8]:
			block(Vector3(px, 1.8, pz), Vector3(1.2, 3.6, 1.2), stone)


func _build_path() -> void:
	var sand := Color(0.87, 0.77, 0.46)
	flat(-3.0, 3.0, -72.0, 46.0, 0.04, sand)
	flat(-14.0, 14.0, -34.0, -12.0, 0.045, sand) # plaza
	var cols := [Color(0.6, 0.32, 0.2), Color(0.62, 0.62, 0.68), Color(0.7, 0.42, 0.25)]
	for i in 34:
		var x := rng.randf_range(-2.4, 2.4)
		var z := rng.randf_range(-68.0, 42.0)
		var s := rng.randf_range(1.0, 1.6)
		var c: Color = cols[rng.randi() % cols.size()]
		flat(x, x + s, z, z + s, 0.06, c)


func _build_desert() -> void:
	flat(26.0, 100.0, -72.0, 28.0, 0.05, Color(0.93, 0.85, 0.55))
	var sandstone := Color(0.85, 0.75, 0.5)
	for i in 5:
		var s := 26.0 - i * 5.0
		block(Vector3(56, 1.0 + i * 2.0, -28), Vector3(s, 2, s), sandstone)
	block(Vector3(56, 1.5, -14.9), Vector3(3, 3, 0.3), Color(0.25, 0.15, 0.1), false)
	# cacti
	var placed := 0
	var tries := 0
	while placed < 14 and tries < 200:
		tries += 1
		var x := rng.randf_range(30.0, 92.0)
		var z := rng.randf_range(-62.0, 22.0)
		if Vector2(x, z).distance_to(Vector2(56, -28)) < 20.0:
			continue
		var h := rng.randf_range(3.0, 4.5)
		var g := Color(0.2, 0.55, 0.2)
		block(Vector3(x, h * 0.5, z), Vector3(0.9, h, 0.9), g)
		block(Vector3(x - 0.9, h * 0.6, z), Vector3(1.0, 0.6, 0.6), g, false)
		block(Vector3(x - 1.4, h * 0.6 + 0.8, z), Vector3(0.6, 1.4, 0.6), g, false)
		placed += 1


func _mountain(cx: float, cz: float, base: float, layers: int) -> void:
	for i in layers:
		var s := base - i * (base / (layers + 1.0))
		var col := Color(0.5, 0.48, 0.47) if i % 2 == 0 else Color(0.45, 0.4, 0.36)
		if i >= layers - 2:
			col = Color(0.95, 0.96, 1.0)
		var jx := rng.randf_range(-1.5, 1.5)
		var jz := rng.randf_range(-1.5, 1.5)
		block(Vector3(cx + jx, 2.5 + i * 5.0, cz + jz), Vector3(s, 5, s), col)


func _build_mountains() -> void:
	_mountain(-62.0, -52.0, 50.0, 7)
	_mountain(-92.0, -20.0, 36.0, 5)
	_mountain(70.0, -88.0, 40.0, 6)


func _flag(p: Vector3) -> void:
	block(p + Vector3(0, 1.5, 0), Vector3(0.2, 3.0, 0.2), Color(0.25, 0.2, 0.15), false)
	block(p + Vector3(0.9, 2.4, 0), Vector3(1.6, 1.0, 0.1), Color(0.85, 0.15, 0.15), false)


func _build_castle() -> void:
	var stone := Color(0.62, 0.62, 0.66)
	var dark := Color(0.5, 0.5, 0.55)
	var roof := Color(0.72, 0.5, 0.18)
	flat(-28.0, 28.0, -96.0, -71.0, 0.05, Color(0.55, 0.55, 0.58))

	# keep
	block(Vector3(0, 9, -86), Vector3(18, 18, 10), stone)
	block(Vector3(0, 19.5, -86), Vector3(12, 3, 8), roof)
	block(Vector3(0, 22, -86), Vector3(6, 2, 5), roof)
	block(Vector3(0, 3, -80.9), Vector3(4, 6, 0.3), Color(0.25, 0.15, 0.1), false)

	# corner towers
	for sx in [-11.0, 11.0]:
		block(Vector3(sx, 12, -86), Vector3(5, 24, 5), dark)
		block(Vector3(sx, 25, -86), Vector3(6.4, 3, 6.4), roof)
		block(Vector3(sx, 27.5, -86), Vector3(3, 2, 3), Color(0.8, 0.2, 0.2))
		_flag(Vector3(sx, 28.5, -86))

	# gate towers, lintel, walls
	for sx in [-6.0, 6.0]:
		block(Vector3(sx, 7, -70), Vector3(4.5, 14, 4.5), dark)
		block(Vector3(sx, 14.8, -70), Vector3(5.5, 1.6, 5.5), roof)
		_flag(Vector3(sx, 15.6, -70))
	block(Vector3(0, 12.5, -70), Vector3(8, 3, 2), dark)
	for sx in [-17.5, 17.5]:
		block(Vector3(sx, 4, -70), Vector3(21, 8, 2), stone)
		for i in 8:
			block(Vector3(sx - 9.0 + i * 2.6, 8.6, -70), Vector3(1.6, 1.2, 2), stone, false)
	for sx in [-28.0, 28.0]:
		block(Vector3(sx, 4, -83), Vector3(2, 8, 26), stone)


func _house(p: Vector2) -> void:
	var walls := [Color(0.85, 0.7, 0.45), Color(0.78, 0.6, 0.4), Color(0.9, 0.8, 0.6)]
	var w: Color = walls[rng.randi() % walls.size()]
	var roof := Color(0.6, 0.28, 0.18)
	block(Vector3(p.x, 1.8, p.y), Vector3(5, 3.6, 5), w)
	block(Vector3(p.x, 4.3, p.y), Vector3(6, 1.4, 6), roof, false)
	block(Vector3(p.x, 5.5, p.y), Vector3(4, 1.2, 4), roof, false)
	block(Vector3(p.x, 1.0, p.y + 2.55), Vector3(1.2, 2.0, 0.2), Color(0.3, 0.18, 0.1), false)
	block(Vector3(p.x - 1.5, 2.3, p.y + 2.55), Vector3(0.9, 0.9, 0.2), Color(0.6, 0.85, 1.0), false)
	block(Vector3(p.x + 1.5, 2.3, p.y + 2.55), Vector3(0.9, 0.9, 0.2), Color(0.6, 0.85, 1.0), false)


func _build_village() -> void:
	var spots := [
		Vector2(-12, -46), Vector2(-18, -54), Vector2(-12, -62),
		Vector2(12, -46), Vector2(19, -52), Vector2(12, -60), Vector2(23, -64),
		Vector2(-19, -64),
	]
	for s in spots:
		_house(s)


func _build_minigames_building() -> void:
	var c := Vector3(10, 0, -26)
	block(c + Vector3(0, 6, 0), Vector3(11, 12, 8), Color(0.33, 0.27, 0.78))
	for i in 3:
		block(c + Vector3(0, 2.5 + i * 4.0, 0), Vector3(11.2, 1.2, 8.2), Color(0.98, 0.85, 0.2), false)
	block(c + Vector3(0, 8.5, 4.2), Vector3(9, 2, 0.4), Color(0.1, 0.6, 0.45), false)
	label3d(c + Vector3(0, 8.5, 4.5), "MINIGAMES", 0.02)
	block(c + Vector3(0, 1.8, 4.05), Vector3(3, 3.6, 0.2), Color(0.12, 0.08, 0.2), false)

	# glowing start pad
	var pad := flat(MINI_PAD.x - 2.5, MINI_PAD.x + 2.5, MINI_PAD.z - 2.5, MINI_PAD.z + 2.5, 0.08, Color(1.0, 0.85, 0.2))
	pad_mat = StandardMaterial3D.new()
	pad_mat.albedo_color = Color(1.0, 0.85, 0.2)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color(1.0, 0.7, 0.1)
	pad_mat.emission_energy_multiplier = 1.0
	pad.material_override = pad_mat
	pad_gem = block(MINI_PAD + Vector3(0, 2.2, 0), Vector3(0.9, 0.9, 0.9), Color(1.0, 0.8, 0.1), false)
	label3d(MINI_PAD + Vector3(0, 3.6, 0), "CHOOSE A GAME", 0.012, Color(1, 1, 1), true)

	# arcade building + colorful block stack (decor)
	var a := Vector3(-12, 0, -26)
	block(a + Vector3(0, 5.5, 0), Vector3(10, 11, 8), Color(0.82, 0.42, 0.18))
	block(a + Vector3(0, 7.5, 0), Vector3(10.2, 2.2, 8.2), Color(0.55, 0.3, 0.7), false)
	block(a + Vector3(0, 1.6, 4.05), Vector3(2.6, 3.2, 0.2), Color(0.2, 0.12, 0.08), false)
	var stack := [Color(0.95, 0.85, 0.1), Color(0.2, 0.5, 0.9), Color(0.3, 0.75, 0.3),
		Color(0.95, 0.5, 0.15), Color(0.85, 0.2, 0.2)]
	for i in stack.size():
		var sc: Color = stack[i]
		block(Vector3(-19 + (i % 2) * 0.6, 1.5 + i * 3.0, -24), Vector3(3, 3, 3), sc)


func _build_signs_and_chill() -> void:
	var sp := Vector3(6.5, 0, 24)
	block(sp + Vector3(0, 2.2, 0), Vector3(0.35, 4.4, 0.35), Color(0.22, 0.22, 0.25))
	block(sp + Vector3(0, 3.6, 0.25), Vector3(4.6, 1.0, 0.25), Color(0.6, 0.38, 0.15), false)
	label3d(sp + Vector3(0, 3.6, 0.4), "MINIGAMES", 0.009)
	block(sp + Vector3(0, 2.3, 0.25), Vector3(4.6, 1.0, 0.25), Color(0.2, 0.35, 0.5), false)
	label3d(sp + Vector3(0, 2.3, 0.4), "CHILL ZONE", 0.009)

	# chill zone: pond, bench, lantern, flowers
	flat(-13.0, -5.0, 16.0, 24.0, 0.045, Color(0.5, 0.78, 0.3))
	flat(-12.0, -8.5, 17.0, 20.0, 0.07, Color(0.2, 0.4, 0.85))
	var wood := Color(0.55, 0.36, 0.18)
	block(Vector3(-7.5, 0.7, 22.0), Vector3(2.6, 0.3, 0.9), wood)
	block(Vector3(-7.5, 1.3, 22.4), Vector3(2.6, 0.9, 0.2), wood, false)
	block(Vector3(-8.6, 0.3, 22.0), Vector3(0.2, 0.6, 0.7), wood, false)
	block(Vector3(-6.4, 0.3, 22.0), Vector3(0.2, 0.6, 0.7), wood, false)
	block(Vector3(-5.8, 1.5, 17.5), Vector3(0.25, 3.0, 0.25), Color(0.2, 0.2, 0.22))
	var lamp := block(Vector3(-5.8, 3.2, 17.5), Vector3(0.7, 0.7, 0.7), Color(1.0, 0.9, 0.4), false)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1.0, 0.9, 0.4)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.85, 0.3)
	lamp.material_override = lm
	label3d(Vector3(-9, 5.0, 20), "CHILL ZONE", 0.012, Color(0.8, 1.0, 0.9), true)


func _build_windmill() -> void:
	var p := Vector3(20, 0, -32)
	block(p + Vector3(0, 4.5, 0), Vector3(4.5, 9, 4.5), Color(0.88, 0.78, 0.6))
	block(p + Vector3(0, 9.7, 0), Vector3(5.4, 1.4, 5.4), Color(0.6, 0.28, 0.18), false)
	block(p + Vector3(0, 1.2, 2.3), Vector3(1.2, 2.4, 0.2), Color(0.3, 0.18, 0.1), false)
	blades = Node3D.new()
	blades.position = p + Vector3(0, 7.5, 2.6)
	world_root.add_child(blades)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = i * PI * 0.5
		blades.add_child(arm)
		block(Vector3(0, 2.6, 0), Vector3(0.5, 5.2, 0.2), Color(0.45, 0.3, 0.15), false, arm)
		block(Vector3(0.7, 3.4, 0), Vector3(1.2, 3.2, 0.12), Color(0.96, 0.94, 0.88), false, arm)
	block(Vector3.ZERO, Vector3(0.9, 0.9, 0.9), Color(0.35, 0.22, 0.12), false, blades)


func _make_tree(x: float, z: float) -> void:
	var h := rng.randf_range(3.0, 4.6)
	var greens := [Color(0.2, 0.55, 0.15), Color(0.25, 0.62, 0.18), Color(0.16, 0.47, 0.13)]
	var g: Color = greens[rng.randi() % greens.size()]
	block(Vector3(x, h * 0.5, z), Vector3(0.9, h, 0.9), Color(0.4, 0.26, 0.13))
	block(Vector3(x, h + 1.6, z), Vector3(4.2, 3.6, 4.2), g, false)
	block(Vector3(x + rng.randf_range(-0.6, 0.6), h + 4.0, z + rng.randf_range(-0.6, 0.6)),
		Vector3(3.0, 2.4, 3.0), g.lightened(0.08), false)


func _build_trees() -> void:
	var placed := 0
	var tries := 0
	while placed < 60 and tries < 600:
		tries += 1
		var x := rng.randf_range(-90.0, 90.0)
		var z := rng.randf_range(-90.0, 60.0)
		if _is_blocked(x, z):
			continue
		_make_tree(x, z)
		placed += 1


func _build_flowers() -> void:
	var heads := [Color(0.95, 0.2, 0.2), Color(1.0, 0.85, 0.1), Color(0.97, 0.97, 0.97), Color(1.0, 0.55, 0.15)]
	var placed := 0
	var tries := 0
	while placed < 45 and tries < 300:
		tries += 1
		var x := rng.randf_range(-14.0, 14.0)
		var z := rng.randf_range(-60.0, 46.0)
		if absf(x) < 3.6:
			continue
		var hc: Color = heads[rng.randi() % heads.size()]
		block(Vector3(x, 0.3, z), Vector3(0.12, 0.6, 0.12), Color(0.15, 0.5, 0.15), false)
		block(Vector3(x, 0.72, z), Vector3(0.45, 0.35, 0.45), hc, false)
		placed += 1


func _build_clouds() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 12:
		var cloud := Node3D.new()
		cloud.position = Vector3(rng.randf_range(-150, 150), rng.randf_range(55, 85), rng.randf_range(-150, 50))
		for j in 3:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(rng.randf_range(14, 28), 3.0, rng.randf_range(8, 14))
			mi.mesh = bm
			mi.material_override = m
			mi.position = Vector3(rng.randf_range(-8, 8), rng.randf_range(-1, 1), rng.randf_range(-5, 5))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(mi)
		add_child(cloud)
		clouds.append(cloud)


# ------------------------------------------------------------ actors / camera

func _spawn_player() -> void:
	player = PlayerScript.new()
	player.position = START_POS
	add_child(player)
	player.model.rotation.y = PI # face away from the camera at start


func _spawn_camera() -> void:
	cam_pivot = Node3D.new()
	cam_pivot.position = START_POS + Vector3(0, 1.7, 0)
	add_child(cam_pivot)
	cam_arm = SpringArm3D.new()
	cam_arm.spring_length = 9.0
	cam_arm.margin = 0.4
	cam_arm.collision_mask = 1
	cam_arm.rotation.x = cam_pitch
	cam_pivot.add_child(cam_arm)
	cam_arm.add_excluded_object(player.get_rid())
	cam = Camera3D.new()
	cam.fov = BASE_FOV
	cam.near = 0.3
	cam.far = 500.0
	cam_arm.add_child(cam)
	cam.current = true


func _spawn_npcs() -> void:
	var defs := [
		{"shirt": Color(0.1, 0.1, 0.12), "pants": Color(0.1, 0.1, 0.12), "skin": Color(0.95, 0.93, 0.9),
			"hair": Color(0.75, 0.4, 0.2), "region": Rect2(-6, -45, 12, 50), "sword": false},
		{"shirt": Color(0.25, 0.4, 0.75), "pants": Color(0.45, 0.4, 0.3), "skin": Color(0.9, 0.75, 0.6),
			"hair": Color(0.15, 0.15, 0.3), "region": Rect2(-6, -45, 12, 50), "sword": true},
		{"shirt": Color(0.85, 0.3, 0.5), "pants": Color(0.3, 0.3, 0.6), "skin": Color(0.98, 0.83, 0.1),
			"hair": Color(0.4, 0.2, 0.1), "region": Rect2(-12, 17, 7, 6), "sword": false},
		{"shirt": Color(0.9, 0.7, 0.2), "pants": Color(0.5, 0.35, 0.2), "skin": Color(0.8, 0.6, 0.45),
			"hair": Color(0.1, 0.1, 0.1), "region": Rect2(30, -6, 14, 26), "sword": false},
		{"shirt": Color(0.3, 0.6, 0.35), "pants": Color(0.25, 0.25, 0.3), "skin": Color(0.98, 0.83, 0.1),
			"hair": Color(0.2, 0.2, 0.2), "region": Rect2(-6, -66, 12, 16), "sword": true},
	]
	for d in defs:
		var n := BlockyScript.new()
		n.build(d["skin"], d["shirt"], d["skin"], d["skin"], d["pants"], d["pants"], d["hair"], d["sword"])
		var region: Rect2 = d["region"]
		n.position = _rand_in(region)
		add_child(n)
		npcs.append({"node": n, "target": _rand_in(region), "wait": rng.randf_range(0.0, 2.0), "region": region})


func _spawn_coin(pos: Vector3, mini: bool = false) -> void:
	var holder := Node3D.new()
	holder.position = pos
	var mi := MeshInstance3D.new()
	mi.mesh = _coin_rim_mesh
	mi.rotation_degrees.x = 90.0
	mi.material_override = coin_rim_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	var face := MeshInstance3D.new()
	face.mesh = _coin_face_mesh
	face.material_override = coin_mat
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(face)
	var gem := MeshInstance3D.new()
	gem.mesh = _coin_gem_mesh
	gem.rotation_degrees.y = 45.0
	gem.material_override = coin_gem_mat
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(gem)
	holder.set_meta("mini", mini)
	holder.set_meta("y0", pos.y)
	world_root.add_child(holder)
	coins.append(holder)


func _spawn_start_coins() -> void:
	for i in 30:
		_spawn_coin(Vector3(rng.randf_range(-3.5, 3.5), 1.3, rng.randf_range(-62.0, 44.0)))
	for i in 10:
		_spawn_coin(Vector3(rng.randf_range(30.0, 44.0), 1.3, rng.randf_range(0.0, 20.0)))
	for i in 8:
		_spawn_coin(Vector3(rng.randf_range(-22.0, -17.0), 1.3, rng.randf_range(-10.0, 40.0)))


# -------------------------------------------------------------------- HUD

func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _center_top(l: Label, top: float) -> void:
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 0.0
	l.anchor_bottom = 0.0
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.offset_top = top


func _build_hud() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	score_label = _make_label(40)
	score_label.position = Vector2(70, 24)
	ui.add_child(score_label)

	info_label = _make_label(34)
	_center_top(info_label, 24.0)
	ui.add_child(info_label)

	toast_label = _make_label(32)
	_center_top(toast_label, 110.0)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.modulate.a = 0.0
	ui.add_child(toast_label)

	controls = ControlsScript.new()
	ui.add_child(controls)
	controls.jump_pressed.connect(_on_jump)
	controls.wave_pressed.connect(_on_wave)
	controls.dance_pressed.connect(_on_dance)
	controls.shadows_pressed.connect(_on_shadows)
	controls.lock_pressed.connect(_toggle_shift_lock)
	controls.game_chosen.connect(_on_game_chosen)
	controls.leave_pressed.connect(_leave_parkour)
	controls.home_pressed.connect(_on_home)
	controls.chat_pressed.connect(_open_chat)
	controls.chat_send_pressed.connect(_submit_chat)
	controls.chat_cancel_pressed.connect(_close_chat)

	# the chat text box is a real LineEdit (so phones get their keyboard);
	# it stays hidden until the chat button / Enter is pressed
	chat_edit = LineEdit.new()
	chat_edit.visible = false
	chat_edit.max_length = 120
	chat_edit.context_menu_enabled = false
	chat_edit.placeholder_text = "اكتب رسالة..." if Customization.lang == "ar" else "Say something..."
	chat_edit.add_theme_font_size_override("font_size", 24)
	chat_edit.add_theme_color_override("font_color", Color(1, 1, 1))
	chat_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.5))
	chat_edit.add_theme_color_override("caret_color", Color(1, 1, 1))
	var no_box := StyleBoxEmpty.new()
	chat_edit.add_theme_stylebox_override("normal", no_box)
	chat_edit.add_theme_stylebox_override("focus", no_box)
	chat_edit.text_submitted.connect(_on_chat_submitted)
	ui.add_child(chat_edit)


func toast(msg: String, secs: float = 2.5) -> void:
	toast_label.text = msg
	toast_label.modulate.a = 1.0
	if toast_tween != null and toast_tween.is_valid():
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(secs)
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)


func _update_hud() -> void:
	score_label.text = "Coins: %d" % score
	if game_active:
		var streak := ""
		if combo >= 2 and time_acc - last_collect_t <= COMBO_WINDOW:
			streak = "   x%d" % combo
		info_label.text = "COIN RUSH   %d s   +%d%s" % [int(ceil(game_time)), game_coins, streak]
	elif game_mode == "parkour":
		info_label.text = "PARKOUR   %.1f s" % parkour_time
	elif best > 0:
		info_label.text = "Best Rush: %d" % best
	else:
		info_label.text = ""


# ------------------------------------------------------------------ audio

func _make_tone(freqs: Array, dur: float, vol: float = 0.35) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var f: float = freqs[int(float(i) / n * freqs.size())]
		var env := 1.0 - float(i) / n
		var v := int(sin(TAU * f * float(i) / rate) * env * vol * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func _setup_audio() -> void:
	snd_coin = AudioStreamPlayer.new()
	snd_coin.stream = _make_tone([988.0, 1319.0], 0.16)
	add_child(snd_coin)
	snd_jump = AudioStreamPlayer.new()
	snd_jump.stream = _make_tone([330.0, 440.0], 0.12, 0.25)
	add_child(snd_jump)
	snd_land = AudioStreamPlayer.new()
	snd_land.stream = _make_tone([150.0, 110.0], 0.12, 0.3)
	add_child(snd_land)


# ---------------------------------------------------------------- save/load

func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://save.cfg") == OK:
		best = int(cfg.get_value("game", "best", 0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "best", best)
	cfg.save("user://save.cfg")


# ------------------------------------------------------------------ input

func _on_jump() -> void:
	if player.is_on_floor():
		snd_jump.play()
	player.want_jump = true


func _on_wave() -> void:
	player.model.wave()


# ------------------------------------------------------------------- chat

func _open_chat() -> void:
	if chat_open or not online.is_online():
		return
	chat_open = true
	controls.chat_open = true
	controls.reset_touches()
	var r: Rect2 = controls.chat_edit_rect()
	chat_edit.position = r.position
	chat_edit.size = r.size
	chat_edit.text = ""
	chat_edit.visible = true
	chat_edit.grab_focus() # on phones this also raises the keyboard


func _close_chat() -> void:
	if not chat_open:
		return
	chat_open = false
	controls.chat_open = false
	chat_edit.release_focus()
	chat_edit.visible = false
	DisplayServer.virtual_keyboard_hide()


func _submit_chat() -> void:
	_on_chat_submitted(chat_edit.text)


func _on_chat_submitted(text: String) -> void:
	online.say(text)
	_close_chat()


func _input(event: InputEvent) -> void:
	# Esc closes the chat box (before the text box can swallow it)
	if chat_open and event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled()


## DANCE button / G key: play the dance equipped in the Customize screen.
## Tapping again (or moving / jumping) stops it.
func _on_dance() -> void:
	if player.model.is_dancing():
		player.model.stop_dance()
		return
	if not player.is_on_floor():
		return
	player.model.play_dance(Customization.dance_id())
	toast("%s  —  move to stop" % Customization.dance_name(), 1.4)


func _on_player_landed(fall_speed: float) -> void:
	# a soft thud only for real drops, not tiny steps
	if fall_speed > 10.5:
		snd_land.play()


func _on_shadows() -> void:
	sun.shadow_enabled = not sun.shadow_enabled
	toast("Shadows " + ("ON" if sun.shadow_enabled else "OFF"), 1.5)


func _on_home() -> void:
	Net.leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://home.tscn")


func _toggle_shift_lock() -> void:
	shift_lock_enabled = not shift_lock_enabled
	player.shift_lock = shift_lock_enabled
	controls.set_lock_state(shift_lock_enabled)
	if OS.has_feature("pc"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if shift_lock_enabled else Input.MOUSE_MODE_VISIBLE
	toast("Shift Lock " + ("ON — mouse always steers the camera" if shift_lock_enabled else "OFF"), 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode == KEY_SPACE:
				_on_jump()
			elif k.keycode == KEY_F:
				_on_wave()
			elif k.keycode == KEY_G:
				_on_dance()
			elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
				_open_chat()
			elif k.keycode == KEY_SHIFT:
				_toggle_shift_lock()
			elif k.keycode == KEY_ESCAPE and shift_lock_enabled:
				_toggle_shift_lock()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		cam_yaw -= mm.relative.x * 0.006
		cam_pitch = clampf(cam_pitch - mm.relative.y * 0.004, -1.25, -0.12)


# ------------------------------------------------------------- minigames

func _rand_arena() -> Vector3:
	return Vector3(rng.randf_range(-13.0, 13.0), 1.3, rng.randf_range(-13.0, 11.0))


func _on_game_chosen(mode: String) -> void:
	if mode == "coinrush":
		_start_game()
	elif mode == "parkour":
		_start_parkour()


func _start_game() -> void:
	game_mode = "coinrush"
	game_active = true
	game_time = GAME_LENGTH
	game_coins = 0
	combo = 0
	last_collect_t = -10.0
	pad_armed = false
	for i in 14:
		_spawn_coin(_rand_arena(), true)
	toast("COIN RUSH!  Grab as many coins as you can!", 3.0)


func _end_game() -> void:
	game_active = false
	game_mode = "none"
	for i in range(coins.size() - 1, -1, -1):
		if coins[i].get_meta("mini"):
			coins[i].queue_free()
			coins.remove_at(i)
	if game_coins > best:
		best = game_coins
		_save_best()
		toast("NEW RECORD!  %d coins" % game_coins, 4.5)
	else:
		toast("Time's up!  %d coins  (best %d)" % [game_coins, best], 4.5)


# ------------------------------------------------------------- parkour

func _world_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [node]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is VisualInstance3D:
			var local_aabb: AABB = n.get_aabb()
			var gt: Transform3D = n.global_transform
			for i in 8:
				var corner := Vector3(
					local_aabb.position.x if (i & 1) == 0 else local_aabb.end.x,
					local_aabb.position.y if (i & 2) == 0 else local_aabb.end.y,
					local_aabb.position.z if (i & 4) == 0 else local_aabb.end.z)
				var wp: Vector3 = gt * corner
				if first:
					result = AABB(wp, Vector3.ZERO)
					first = false
				else:
					result = result.expand(wp)
		for c in n.get_children():
			stack.append(c)
	return result


func _add_trimesh_collision(node: Node) -> void:
	var stack: Array = [node]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			n.create_trimesh_collision()
		for c in n.get_children():
			stack.append(c)


func _build_parkour_world() -> void:
	if not ResourceLoader.exists(PARKOUR_ASSET):
		push_warning("Parkour asset not found (open the project in Godot once to import it): " + PARKOUR_ASSET)
		return
	var scene: PackedScene = load(PARKOUR_ASSET)
	if scene == null:
		return
	parkour_root = Node3D.new()
	parkour_root.name = "ParkourWorld"
	add_child(parkour_root)
	var inst := scene.instantiate()
	parkour_root.add_child(inst)
	_add_trimesh_collision(inst)

	var aabb := _world_aabb(inst)
	if aabb.size == Vector3.ZERO:
		aabb = AABB(Vector3(-10, 0, -10), Vector3(20, 20, 20))
	# Tuck the whole course well away from the main map so the two never overlap.
	var far := Vector3(400.0, 0.0, 0.0)
	parkour_root.position += far - Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)

	aabb = _world_aabb(inst) # recompute now that the root has moved
	parkour_aabb = aabb
	parkour_spawn = Vector3(aabb.get_center().x, aabb.end.y + 3.0, aabb.get_center().z)
	parkour_fall_y = aabb.position.y - 20.0
	parkour_bounds_limit = maxf(aabb.size.x, aabb.size.z) * 0.5 + 20.0


func _start_parkour() -> void:
	if parkour_root == null:
		toast("Parkour course isn't loaded — open the project in Godot once so it can import.", 4.0)
		return
	game_mode = "parkour"
	parkour_time = 0.0
	player.bounds_center = Vector2(parkour_aabb.get_center().x, parkour_aabb.get_center().z)
	player.bounds_limit = parkour_bounds_limit
	player.respawn_pos = parkour_spawn
	player.fall_y = parkour_fall_y
	player.position = parkour_spawn
	player.velocity = Vector3.ZERO
	controls.set_parkour_active(true)
	toast("PARKOUR!  Climb the course — fall off and you'll respawn.", 3.5)


func _leave_parkour() -> void:
	game_mode = "none"
	controls.set_parkour_active(false)
	player.bounds_center = Vector2(0.0, 0.0)
	player.bounds_limit = WORLD_BOUNDS_LIMIT
	player.respawn_pos = WORLD_RESPAWN
	player.fall_y = -20.0
	player.position = MINI_PAD + Vector3(0.0, 1.0, 6.0)
	player.velocity = Vector3.ZERO
	pad_armed = false
	toast("Back from Parkour!  %.1f s" % parkour_time, 2.5)


# --------------------------------------------------------- community level

## Builds a level published from the Studio, purely from its JSON data (see
## studio.gd's _level_dict()) — never as code, so nothing in `level` can do
## anything beyond placing the handful of block kinds and running the
## handful of level_script.gd actions handled in _run_level_action below.
func _build_community_level(level: Dictionary) -> void:
	var meta: Dictionary = level.get("meta", {})
	var data: Dictionary = level.get("data", {})
	community_title = String(meta.get("title", "Level"))
	community_author = String(meta.get("author", "?"))
	community_speed_mult = clampf(float(data.get("speed_mult", 1.0)), 0.5, 2.0)
	community_jump_mult = clampf(float(data.get("jump_mult", 1.0)), 0.5, 2.0)
	community_grid_n = clampi(int(data.get("n", 16)), 4, 64)
	community_finishes.clear()
	community_triggers.clear()
	community_timers.clear()

	community_root = Node3D.new()
	community_root.name = "CommunityLevel"
	add_child(community_root)

	var cell := COMMUNITY_CELL
	var n := community_grid_n
	var origin := COMMUNITY_ORIGIN - Vector3(float(n) * cell * 0.5, 0.0, float(n) * cell * 0.5)
	var ground_size := float(n) * cell + 14.0
	block(COMMUNITY_ORIGIN - Vector3(0.0, 1.0, 0.0), Vector3(ground_size, 2.0, ground_size),
		Color(0.30, 0.55, 0.30), true, community_root)

	community_spawn = COMMUNITY_ORIGIN + Vector3(0.0, 1.0, 0.0) # used if the level has no Start (shouldn't happen)
	for c in data.get("cells", []):
		var gx := int(c.get("x", 0))
		var gy := int(c.get("y", 0))
		var t := String(c.get("t", ""))
		var wp: Vector3 = origin + Vector3((float(gx) + 0.5) * cell, 0.0, (float(gy) + 0.5) * cell)
		match t:
			"platform":
				var h := float(clampi(int(c.get("h", 1)), 1, 4))
				block(wp + Vector3(0.0, h - 0.2, 0.0), Vector3(cell - 0.1, 0.4, cell - 0.1),
					Color(0.62, 0.66, 0.72), true, community_root)
			"wall":
				var h2 := float(clampi(int(c.get("h", 1)), 1, 4))
				block(wp + Vector3(0.0, h2 * 0.5, 0.0), Vector3(cell - 0.1, h2, cell - 0.1),
					Color(0.36, 0.40, 0.45), true, community_root)
			"ramp":
				_build_ramp(wp, int(c.get("r", 0)) % 4, cell)
			"coin":
				_spawn_coin(wp + Vector3(0.0, 1.2, 0.0)) # lives under world_root, like any other coin
			"start":
				community_spawn = wp + Vector3(0.0, 1.0, 0.0)
			"finish":
				flat(wp.x - cell * 0.4, wp.x + cell * 0.4, wp.z - cell * 0.4, wp.z + cell * 0.4, 0.05, Color(0.85, 0.25, 0.2))
				community_finishes.append(Vector2(wp.x, wp.z))
			"bounce":
				_pad(wp, cell, Color(0.18, 0.75, 0.85))
				community_triggers.append({"pos": Vector2(wp.x, wp.z), "actions": [{"op": "bounce"}], "armed": true})
			"speed":
				_pad(wp, cell, Color(1.0, 0.55, 0.25))
				community_triggers.append({"pos": Vector2(wp.x, wp.z), "actions": [{"op": "speed", "mult": 1.6, "secs": 3.0}], "armed": true})
			"trigger":
				var parsed := LevelScript.parse(String(c.get("s", "")))
				var mk := block(wp + Vector3(0.0, 0.55, 0.0), Vector3(cell * 0.5, 1.1, cell * 0.5),
					Color(0.48, 0.36, 1.0), false, community_root)
				mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if parsed["touch"].size() > 0:
					community_triggers.append({"pos": Vector2(wp.x, wp.z), "actions": parsed["touch"], "armed": true})
				for te in parsed["timers"]:
					community_timers.append({"t": float(te["t"]), "action": te["action"], "fired": false})

	community_bounds_limit = float(n) * cell * 0.5 + 14.0


## A flat, glowing, non-colliding pad — the visual for Bounce Pad / Speed Pad.
## Its own material (not the shared mat() cache other blocks use), since it
## needs emission glow that shouldn't leak onto anything else that colour.
func _pad(wp: Vector3, cell: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(cell * 0.84, 0.08, cell * 0.84)
	mi.mesh = bm
	mi.position = wp + Vector3(0.0, 0.04, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.9
	mi.material_override = m
	community_root.add_child(mi)


## A simple ramp: a tilted box climbing 1 unit across one grid cell. `r`
## (0..3) picks which side is the low edge. The tilt sign is my best
## reading of Godot's rotation convention — since I can't run the editor
## myself, open the Studio and check a ramp climbs the way its arrow points;
## if any direction is backwards, flip the sign on the `-angle` below.
func _build_ramp(center: Vector3, r: int, cell: float) -> void:
	var rise := 1.0
	var slope_len := sqrt(cell * cell + rise * rise)
	var angle := atan2(rise, cell)
	var holder := Node3D.new()
	holder.position = center
	holder.rotation.y = float(r) * PI * 0.5
	community_root.add_child(holder)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(cell - 0.1, 0.25, slope_len)
	mi.mesh = bm
	mi.material_override = mat(Color(0.55, 0.42, 0.28))
	mi.transform = Transform3D(Basis(Vector3(1.0, 0.0, 0.0), -angle), Vector3(0.0, rise * 0.5, 0.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)

	var body := StaticBody3D.new()
	body.transform = mi.transform
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	body.add_child(cs)
	holder.add_child(body)


func _start_community() -> void:
	game_mode = "community"
	community_time = 0.0
	community_ended = false
	_temp_speed_until = 0.0
	for t in community_triggers:
		t["armed"] = true
	for te in community_timers:
		te["fired"] = false
	player.bounds_center = Vector2(COMMUNITY_ORIGIN.x, COMMUNITY_ORIGIN.z)
	player.bounds_limit = community_bounds_limit
	player.respawn_pos = community_spawn
	player.fall_y = COMMUNITY_ORIGIN.y - 20.0
	player.position = community_spawn
	player.velocity = Vector3.ZERO
	player.speed_mult = community_speed_mult
	player.jump_mult = community_jump_mult
	toast("%s  —  %s %s" % [community_title, ("by" if Customization.lang != "ar" else "بواسطة"), community_author], 3.5)


func _community_win() -> void:
	if community_ended:
		return
	community_ended = true
	_add_coins(10)
	toast(("🏁 You made it!  +10 coins" if Customization.lang != "ar" else "🏁 وصلت! +10 عملات"), 3.0)


## Runs one action from a trigger / timer's script — see level_script.gd for
## the fixed, whitelisted set this can ever be. `op` values other than the
## ones below (there are none) are simply ignored.
func _run_level_action(action: Dictionary) -> void:
	match String(action.get("op", "")):
		"give_coins":
			var n := int(action.get("n", 1))
			_add_coins(n)
			toast("+%d" % n, 1.2)
		"lose_coins":
			var n2 := int(action.get("n", 1))
			Customization.add_coins(-n2)
			score = Customization.coins
			toast("-%d" % n2, 1.2)
		"win":
			_community_win()
		"lose":
			player.position = community_spawn
			player.velocity = Vector3.ZERO
			toast(("Try again!" if Customization.lang != "ar" else "حاول مرة ثانية!"), 1.4)
		"message":
			toast(String(action.get("text", "")), 2.4)
		"teleport":
			var n3 := community_grid_n
			var origin2 := COMMUNITY_ORIGIN - Vector3(float(n3) * COMMUNITY_CELL * 0.5, 0.0, float(n3) * COMMUNITY_CELL * 0.5)
			player.position = origin2 + Vector3(
				(float(action.get("gx", 0.0)) + 0.5) * COMMUNITY_CELL, 1.0,
				(float(action.get("gy", 0.0)) + 0.5) * COMMUNITY_CELL)
			player.velocity = Vector3.ZERO
		"speed":
			player.speed_mult = community_speed_mult * float(action.get("mult", 1.0))
			_temp_speed_until = community_time + float(action.get("secs", 2.0))
		"bounce":
			player.velocity.y = PlayerScript.JUMP_VELOCITY * community_jump_mult * 1.6


func _update_community(delta: float) -> void:
	community_time += delta
	if community_time >= _temp_speed_until and not is_equal_approx(player.speed_mult, community_speed_mult):
		player.speed_mult = community_speed_mult

	for te in community_timers:
		if not te["fired"] and community_time >= float(te["t"]):
			te["fired"] = true
			_run_level_action(te["action"])

	var pxz := Vector2(player.position.x, player.position.z)
	for t in community_triggers:
		var d: float = pxz.distance_to(t["pos"])
		if d < 1.8 and t["armed"]:
			t["armed"] = false
			for a in t["actions"]:
				_run_level_action(a)
		elif d > 2.6:
			t["armed"] = true

	if not community_ended:
		for f in community_finishes:
			if pxz.distance_to(f) < 1.8:
				_community_win()
				break


## Every coin you earn is saved right away (Customization keeps the wallet).
func _add_coins(n: int) -> void:
	Customization.add_coins(n)
	score = Customization.coins


func _coin_burst(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 180.0
	p.gravity = Vector3(0.0, -12.0, 0.0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.16)
	bm.material = coin_mat
	p.mesh = bm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	world_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func _collect(i: int) -> void:
	var c := coins[i]
	var was_mini: bool = c.get_meta("mini")
	_coin_burst(c.position)
	c.queue_free()
	coins.remove_at(i)
	_add_coins(1)
	snd_coin.play()
	if game_active and was_mini:
		# streak: grab the next coin quickly to keep it going
		if time_acc - last_collect_t <= COMBO_WINDOW:
			combo += 1
		else:
			combo = 1
		last_collect_t = time_acc
		game_coins += 1
		if combo % 5 == 0:
			game_time += COMBO_BONUS
			toast("COMBO x%d!  +%d s" % [combo, int(COMBO_BONUS)], 1.5)
		_spawn_coin(_rand_arena(), true)


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	time_acc += delta

	# camera look (drag on right half of the screen)
	var cd: Vector2 = controls.cam_delta
	controls.cam_delta = Vector2.ZERO
	cam_yaw -= cd.x * 0.006
	cam_pitch = clampf(cam_pitch - cd.y * 0.004, -1.25, -0.12)

	# movement input (joystick, or WASD/QE on desktop)
	var mv: Vector2 = controls.move_vec
	if OS.has_feature("pc") and not chat_open:
		var kv := Vector2(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		if kv != Vector2.ZERO:
			mv = kv.normalized()
		cam_yaw += (float(Input.is_key_pressed(KEY_Q)) - float(Input.is_key_pressed(KEY_E))) * 2.0 * delta
	var dir3: Vector3 = Basis(Vector3.UP, cam_yaw) * Vector3(mv.x, 0.0, mv.y)
	player.input_dir = dir3
	player.in_water = player.position.x > WATER_X0 and player.position.x < WATER_X1
	player.look_yaw = cam_yaw
	controls.dance_on = player.model.is_dancing()
	controls.shadows_on = sun.shadow_enabled
	controls.chat_available = online.is_online()
	controls.online_status = online.status
	online.tick(delta)

	# the view widens a touch when you run — a cheap but effective sense of speed
	var run_ratio := clampf(Vector2(player.velocity.x, player.velocity.z).length() / PlayerScript.SPEED, 0.0, 1.0)
	cam.fov = lerpf(cam.fov, BASE_FOV + 7.0 * run_ratio, clampf(delta * 4.0, 0.0, 1.0))

	cam_pivot.rotation.y = cam_yaw
	cam_arm.rotation.x = cam_pitch

	# world animation (the open world only — a community level has none of this)
	if game_mode != "community":
		blades.rotation.z += delta * 0.8
		for c in clouds:
			c.position.x += delta * 1.5
			if c.position.x > 170.0:
				c.position.x -= 340.0
		pad_mat.emission_energy_multiplier = 0.9 + 0.5 * sin(time_acc * 4.0)
		pad_gem.rotation.y += delta * 2.0
		pad_gem.position.y = 2.2 + sin(time_acc * 2.5) * 0.25
		_update_npcs(delta)

	# coins
	var pp: Vector3 = player.position + Vector3(0.0, 1.0, 0.0)
	for i in range(coins.size() - 1, -1, -1):
		var c := coins[i]
		c.rotation.y += delta * 3.0
		# coins bob gently, and drift toward you when you get close
		var y0: float = c.get_meta("y0")
		var base := Vector3(c.position.x, y0, c.position.z)
		var d := base.distance_to(pp)
		if d < MAGNET_RANGE:
			var pull := (pp - base).normalized() * (8.0 + 12.0 * (1.0 - d / MAGNET_RANGE)) * delta
			c.position.x += pull.x
			c.position.z += pull.z
			y0 += pull.y
			c.set_meta("y0", y0)
		c.position.y = y0 + sin(time_acc * 3.0 + c.position.x * 0.7) * 0.12
		if c.position.distance_to(pp) < 1.7:
			_collect(i)

	if game_mode == "community":
		_update_community(delta)
	else:
		# minigame pad — steps on it open a two-option choice, never auto-start
		var pad_dist := Vector2(player.position.x, player.position.z).distance_to(Vector2(MINI_PAD.x, MINI_PAD.z))
		if pad_dist > 5.0:
			if not pad_armed:
				pad_armed = true
			if controls.menu_open:
				controls.close_game_menu()
		elif pad_armed and pad_dist < 2.6 and game_mode == "none" and not chat_open:
			controls.open_game_menu()
			pad_armed = false
		if game_active:
			game_time -= delta
			if game_time <= 0.0:
				_end_game()
		elif game_mode == "parkour":
			parkour_time += delta

		# chill zone bonus: stand still for 3 seconds
		chill_cooldown = maxf(0.0, chill_cooldown - delta)
		var pxz := Vector2(player.position.x, player.position.z)
		if CHILL_RECT.has_point(pxz):
			var still := Vector2(player.velocity.x, player.velocity.z).length() < 0.5
			chill_timer = chill_timer + delta if still else 0.0
			if chill_timer >= 3.0 and chill_cooldown <= 0.0:
				_add_coins(5)
				chill_cooldown = 20.0
				chill_timer = 0.0
				toast("So relaxing...  +5 coins", 2.5)
		else:
			chill_timer = 0.0

	_update_hud()


func _physics_process(delta: float) -> void:
	if player == null or cam_pivot == null:
		return
	var target: Vector3 = player.position + Vector3(0.0, 1.7, 0.0)
	cam_pivot.position = cam_pivot.position.lerp(target, 1.0 - exp(-14.0 * delta))


func _update_npcs(delta: float) -> void:
	for npc in npcs:
		var n: Node3D = npc["node"]
		var moving := false
		if npc["wait"] > 0.0:
			npc["wait"] -= delta
			if npc["wait"] <= 0.0:
				n.stop_dance()
		else:
			var to: Vector3 = npc["target"] - n.position
			to.y = 0.0
			if to.length() < 0.4:
				npc["wait"] = rng.randf_range(1.5, 4.0)
				npc["target"] = _rand_in(npc["region"])
				# villagers sometimes break into a dance while they wait
				if rng.randf() < 0.35:
					var dd: Dictionary = Customization.DANCES[rng.randi() % Customization.DANCES.size()]
					n.play_dance(String(dd["id"]))
			else:
				var dir := to.normalized()
				n.position += dir * 2.4 * delta
				n.rotation.y = lerp_angle(n.rotation.y, atan2(dir.x, dir.z), 8.0 * delta)
				moving = true
		n.animate(delta, 0.45 if moving else 0.0, true)
