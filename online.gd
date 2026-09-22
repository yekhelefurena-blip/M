extends Node
## Everything about "other players" inside the game world (created by main.gd):
##   - connects to the server when Play online is on (Customize/Marketplace menu)
##   - spawns / moves / animates the other players' avatars, with name tags
##   - shows chat as a log on the HUD and as speech bubbles over heads
##   - sends this player's position to the server ~15 times a second
## The actual networking (RPCs) lives in net.gd.

const BlockyScript = preload("res://blocky.gd")
const PlayerScript = preload("res://player.gd")

const SEND_INTERVAL := 1.0 / 15.0
const HEARTBEAT := 1.0     # send at least this often, even when standing still
const BUBBLE_TIME := 6.0
const MAX_LOG := 40
const TAG_Y := 2.75        # name tag height above the feet
const BUBBLE_Y := 3.05     # speech bubble sits just above the tag

var main # the Main node (gives us player + toast())
var remotes := {}          # id -> Dictionary (see _add_remote)
var chat_lines: Array = [] # shared with the HUD: {name, text, age, sys}
var status := ""           # e.g. "Online · 3 players" (shown by the HUD)

var _send_t := 0.0
var _hb := 0.0
var _last_pos := Vector3.INF
var _last_yaw := 0.0
var _last_dance := ""
var _last_floor := true
var _local_bubble: Label3D
var _local_bubble_t := 0.0


func setup(main_node) -> void:
	main = main_node
	Net.state_changed.connect(_on_state_changed)
	Net.player_added.connect(_on_player_added)
	Net.player_removed.connect(_on_player_removed)
	Net.state_received.connect(_on_state_received)
	Net.chat_received.connect(_on_chat_received)

	_local_bubble = _make_label("", Color(1.0, 0.95, 0.7))
	_local_bubble.position = Vector3(0.0, TAG_Y + 0.1, 0.0)
	_make_bubble_style(_local_bubble)
	main.player.add_child(_local_bubble)

	if Customization.online:
		Net.join(Customization.server_url, Customization.make_join_info())
	_refresh_status()


func _exit_tree() -> void:
	Net.leave()


func is_online() -> bool:
	return Net.state == Net.State.ONLINE


func say(text: String) -> void:
	var t := text.strip_edges()
	if t != "":
		Net.say(t)


# ----------------------------------------------------------------- per frame

func tick(delta: float) -> void:
	for l in chat_lines:
		l["age"] = float(l["age"]) + delta
	while chat_lines.size() > MAX_LOG:
		chat_lines.pop_front()

	_local_bubble_t = maxf(_local_bubble_t - delta, 0.0)
	_local_bubble.visible = _local_bubble_t > 0.0

	for id in remotes:
		_update_remote(remotes[id], delta)

	if is_online():
		_send_local(delta)


func _send_local(delta: float) -> void:
	_send_t += delta
	if _send_t < SEND_INTERVAL:
		return
	_send_t = 0.0
	_hb += SEND_INTERVAL

	var p = main.player
	var vel: Vector3 = p.velocity
	var pos: Vector3 = p.position
	var yaw: float = p.model.rotation.y
	var dance: String = p.model.dance_id
	var on_floor: bool = p.is_on_floor()
	var speed := clampf(Vector2(vel.x, vel.z).length() / PlayerScript.SPEED, 0.0, 1.2)

	var changed := pos.distance_to(_last_pos) > 0.02 \
		or absf(angle_difference(_last_yaw, yaw)) > 0.02 \
		or dance != _last_dance or on_floor != _last_floor
	if changed or _hb >= HEARTBEAT:
		_hb = 0.0
		_last_pos = pos
		_last_yaw = yaw
		_last_dance = dance
		_last_floor = on_floor
		Net.send_local_state(pos, yaw, speed, on_floor, vel.y, dance)


# ------------------------------------------------------------ remote players

func _col(info: Dictionary, key: String) -> Color:
	var c = info.get(key)
	return c if typeof(c) == TYPE_COLOR else Color(0.8, 0.8, 0.8)


func _make_label(text: String, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.005
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 1)
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return l


## Speech bubbles wrap long messages and grow upward from their anchor.
func _make_bubble_style(l: Label3D) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = 640.0
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.visible = false


func _add_remote(id: int, info: Dictionary) -> void:
	if remotes.has(id):
		return
	var holder := Node3D.new()
	var model := BlockyScript.new()
	holder.add_child(model)
	model.build(_col(info, "head"), _col(info, "torso"), _col(info, "arms"), _col(info, "arms"),
		_col(info, "legs"), _col(info, "legs"), _col(info, "hair"), false)

	model.set_walk_style(int(info.get("walk", 0)))
	model.set_aura(bool(info.get("aura", false)))
	model.set_shirt(Customization.shirt_tex_for_id(String(info.get("shirt", ""))))

	var tag := _make_label(String(info.get("name", "Player")), Color(1, 1, 1))
	tag.position = Vector3(0.0, TAG_Y, 0.0)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	holder.add_child(tag)

	var bubble := _make_label("", Color(1.0, 0.95, 0.7))
	bubble.position = Vector3(0.0, BUBBLE_Y, 0.0)
	_make_bubble_style(bubble)
	holder.add_child(bubble)

	var pos: Vector3 = info.get("pos", Vector3(0.0, 1.0, 34.0))
	holder.position = pos
	add_child(holder)
	remotes[id] = {
		"holder": holder, "model": model, "bubble": bubble, "bubble_t": 0.0,
		"name": String(info.get("name", "Player")),
		"pos": pos, "yaw": float(info.get("yaw", 0.0)), "speed": float(info.get("speed", 0.0)),
		"floor": bool(info.get("floor", true)), "vy": float(info.get("vy", 0.0)),
		"dance": String(info.get("dance", "")),
	}
	model.rotation.y = float(info.get("yaw", 0.0))


func _remove_remote(id: int) -> void:
	if not remotes.has(id):
		return
	var r: Dictionary = remotes[id]
	var holder: Node3D = r["holder"]
	holder.queue_free()
	remotes.erase(id)


func _clear_remotes() -> void:
	for id in remotes.keys():
		_remove_remote(id)


func _update_remote(r: Dictionary, delta: float) -> void:
	var holder: Node3D = r["holder"]
	var target: Vector3 = r["pos"]
	if holder.position.distance_to(target) > 10.0:
		holder.position = target # they teleported (respawn / entered parkour)
	else:
		holder.position = holder.position.lerp(target, 1.0 - exp(-12.0 * delta))

	var model = r["model"]
	model.rotation.y = lerp_angle(model.rotation.y, float(r["yaw"]), 1.0 - exp(-14.0 * delta))
	var dance := String(r["dance"])
	if dance != model.dance_id:
		if dance == "":
			model.stop_dance()
		else:
			model.play_dance(dance)
	model.animate(delta, float(r["speed"]), bool(r["floor"]), float(r["vy"]))

	var bt := maxf(float(r["bubble_t"]) - delta, 0.0)
	r["bubble_t"] = bt
	var bubble: Label3D = r["bubble"]
	bubble.visible = bt > 0.0


# ------------------------------------------------------------- net callbacks

func _on_state_changed(s: int) -> void:
	if s == Net.State.ONLINE:
		main.toast("Online!  Tap the chat button to talk to other players", 3.5)
	elif s == Net.State.FAILED:
		_clear_remotes()
		main.toast("Online: %s — playing offline" % Net.last_error, 4.0)
	elif s == Net.State.OFFLINE:
		_clear_remotes()
	_refresh_status()


func _on_player_added(id: int, info: Dictionary, announce: bool) -> void:
	_add_remote(id, info)
	if announce:
		_add_line("", "%s joined" % String(info.get("name", "Player")), true)
	_refresh_status()


func _on_player_removed(id: int) -> void:
	if remotes.has(id):
		var r: Dictionary = remotes[id]
		_add_line("", "%s left" % String(r["name"]), true)
	_remove_remote(id)
	_refresh_status()


func _on_state_received(id: int, pos: Vector3, yaw: float, speed: float, on_floor: bool, vy: float, dance: String) -> void:
	if not remotes.has(id):
		return
	var r: Dictionary = remotes[id]
	r["pos"] = pos
	r["yaw"] = yaw
	r["speed"] = speed
	r["floor"] = on_floor
	r["vy"] = vy
	r["dance"] = dance


func _on_chat_received(id: int, sender: String, text: String) -> void:
	_add_line(sender, text, false)
	if id == Net.my_id():
		_local_bubble.text = text
		_local_bubble_t = BUBBLE_TIME
	elif remotes.has(id):
		var r: Dictionary = remotes[id]
		var bubble: Label3D = r["bubble"]
		bubble.text = text
		r["bubble_t"] = BUBBLE_TIME


func _add_line(sender: String, text: String, is_system: bool) -> void:
	chat_lines.append({"name": sender, "text": text, "age": 0.0, "sys": is_system})


func _refresh_status() -> void:
	if Net.state == Net.State.CONNECTING:
		status = "Connecting to server…"
	elif Net.state == Net.State.ONLINE:
		var n := remotes.size() + 1
		status = "Online · %d %s" % [n, "player" if n == 1 else "players"]
	elif Net.state == Net.State.FAILED:
		status = "Offline · %s" % Net.last_error
	else:
		status = ""
