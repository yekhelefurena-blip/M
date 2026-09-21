extends Node3D
## Blocky character built from boxes, animated procedurally. Faces local +Z.
##
## Rig layout (so the body can bob, lean, twist and nod, not just swing limbs):
##   self
##    └ rig            bob / hip sway / squash & stretch
##        ├ upper      hips pivot: forward lean, twist, side roll
##        │   ├ torso
##        │   ├ head_pivot (neck): nod / turn / tilt  →  head (face + hair)
##        │   └ arm_a, arm_b   (shoulder pivots)
##        └ leg_a, leg_b       (hip pivots)
##
## Every frame animate() fills a *target pose* (idle / walk-run / jump-fall /
## landing / dance), then the real pose eases toward it. That easing is what
## makes transitions (stop, start, land, start dancing) look smooth.
##
## Each body part keeps its own material (head, torso, both arms, both legs)
## so the Customize screen (home.gd) can recolor them individually, even after
## the model has already been built and is being shown live in a preview.

# --- pose slots (indexes into the target / current pose arrays)
const P_ARM_A_X := 0  # shoulder swing (negative = forward)
const P_ARM_A_Z := 1  # arm out to the side (arm A: + is outward)
const P_ARM_B_X := 2
const P_ARM_B_Z := 3  # arm B: - is outward
const P_LEG_A_X := 4
const P_LEG_B_X := 5
const P_LEG_A_Z := 6
const P_LEG_B_Z := 7
const P_LEAN := 8     # upper body pitch (+ = forward)
const P_TWIST := 9    # upper body yaw
const P_ROLL := 10    # upper body side tilt
const P_HEAD_X := 11  # nod (+ = look down)
const P_HEAD_Y := 12  # turn
const P_HEAD_Z := 13  # tilt
const P_BOB := 14     # whole-body height offset
const P_SQUASH := 15  # + stretch / - squash
const P_SWAY := 16    # whole-body sideways shift (hips)
const P_COUNT := 17

## Robot dance: one snapped pose per step.
## [arm A x, arm A z, arm B x, arm B z, leg A x, leg B x, twist, head yaw, head pitch]
const ROBOT_POSES := [
	[0.0, 1.57, 0.0, -1.57, 0.0, 0.0, 0.0, 0.7, 0.0],
	[0.0, 3.14, 0.0, -0.25, 0.0, 0.0, 0.35, -0.7, -0.1],
	[-1.57, 0.12, -1.57, -0.12, -0.45, 0.0, 0.0, 0.0, 0.0],
	[-1.57, 0.12, 0.0, -1.57, 0.0, 0.0, -0.35, 0.6, 0.0],
	[0.0, 0.25, 0.0, -3.14, 0.0, 0.0, -0.35, 0.7, -0.1],
	[-1.57, 0.12, -1.57, -0.12, 0.0, -0.45, 0.0, 0.0, 0.0],
	[0.0, 0.9, 0.0, -0.9, 0.0, 0.0, 0.0, 0.0, 0.3],
	[0.0, 2.6, 0.0, -2.6, 0.0, 0.0, 0.0, 0.0, -0.3],
]

var rig: Node3D
var upper: Node3D
var head_pivot: Node3D

var arm_a: Node3D # +X side
var arm_b: Node3D # -X side (the waving arm)
var leg_a: Node3D
var leg_b: Node3D

var head_mesh: MeshInstance3D
var torso_mesh: MeshInstance3D
var arm_a_mesh: MeshInstance3D
var arm_b_mesh: MeshInstance3D
var leg_a_mesh: MeshInstance3D
var leg_b_mesh: MeshInstance3D

## "" = not dancing, otherwise "disco" / "floss" / "robot".
var dance_id := ""

## 0 = normal walk, 1 = Swagger Walk, 2 = Coin Runner (both bought in the Shop).
var walk_style := 0

var _aura: Node3D
var _aura_t := 0.0
var _aura_rings: Array = []      # MeshInstance3D x3 (rise and fade)
var _aura_ring_mats: Array = []  # their materials
var _aura_spark_mat: StandardMaterial3D
var _aura_sparks: CPUParticles3D
var _aura_light: OmniLight3D

var _eye_a: MeshInstance3D
var _eye_b: MeshInstance3D

var _pose := PackedFloat32Array()
var _tg := PackedFloat32Array()
var _phase := 0.0
var _t := 0.0
var _dance_t := 0.0
var _wave_left := 0.0
var _land := 0.0
var _was_air := false
var _air_vy := 0.0
var _last_yaw := 0.0
var _yaw_rate := 0.0
var _yaw_init := false
var _blink_in := 2.0
var _blink_left := 0.0


func _init() -> void:
	_pose.resize(P_COUNT)
	_tg.resize(P_COUNT)
	_blink_in = randf_range(1.0, 4.0)


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, unshaded: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Returns [pivot, mesh] — pivot is what animate() rotates, mesh is what
## set_part_color() recolors.
func _limb(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> Array:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	var mesh := _box(pivot, size, Vector3(0.0, -size.y * 0.5, 0.0), color)
	return [pivot, mesh]


## head_c/torso_c/arm colors/leg colors/hair_c are all independent so any
## body part can be recolored on its own later via set_part_color().
func build(head_c: Color, torso_c: Color, arm_a_c: Color, arm_b_c: Color, leg_a_c: Color, leg_b_c: Color, hair_c: Color, sword: bool = false) -> void:
	rig = Node3D.new()
	add_child(rig)

	# hips pivot: everything above the legs hangs off this
	upper = Node3D.new()
	upper.position = Vector3(0.0, 0.8, 0.0)
	rig.add_child(upper)

	# torso + small white badge
	torso_mesh = _box(upper, Vector3(0.8, 0.8, 0.42), Vector3(0.0, 0.4, 0.0), torso_c)
	_box(torso_mesh, Vector3(0.36, 0.09, 0.02), Vector3(0.0, 0.22, 0.22), Color(1, 1, 1), true)

	# neck pivot + head + face
	head_pivot = Node3D.new()
	head_pivot.position = Vector3(0.0, 0.8, 0.0)
	upper.add_child(head_pivot)
	head_mesh = _box(head_pivot, Vector3(0.46, 0.46, 0.46), Vector3(0.0, 0.24, 0.0), head_c)
	_eye_a = _box(head_mesh, Vector3(0.06, 0.09, 0.02), Vector3(-0.1, 0.05, 0.235), Color(0, 0, 0), true)
	_eye_b = _box(head_mesh, Vector3(0.06, 0.09, 0.02), Vector3(0.1, 0.05, 0.235), Color(0, 0, 0), true)
	var smile_y := [-0.08, -0.11, -0.12, -0.11, -0.08]
	for i in 5:
		var sy: float = smile_y[i]
		_box(head_mesh, Vector3(0.05, 0.035, 0.02), Vector3(-0.1 + i * 0.05, sy, 0.235), Color(0, 0, 0), true)

	# hair (kept fixed — not part of the Customize screen)
	_box(head_mesh, Vector3(0.5, 0.14, 0.5), Vector3(0.0, 0.28, 0.0), hair_c)
	_box(head_mesh, Vector3(0.5, 0.3, 0.1), Vector3(0.0, 0.1, -0.22), hair_c)
	_box(head_mesh, Vector3(0.06, 0.3, 0.4), Vector3(0.24, 0.12, -0.03), hair_c)
	_box(head_mesh, Vector3(0.06, 0.3, 0.4), Vector3(-0.24, 0.12, -0.03), hair_c)
	_box(head_mesh, Vector3(0.5, 0.1, 0.08), Vector3(0.0, 0.2, 0.23), hair_c)
	_box(head_mesh, Vector3(0.16, 0.12, 0.16), Vector3(-0.1, 0.4, 0.05), hair_c)

	# limbs (arms hang off the upper body, legs off the hips)
	var la := _limb(upper, Vector3(0.6, 0.78, 0.0), Vector3(0.4, 0.8, 0.4), arm_a_c)
	arm_a = la[0]
	arm_a_mesh = la[1]
	var lb := _limb(upper, Vector3(-0.6, 0.78, 0.0), Vector3(0.4, 0.8, 0.4), arm_b_c)
	arm_b = lb[0]
	arm_b_mesh = lb[1]
	var lc := _limb(rig, Vector3(0.2, 0.8, 0.0), Vector3(0.4, 0.8, 0.4), leg_a_c)
	leg_a = lc[0]
	leg_a_mesh = lc[1]
	var ld := _limb(rig, Vector3(-0.2, 0.8, 0.0), Vector3(0.4, 0.8, 0.4), leg_b_c)
	leg_b = ld[0]
	leg_b_mesh = ld[1]

	if sword:
		_box(arm_a, Vector3(0.06, 0.06, 0.9), Vector3(0.0, -0.75, 0.5), Color(0.8, 0.85, 0.92))
		_box(arm_a, Vector3(0.3, 0.06, 0.06), Vector3(0.0, -0.75, 0.1), Color(0.45, 0.28, 0.12))


## Recolors a single part live (used by the Customize screen's preview).
## part is one of "head", "torso", "arms" (both arms), "legs" (both legs).
func set_part_color(part: String, color: Color) -> void:
	match part:
		"head":
			if head_mesh:
				head_mesh.material_override.albedo_color = color
		"torso":
			if torso_mesh:
				torso_mesh.material_override.albedo_color = color
		"arms":
			if arm_a_mesh:
				arm_a_mesh.material_override.albedo_color = color
			if arm_b_mesh:
				arm_b_mesh.material_override.albedo_color = color
		"legs":
			if leg_a_mesh:
				leg_a_mesh.material_override.albedo_color = color
			if leg_b_mesh:
				leg_b_mesh.material_override.albedo_color = color


func wave() -> void:
	dance_id = ""
	_wave_left = 2.2


## Starts a dance ("disco", "floss" or "robot") from its first beat.
func play_dance(id: String) -> void:
	dance_id = id
	_dance_t = 0.0
	_wave_left = 0.0


func stop_dance() -> void:
	dance_id = ""


func is_dancing() -> bool:
	return dance_id != ""


func set_walk_style(style: int) -> void:
	walk_style = style


## Turns the Rainbow Aura (rising glow rings + sparks + a soft light) on/off.
func set_aura(on: bool) -> void:
	if on and _aura == null:
		_build_aura()
	if _aura:
		_aura.visible = on
		_aura_sparks.emitting = on


# ------------------------------------------------------------------ animate

## speed_ratio: horizontal speed / max speed (0..1).  vel_y is optional — pass
## the body's vertical velocity so jumps can show a rising vs. falling pose.
func animate(delta: float, speed_ratio: float, on_floor: bool, vel_y: float = 0.0) -> void:
	if rig == null:
		return
	_t += delta
	_tg.fill(0.0)

	# how fast the model is turning (used to bank into turns while running)
	var yaw := rotation.y
	if not _yaw_init:
		_yaw_init = true
		_last_yaw = yaw
	if delta > 0.0:
		var yr := angle_difference(_last_yaw, yaw) / delta
		_yaw_rate = lerpf(_yaw_rate, yr, clampf(delta * 10.0, 0.0, 1.0))
	_last_yaw = yaw

	var rate := 16.0
	if not on_floor:
		dance_id = "" # can't keep dancing in mid-air
		_was_air = true
		_air_vy = vel_y
		_pose_air(vel_y)
		rate = 12.0
	else:
		if _was_air:
			_was_air = false
			_land = clampf(-_air_vy / 14.0, 0.3, 1.0)
		if dance_id != "":
			rate = _pose_dance(delta)
		else:
			_pose_ground(speed_ratio, delta)
		_land = maxf(_land - delta * 4.5, 0.0)
		if _land > 0.0:
			_pose_landing()
			rate = maxf(rate, 26.0)

	if _wave_left > 0.0:
		_wave_left -= delta
		_tg[P_ARM_B_X] = 0.0
		_tg[P_ARM_B_Z] = -2.5 + sin(_t * 14.0) * 0.4
		_tg[P_HEAD_Z] += 0.1

	# blink now and then
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_in = randf_range(2.5, 5.5)
		_blink_left = 0.12
	_blink_left = maxf(_blink_left - delta, 0.0)
	var eye_scale := 0.12 if _blink_left > 0.0 else 1.0
	if _eye_a:
		_eye_a.scale.y = eye_scale
	if _eye_b:
		_eye_b.scale.y = eye_scale

	if _aura != null and _aura.visible:
		_update_aura(delta)

	# ease the real pose toward the target pose
	var k := 1.0 - exp(-rate * delta)
	for i in P_COUNT:
		_pose[i] = lerpf(_pose[i], _tg[i], k)
	_apply_pose()


func _apply_pose() -> void:
	arm_a.rotation = Vector3(_pose[P_ARM_A_X], 0.0, _pose[P_ARM_A_Z])
	arm_b.rotation = Vector3(_pose[P_ARM_B_X], 0.0, _pose[P_ARM_B_Z])
	leg_a.rotation = Vector3(_pose[P_LEG_A_X], 0.0, _pose[P_LEG_A_Z])
	leg_b.rotation = Vector3(_pose[P_LEG_B_X], 0.0, _pose[P_LEG_B_Z])
	upper.rotation = Vector3(_pose[P_LEAN], _pose[P_TWIST], _pose[P_ROLL])
	head_pivot.rotation = Vector3(_pose[P_HEAD_X], _pose[P_HEAD_Y], _pose[P_HEAD_Z])
	rig.position = Vector3(_pose[P_SWAY], _pose[P_BOB], 0.0)
	var sq := _pose[P_SQUASH]
	rig.scale = Vector3(1.0 - sq * 0.6, 1.0 + sq, 1.0 - sq * 0.6)


## Idle breathing + walk/run cycle (blended by speed).
func _pose_ground(speed_ratio: float, delta: float) -> void:
	var sr := clampf(speed_ratio, 0.0, 1.2)
	var moving := clampf(sr * 1.6, 0.0, 1.0)
	var idle := 1.0 - moving
	var run := clampf((sr - 0.55) / 0.4, 0.0, 1.0)

	# the step cycle speeds up with the actual ground speed
	var step_speed := lerpf(7.0, 13.5, clampf(sr, 0.0, 1.0))
	if walk_style == 1:
		step_speed *= 0.82
	elif walk_style == 2:
		step_speed *= 1.12
	_phase += delta * step_speed * moving
	var s := sin(_phase)
	var c := cos(_phase)
	var legs := lerpf(0.75, 1.0, run) * moving
	var arms := lerpf(0.8, 1.15, run) * moving

	# opposite arm / leg swing
	_tg[P_LEG_A_X] = -s * legs
	_tg[P_LEG_B_X] = s * legs
	_tg[P_ARM_A_X] = s * arms
	_tg[P_ARM_B_X] = -s * arms
	# arms drift outward a little when running
	_tg[P_ARM_A_Z] = 0.05 + 0.12 * run * moving
	_tg[P_ARM_B_Z] = -(0.05 + 0.12 * run * moving)

	# body: lean into the run, counter-twist the shoulders, bank into turns,
	# and dip a little on each stride
	_tg[P_LEAN] = lerpf(0.05, 0.24, run) * moving
	_tg[P_TWIST] = s * 0.16 * moving
	_tg[P_ROLL] = (c * 0.045 - clampf(_yaw_rate * 0.02, -0.22, 0.22)) * moving
	_tg[P_BOB] = -absf(s) * 0.10 * legs

	# the head stays level and keeps looking ahead while the body moves
	_tg[P_HEAD_X] = -_tg[P_LEAN] * 0.8
	_tg[P_HEAD_Y] = -_tg[P_TWIST] * 0.9
	_tg[P_HEAD_Z] = -_tg[P_ROLL] * 0.7

	if walk_style == 1:
		_walk_swagger(s, c, moving, run)
	elif walk_style == 2:
		_walk_coin_runner(s, c, moving, run)

	# idle: breathing, tiny arm sway, weight shift, slow look-around
	var breath := sin(_t * 2.2)
	_tg[P_BOB] += breath * 0.012 * idle
	_tg[P_ARM_A_X] += sin(_t * 1.6) * 0.045 * idle
	_tg[P_ARM_B_X] -= sin(_t * 1.6) * 0.045 * idle
	_tg[P_ARM_A_Z] += (0.03 + breath * 0.02) * idle
	_tg[P_ARM_B_Z] -= (0.03 + breath * 0.02) * idle
	_tg[P_ROLL] += sin(_t * 0.7) * 0.02 * idle
	_tg[P_HEAD_Y] += sin(_t * 0.55) * 0.2 * idle
	_tg[P_HEAD_X] += sin(_t * 0.9 + 1.0) * 0.04 * idle


## Swagger Walk: slower, cooler stride — hips swing side to side, shoulders
## roll, arms held a bit out, head tilts on every step, chest a little back.
## Layered on top of the normal walk/run targets.
func _walk_swagger(s: float, c: float, moving: float, run: float) -> void:
	_tg[P_LEG_A_X] *= 0.9
	_tg[P_LEG_B_X] *= 0.9
	_tg[P_ARM_A_X] *= 0.6
	_tg[P_ARM_B_X] *= 0.6
	_tg[P_ARM_A_Z] += 0.22 * moving
	_tg[P_ARM_B_Z] -= 0.22 * moving
	_tg[P_SWAY] = c * 0.09 * moving
	_tg[P_ROLL] -= c * 0.11 * moving
	_tg[P_TWIST] = s * 0.30 * moving
	_tg[P_LEAN] = lerpf(-0.07, 0.12, run) * moving
	_tg[P_BOB] += absf(c) * 0.05 * moving
	_tg[P_HEAD_Z] += c * 0.09 * moving
	_tg[P_HEAD_Y] = -_tg[P_TWIST] * 0.8
	_tg[P_HEAD_X] = -_tg[P_LEAN] * 0.6


## Coin Runner: an energetic, bouncy stride with a little extra hop on every
## step and a quicker arm pump — like sprinting to grab a coin. Layered on
## top of the normal walk/run targets, the same way Swagger Walk is.
func _walk_coin_runner(s: float, c: float, moving: float, run: float) -> void:
	_tg[P_LEG_A_X] *= 1.15
	_tg[P_LEG_B_X] *= 1.15
	_tg[P_ARM_A_X] *= 1.3
	_tg[P_ARM_B_X] *= 1.3
	_tg[P_BOB] -= absf(s) * 0.09 * moving
	_tg[P_SQUASH] += absf(c) * 0.05 * moving
	_tg[P_LEAN] += 0.05 * moving
	_tg[P_HEAD_X] += absf(s) * 0.05 * moving


## Jump: arms up + stretch while rising, arms out while falling.
func _pose_air(vy: float) -> void:
	var f := clampf((4.0 - vy) / 10.0, 0.0, 1.0) # 0 = rising fast ... 1 = falling
	_tg[P_ARM_A_X] = lerpf(-2.7, -0.5, f)
	_tg[P_ARM_B_X] = lerpf(-2.7, -0.5, f)
	_tg[P_ARM_A_Z] = lerpf(0.18, 1.5, f)
	_tg[P_ARM_B_Z] = -lerpf(0.18, 1.5, f)
	_tg[P_LEG_A_X] = lerpf(-0.55, -0.2, f)
	_tg[P_LEG_B_X] = lerpf(0.4, 0.25, f)
	_tg[P_LEG_A_Z] = lerpf(0.0, 0.2, f)
	_tg[P_LEG_B_Z] = -lerpf(0.0, 0.2, f)
	_tg[P_LEAN] = lerpf(-0.05, 0.09, f)
	_tg[P_HEAD_X] = lerpf(-0.18, 0.05, f)
	_tg[P_SQUASH] = lerpf(0.07, 0.02, f)


## Layered on top of the ground pose for a moment after touching down.
func _pose_landing() -> void:
	var w := _land
	_tg[P_BOB] -= 0.10 * w
	_tg[P_SQUASH] -= 0.13 * w
	_tg[P_LEAN] += 0.14 * w
	_tg[P_ARM_A_X] += 0.5 * w
	_tg[P_ARM_B_X] += 0.5 * w
	_tg[P_HEAD_X] -= 0.1 * w


# ------------------------------------------------------------------- dances

## Returns how snappy the pose blend should be for this dance.
func _pose_dance(delta: float) -> float:
	_dance_t += delta
	match dance_id:
		"disco":
			return _dance_disco()
		"floss":
			return _dance_floss()
		"robot":
			return _dance_robot()
	return 16.0


## Hips are shifted sideways by P_SWAY; tilt both legs the other way so the
## feet stay planted on the floor instead of sliding.
func _plant_feet() -> void:
	var lz := -_tg[P_SWAY] / 0.8
	_tg[P_LEG_A_Z] += lz
	_tg[P_LEG_B_Z] += lz


## Disco: arms point at the sky one after the other, hips swing, knee pumps.
func _dance_disco() -> float:
	var ph := _dance_t * TAU * 1.0 # one cycle per second (two beats)
	var s := sin(ph)
	var u := 0.5 + 0.5 * s # how high arm A is
	var v := 1.0 - u       # how high arm B is
	_tg[P_ARM_A_Z] = lerpf(0.3, 2.7, u)
	_tg[P_ARM_A_X] = -0.3 * u
	_tg[P_ARM_B_Z] = -lerpf(0.3, 2.7, v)
	_tg[P_ARM_B_X] = -0.3 * v
	_tg[P_TWIST] = -0.28 * s
	_tg[P_ROLL] = -0.09 * s
	_tg[P_SWAY] = -0.10 * s
	_tg[P_HEAD_Z] = 0.16 * s
	_tg[P_HEAD_Y] = 0.22 * s
	_tg[P_HEAD_X] = -0.12 * u
	_tg[P_BOB] = -0.08 * (0.5 - 0.5 * cos(ph * 2.0)) # dip on every beat
	_tg[P_LEG_A_X] = -0.4 * maxf(s, 0.0)
	_tg[P_LEG_B_X] = -0.4 * maxf(-s, 0.0)
	_plant_feet()
	return 14.0


## Floss: arms swing side to side behind the back while the hips swing the
## opposite way.
func _dance_floss() -> float:
	var ph := _dance_t * TAU * 1.8
	var s := sin(ph)
	var pos := maxf(s, 0.0)
	var neg := maxf(-s, 0.0)
	_tg[P_ARM_A_X] = 0.95
	_tg[P_ARM_B_X] = 0.95
	_tg[P_ARM_A_Z] = 0.15 + 0.95 * pos - 0.3 * neg
	_tg[P_ARM_B_Z] = -(0.15 + 0.95 * neg - 0.3 * pos)
	_tg[P_SWAY] = -0.16 * s
	_tg[P_ROLL] = -0.10 * s
	_tg[P_LEAN] = 0.10
	_tg[P_HEAD_X] = -0.10
	_tg[P_HEAD_Z] = 0.05 * s
	_tg[P_BOB] = -0.06 + 0.02 * cos(ph * 2.0)
	_plant_feet()
	return 22.0


## Robot: stiff, snapped poses on a steady beat.
func _dance_robot() -> float:
	var n := ROBOT_POSES.size()
	var idx := int(_dance_t * 2.5) % n
	var p: Array = ROBOT_POSES[idx]
	_tg[P_ARM_A_X] = float(p[0])
	_tg[P_ARM_A_Z] = float(p[1])
	_tg[P_ARM_B_X] = float(p[2])
	_tg[P_ARM_B_Z] = float(p[3])
	_tg[P_LEG_A_X] = float(p[4])
	_tg[P_LEG_B_X] = float(p[5])
	_tg[P_TWIST] = float(p[6])
	_tg[P_HEAD_Y] = float(p[7])
	_tg[P_HEAD_X] = float(p[8])
	_tg[P_BOB] = -0.05 * float(idx % 2)
	return 40.0


# --------------------------------------------------------------------- aura

func _build_aura() -> void:
	_aura = Node3D.new()
	add_child(_aura)

	# three glowing rings that rise from the floor to above the head, shrinking and fading
	for i in 3:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.78
		tm.outer_radius = 0.92
		tm.rings = 24
		tm.ring_segments = 6
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		tm.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aura.add_child(mi)
		_aura_rings.append(mi)
		_aura_ring_mats.append(m)

	# sparks drifting upward (they stay in the world, so they trail behind when you run)
	_aura_spark_mat = StandardMaterial3D.new()
	_aura_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var sm := BoxMesh.new()
	sm.size = Vector3(0.12, 0.12, 0.12)
	sm.material = _aura_spark_mat
	_aura_sparks = CPUParticles3D.new()
	_aura_sparks.amount = 22
	_aura_sparks.lifetime = 1.3
	_aura_sparks.local_coords = false
	_aura_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_aura_sparks.emission_box_extents = Vector3(0.7, 0.05, 0.7)
	_aura_sparks.direction = Vector3(0.0, 1.0, 0.0)
	_aura_sparks.spread = 8.0
	_aura_sparks.gravity = Vector3.ZERO
	_aura_sparks.initial_velocity_min = 1.0
	_aura_sparks.initial_velocity_max = 2.2
	_aura_sparks.scale_amount_min = 0.5
	_aura_sparks.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_aura_sparks.scale_amount_curve = curve
	_aura_sparks.mesh = sm
	_aura_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura_sparks.position = Vector3(0.0, 0.05, 0.0)
	_aura.add_child(_aura_sparks)

	# soft glow on the ground and the character
	_aura_light = OmniLight3D.new()
	_aura_light.omni_range = 3.5
	_aura_light.light_energy = 0.7
	_aura_light.position = Vector3(0.0, 1.0, 0.0)
	_aura.add_child(_aura_light)


func _update_aura(delta: float) -> void:
	_aura_t += delta
	var col := Color.from_hsv(fposmod(_aura_t * 0.15, 1.0), 0.65, 1.0)
	_aura_spark_mat.albedo_color = Color(col.r, col.g, col.b, 0.9)
	_aura_light.light_color = col
	for i in 3:
		var t := fposmod(_aura_t * 0.6 + float(i) / 3.0, 1.0) # 0 = at the feet ... 1 = above the head
		var ring: MeshInstance3D = _aura_rings[i]
		ring.position.y = 0.05 + t * 2.5
		var sc := 1.0 - 0.35 * t
		ring.scale = Vector3(sc, 1.0, sc)
		var m: StandardMaterial3D = _aura_ring_mats[i]
		m.albedo_color = Color(col.r, col.g, col.b, sin(t * PI) * 0.75)
