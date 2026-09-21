extends Node
## Online layer (autoload "Net"). One script, two roles:
##
##   * SERVER  — run the project headless with `--server` (see README /
##               Dockerfile). It keeps the player list, relays each player's
##               position to the others, and relays chat messages. It never
##               runs the game world itself, so it is tiny.
##   * CLIENT  — the game. join() connects to the server over WebSocket
##               (works through phone data / Wi-Fi and behind wss:// hosting).
##
## Movement is client-authoritative: every player sends where they are ~15x a
## second and the server just forwards it. That's plenty for a friendly
## hangout world; it is NOT cheat-proof.
##
## All RPCs live on this one node (/root/Net), so the paths always match
## between server and clients.

signal state_changed(new_state: int)
signal player_added(id: int, info: Dictionary, announce: bool)
signal player_removed(id: int)
signal state_received(id: int, pos: Vector3, yaw: float, speed: float, on_floor: bool, vy: float, dance: String)
signal chat_received(id: int, sender: String, text: String)

enum State { OFFLINE, CONNECTING, ONLINE, FAILED }

const DEFAULT_PORT := 9080
const MAX_PLAYERS := 24
const MAX_CHAT_LEN := 120
const NAME_MAX := 16
const CHAT_COOLDOWN_MS := 600
const KICK_UNREGISTERED_AFTER := 6.0
## Where the server keeps its username -> password-hash table. This is the
## container's own local disk: fine for a always-on paid instance, but on a
## FREE host (e.g. Render's free plan) the disk is not guaranteed to survive
## a redeploy, so accounts created there can be lost if the service is
## redeployed or fully recreated (a normal sleep/wake from being idle is
## usually fine — it's a fresh deploy that risks it).
const ACCOUNTS_PATH := "user://accounts.json"

var is_server := false
var state := State.OFFLINE
var last_error := ""
## Server: every connected player (id -> info). Client: the *other* players.
var players := {}
## Server only: username (lowercase) -> SHA-256 password hash.
var accounts := {}

var _join_info := {}
var _last_chat := {} # server: id -> last chat time (msec)


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	var args := OS.get_cmdline_user_args()
	if "--server" in args or OS.has_feature("dedicated_server"):
		_start_server(_pick_port(args))


# ------------------------------------------------------------------ helpers

## Turns what a person types ("192.168.1.5", "my-game.onrender.com", ...) into
## a proper ws:// or wss:// URL.
static func normalize_url(raw: String) -> String:
	var u := raw.strip_edges()
	if u.begins_with("ws://") or u.begins_with("wss://"):
		return u
	if u.begins_with("http://"):
		return "ws://" + u.substr(7)
	if u.begins_with("https://"):
		return "wss://" + u.substr(8)
	var host_port := u.get_slice("/", 0)
	var host := host_port.get_slice(":", 0)
	if host == "localhost" or host.is_valid_ip_address():
		if not host_port.contains(":"):
			u += ":%d" % DEFAULT_PORT
		return "ws://" + u
	return "wss://" + u


func _clean_text(s: String, max_len: int) -> String:
	var out := ""
	for i in s.length():
		var code := s.unicode_at(i)
		if code < 32 or code == 127:
			continue
		# text-direction overrides/isolates can be used to scramble other people's screens
		if (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069):
			continue
		out += s[i]
	return out.strip_edges().substr(0, max_len)


func _clean_info(info: Dictionary) -> Dictionary:
	var nm := _clean_text(String(info.get("name", "")), NAME_MAX)
	if nm == "":
		nm = "Player"
	var out := {
		"name": nm,
		"pos": Vector3(0.0, 1.0, 34.0), "yaw": 0.0, "speed": 0.0,
		"floor": true, "vy": 0.0, "dance": "",
	}
	for key in ["head", "torso", "arms", "legs", "hair"]:
		var c = info.get(key)
		out[key] = c if typeof(c) == TYPE_COLOR else Color(0.8, 0.8, 0.8)
	var walk = info.get("walk", 0)
	out["walk"] = clampi(int(walk), 0, 2) if typeof(walk) == TYPE_INT else 0
	var aura = info.get("aura", false)
	out["aura"] = aura if typeof(aura) == TYPE_BOOL else false
	return out


func _dance_ok(id: String) -> bool:
	if id == "":
		return true
	for d in Customization.DANCES:
		if String(d["id"]) == id:
			return true
	return false


func my_id() -> int:
	return multiplayer.get_unique_id()


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(int(s))


# ------------------------------------------------------------------- server

func _pick_port(args: PackedStringArray) -> int:
	var port := DEFAULT_PORT
	var env := OS.get_environment("PORT") # hosting services tell us which port to use
	if env.is_valid_int():
		port = int(env)
	for a in args:
		if a.begins_with("--port="):
			port = int(a.substr(7))
	return port


func _start_server(port: int) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("Server: can't listen on port %d (error %d)" % [port, err])
		return
	multiplayer.multiplayer_peer = peer
	is_server = true
	Engine.max_fps = 30
	_load_accounts()
	print("Blocky World server listening on port %d (%d accounts on file)" % [port, accounts.size()])


func _load_accounts() -> void:
	if not FileAccess.file_exists(ACCOUNTS_PATH):
		return
	var f := FileAccess.open(ACCOUNTS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		accounts = parsed


func _save_accounts() -> void:
	var f := FileAccess.open(ACCOUNTS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(accounts))


func _on_peer_connected(id: int) -> void:
	if not is_server:
		return
	# anyone who doesn't introduce themselves quickly gets dropped
	get_tree().create_timer(KICK_UNREGISTERED_AFTER).timeout.connect(_kick_if_unregistered.bind(id))


func _kick_if_unregistered(id: int) -> void:
	if is_server and not players.has(id) and multiplayer.get_peers().has(id):
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server:
		return
	_last_chat.erase(id)
	if not players.has(id):
		return
	var nm := String(players[id]["name"])
	players.erase(id)
	print("[server] %s left (%d online)" % [nm, players.size()])
	for pid in players:
		_player_removed.rpc_id(pid, id)


## Client -> server: "here's who I am". Also checks the account: a brand-new
## username is claimed on the spot (bound to the password hash sent along
## with it); an existing username must come with the matching hash, or the
## connection is refused with a reason the client shows to the person.
@rpc("any_peer", "call_remote", "reliable")
func register(info: Dictionary) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		return
	if players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	var uname := _clean_text(String(info.get("username", "")), NAME_MAX).to_lower()
	var phash := String(info.get("password_hash", ""))
	if uname != "":
		if accounts.has(uname):
			if String(accounts[uname]) != phash:
				_account_rejected.rpc_id(id, "that username is already taken")
				multiplayer.multiplayer_peer.disconnect_peer(id)
				return
		else:
			accounts[uname] = phash
			_save_accounts()
	var clean := _clean_info(info)
	_player_list.rpc_id(id, players.duplicate(true)) # who is already here (with last known positions)
	for pid in players:
		_player_added.rpc_id(pid, id, clean)
	players[id] = clean
	print("[server] %s joined (%d online)" % [clean["name"], players.size()])


## Client -> server: my position / pose. The server forwards it to everybody else.
@rpc("any_peer", "call_remote", "reliable")
func send_state(pos: Vector3, yaw: float, speed: float, on_floor: bool, vy: float, dance: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	if not pos.is_finite() or not is_finite(yaw) or not is_finite(speed) or not is_finite(vy):
		return
	pos = pos.clamp(Vector3(-2000.0, -500.0, -2000.0), Vector3(2000.0, 500.0, 2000.0))
	speed = clampf(speed, 0.0, 1.5)
	if not _dance_ok(dance):
		dance = ""
	var p: Dictionary = players[id]
	p["pos"] = pos
	p["yaw"] = yaw
	p["speed"] = speed
	p["floor"] = on_floor
	p["vy"] = vy
	p["dance"] = dance
	for pid in players:
		if pid != id:
			_recv_state.rpc_id(pid, id, pos, yaw, speed, on_floor, vy, dance)


## Client -> server: a chat message. Checked, then shown to everyone.
@rpc("any_peer", "call_remote", "reliable")
func send_chat(text: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_chat.get(id, -100000)) < CHAT_COOLDOWN_MS:
		return
	var clean := _clean_text(text, MAX_CHAT_LEN)
	if clean == "":
		return
	_last_chat[id] = now
	var nm := String(players[id]["name"])
	print("[chat] %s: %s" % [nm, clean])
	_recv_chat.rpc(id, nm, clean)


# ------------------------------------------------------------------- client

func join(url: String, info: Dictionary) -> void:
	if is_server:
		return
	leave()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(normalize_url(url))
	if err != OK:
		last_error = "bad server address"
		_set_state(State.FAILED)
		return
	_join_info = info
	last_error = ""
	multiplayer.multiplayer_peer = peer
	_set_state(State.CONNECTING)


func leave() -> void:
	if is_server:
		return
	var was := state
	state = State.OFFLINE # silently, so the disconnect callbacks below ignore us
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	if was != State.OFFLINE:
		state_changed.emit(int(State.OFFLINE))


func say(text: String) -> void:
	if state == State.ONLINE:
		send_chat.rpc_id(1, text)


func send_local_state(pos: Vector3, yaw: float, speed: float, on_floor: bool, vy: float, dance: String) -> void:
	if state == State.ONLINE:
		send_state.rpc_id(1, pos, yaw, speed, on_floor, vy, dance)


func _on_connected_to_server() -> void:
	register.rpc_id(1, _join_info)


func _on_connection_failed() -> void:
	if state == State.OFFLINE:
		return
	last_error = "couldn't reach the server"
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	_set_state(State.FAILED)


func _on_server_disconnected() -> void:
	if is_server or state == State.OFFLINE or state == State.FAILED:
		return
	last_error = "connection lost"
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	_set_state(State.FAILED)


## Server -> client: the account check in register() above failed. Sets the
## same last_error the rest of the FAILED-state handling already reads, so
## the usual "playing offline" toast just shows this reason instead.
@rpc("authority", "call_remote", "reliable")
func _account_rejected(reason: String) -> void:
	last_error = reason
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	_set_state(State.FAILED)


## Server -> new client: everyone who is already here. Also our "you're in" signal.
@rpc("authority", "call_remote", "reliable")
func _player_list(list: Dictionary) -> void:
	players.clear()
	for id in list:
		players[id] = list[id]
	_set_state(State.ONLINE)
	for id in list:
		player_added.emit(id, list[id], false)


@rpc("authority", "call_remote", "reliable")
func _player_added(id: int, info: Dictionary) -> void:
	players[id] = info
	player_added.emit(id, info, true)


@rpc("authority", "call_remote", "reliable")
func _player_removed(id: int) -> void:
	players.erase(id)
	player_removed.emit(id)


@rpc("authority", "call_remote", "reliable")
func _recv_state(id: int, pos: Vector3, yaw: float, speed: float, on_floor: bool, vy: float, dance: String) -> void:
	state_received.emit(id, pos, yaw, speed, on_floor, vy, dance)


@rpc("authority", "call_remote", "reliable")
func _recv_chat(id: int, sender: String, text: String) -> void:
	chat_received.emit(id, sender, text)
