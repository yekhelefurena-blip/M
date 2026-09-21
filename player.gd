extends CharacterBody3D
## Third-person player. Input is fed in by main.gd (input_dir / want_jump).

signal landed(speed: float) # emitted when touching down after a real fall/jump
signal jumped

const BlockyScript = preload("res://blocky.gd")

const SPEED := 7.5
const JUMP_VELOCITY := 9.0
const GRAVITY := 26.0
const GROUND_ACCEL := 45.0
const AIR_ACCEL := 20.0
## Grace period: you can still jump for a moment after walking off a ledge.
const COYOTE_TIME := 0.12
## A jump pressed slightly before landing still counts.
const JUMP_BUFFER := 0.15

## Movement bounds + respawn are mutable so main.gd can swap them when the
## player enters a different area (e.g. the Parkour minigame world).
var bounds_center := Vector2(0.0, 0.0)
var bounds_limit := 94.0
var respawn_pos := Vector3(0.0, 1.0, 34.0)
var fall_y := -20.0

var input_dir := Vector3.ZERO
var want_jump := false
var in_water := false
var model # Blocky instance

## `look_yaw` is the camera's yaw (set by main.gd). With Shift Lock on the
## model faces the same way the camera looks (away from it); while dancing it
## turns to face the camera so you can see the moves.
var shift_lock := false
var look_yaw := 0.0

var _jump_buffer := 0.0
var _coyote := 0.0
var _was_on_floor := true
var _run_dust: CPUParticles3D
var _puff_dust: CPUParticles3D


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 2.0
	shape.shape = cap
	shape.position.y = 1.0
	add_child(shape)
	floor_snap_length = 0.5

	model = BlockyScript.new()
	add_child(model)
	# colors come from the Customize screen (home.gd / customization.gd),
	# with the classic blue-shirt/green-pants/yellow-skin look as default
	model.build(Customization.head_color, Customization.torso_color,
		Customization.arms_color, Customization.arms_color,
		Customization.legs_color, Customization.legs_color,
		Customization.hair_color, false)

	# items bought in the Shop
	model.set_walk_style(Customization.walk_style())
	model.set_aura(Customization.aura_enabled())

	_run_dust = _make_dust(14, 0.45, false)
	_puff_dust = _make_dust(12, 0.5, true)


## Small blocky dust cloud (world-space, so it stays behind as you move).
func _make_dust(amount: int, life: float, one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.emitting = false
	p.explosiveness = 0.9 if one_shot else 0.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 75.0
	p.gravity = Vector3(0.0, -1.5, 0.0)
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.4
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.2, 0.2)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.89, 0.78)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = m
	p.mesh = bm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0.0, 0.1, 0.0)
	add_child(p)
	return p


func _puff() -> void:
	if in_water:
		return
	_puff_dust.restart()


func _physics_process(delta: float) -> void:
	# dancing ends as soon as the player wants to go somewhere
	if model.is_dancing() and (input_dir.length() > 0.1 or want_jump):
		model.stop_dance()

	var speed := SPEED * (0.55 if in_water else 1.0)
	var target := input_dir * speed
	var on_floor := is_on_floor()
	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)

	if want_jump:
		_jump_buffer = JUMP_BUFFER
		want_jump = false
	_jump_buffer -= delta
	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote -= delta

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		_puff()
		jumped.emit()
	elif on_floor:
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	var vy_before := velocity.y
	move_and_slide()
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor and vy_before < -4.0:
		_puff()
		landed.emit(-vy_before)
	_was_on_floor = now_floor

	position.x = clampf(position.x, bounds_center.x - bounds_limit, bounds_center.x + bounds_limit)
	position.z = clampf(position.z, bounds_center.y - bounds_limit, bounds_center.y + bounds_limit)
	if position.y < fall_y:
		position = respawn_pos
		velocity = Vector3.ZERO
		model.stop_dance()

	if model.is_dancing():
		model.rotation.y = lerp_angle(model.rotation.y, look_yaw, 8.0 * delta)
	elif shift_lock:
		model.rotation.y = lerp_angle(model.rotation.y, look_yaw + PI, 14.0 * delta)
	elif input_dir.length() > 0.1:
		var target_yaw := atan2(input_dir.x, input_dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 14.0 * delta)

	var hv := Vector2(velocity.x, velocity.z)
	_run_dust.emitting = now_floor and hv.length() > SPEED * 0.6 and not in_water
	model.animate(delta, hv.length() / SPEED, now_floor, velocity.y)
