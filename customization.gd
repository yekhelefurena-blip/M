extends Node
## Autoload singleton. Remembers the player's chosen avatar colors between
## the home/marketplace menu and the game world, and saves them to disk so
## the look persists between sessions — like Roblox remembers your avatar.

const SAVE_PATH := "user://customization.cfg"

var head_color := Color(0.98, 0.83, 0.1)
var torso_color := Color(0.13, 0.5, 0.85)
var arms_color := Color(0.98, 0.83, 0.1)
var legs_color := Color(0.3, 0.72, 0.25)
var hair_color := Color(0.22, 0.22, 0.25)

## Backdrop shown behind the avatar on the Customize screen (index into
## BACKGROUNDS). To add one: drop a 9:16 image in assets/ and add a line here.
const BACKGROUNDS := [
	{"name": "Blood moon", "path": "res://assets/bg_blood_moon.jpg"},
	{"name": "Crystal sky", "path": "res://assets/bg_crystal_sky.jpg"},
	{"name": "Forest", "path": "res://assets/bg_forest.jpg"},
]
var background := 0

## Dances shown in the Customize screen's "Dances" section. The equipped one
## (index into DANCES) is what the in-game DANCE button plays. To add one:
## write a _dance_xxx() in blocky.gd, then add a line here.
const DANCES := [
	{"id": "disco", "name": "Disco", "color": Color(0.62, 0.36, 0.9)},
	{"id": "floss", "name": "Floss", "color": Color(0.2, 0.7, 0.95)},
	{"id": "robot", "name": "Robot", "color": Color(0.95, 0.55, 0.2)},
]
var dance := 0

## Shop. Coins are collected in the game world and saved, so they carry over
## between sessions. Buying an item unlocks it and equips it; the Shop tab can
## then switch it on/off. To add an item: add a line here (kind "walk" or
## "aura" are handled in blocky.gd) and add a card for it in home.gd if needed.
const SHOP_ITEMS := [
	{"id": "swagger", "kind": "walk", "name": "Swagger Walk", "desc": "A cool strut with swinging hips", "price": 80},
	{"id": "aura", "kind": "aura", "name": "Rainbow Aura", "desc": "Glowing rings and sparks around you", "price": 140},
	{"id": "coinrun", "kind": "walk", "name": "Coin Runner", "desc": "Bouncy, energetic stride with a little hop on every step", "price": 110},
	{"id": "angel", "kind": "walk", "name": "Angel Float", "desc": "Angel wings, hover above the ground and fly when you move", "price": 300},
]
var coins := 0
var owned: Array = []    # ids of purchased items
var equipped: Array = [] # ids currently switched on

## Shirts — the "Shirts" section of the Shop. Same coins/owned/equipped
## system as SHOP_ITEMS above, except a shirt is exclusive: buying or
## equipping one automatically takes off whichever shirt was worn before
## (see buy() / toggle_equip() below), since a body only wears one shirt at
## a time. The walk styles above work the same way (only one walk can play at
## once); the aura can be combined with anything.
## "tex" points at the front-design image (assets/) drawn on the torso.
## To add one: drop a front-design PNG in assets/ and add a line here.
const SHIRT_ITEMS := [
	{"id": "shirt_ironlion", "kind": "shirt", "name": "IronLion", "desc": "Royal lion crest with crossed axes", "price": 100, "tex": "res://assets/shirt_ironlion.png"},
	{"id": "shirt_algeria", "kind": "shirt", "name": "Algeria", "desc": "Green and white national football jersey", "price": 100, "tex": "res://assets/shirt_algeria.png"},
	{"id": "shirt_cyberdragon", "kind": "shirt", "name": "CyberDragon", "desc": "Neon purple cyber-dragon hoodie", "price": 100, "tex": "res://assets/shirt_cyberdragon.png"},
	{"id": "shirt_phoenix", "kind": "shirt", "name": "Phoenix", "desc": "Glowing blue phoenix emblem", "price": 100, "tex": "res://assets/shirt_phoenix.png"},
	{"id": "shirt_rebel", "kind": "shirt", "name": "Rebel", "desc": "Graffiti-style hoodie print with a skull", "price": 100, "tex": "res://assets/shirt_rebel.png"},
]

## Online play. The server address is fixed below — the "Server" field was
## removed from the UI so people don't need to know or type an address; only
## "Play online" on/off and the account fields (name, username, password)
## show up in the Online card now.
const DEFAULT_SERVER_URL := "wss://m-sbid.onrender.com"
const NAME_MAX := 16
var online := false
var player_name := ""
var server_url := DEFAULT_SERVER_URL

## Real, server-checked account (added on top of the local "registered" flag
## below). Set once at sign-up; used every time the game joins the server so
## the same username always maps back to the same player, and a different
## device can't take an already-used username without the right password.
## The server only ever sees the SHA-256 hash, never the plain password.
var username := ""
var password_hash := ""

## Account. A brand-new install (no save file at all) starts with
## registered = false, so home.gd shows a one-time "create your account"
## screen that asks for a name before the Home screen appears. Anyone
## upgrading from before this existed already has a save file, so
## load_data() treats them as already registered (see its default below).
var registered := false

## UI language: "en" or "ar". Toggled from a button on the Home screen.
var lang := "en"

## Swatches shown on the Customize screen — a small slice of a
## Roblox-style body-color palette.
const PALETTE := [
	Color(0.98, 0.83, 0.1), Color(0.93, 0.93, 0.93), Color(0.62, 0.62, 0.62),
	Color(0.15, 0.15, 0.17), Color(0.85, 0.15, 0.15), Color(0.95, 0.45, 0.1),
	Color(0.95, 0.8, 0.2), Color(0.25, 0.7, 0.3), Color(0.1, 0.45, 0.85),
	Color(0.55, 0.25, 0.8), Color(0.9, 0.4, 0.7), Color(0.45, 0.28, 0.14),
]


func _ready() -> void:
	load_data()
	if player_name == "":
		player_name = "Player%d" % randi_range(1000, 9999)
		save_data()


func get_color(part: String) -> Color:
	match part:
		"head":
			return head_color
		"torso":
			return torso_color
		"arms":
			return arms_color
		"legs":
			return legs_color
	return Color.WHITE


func set_color(part: String, color: Color) -> void:
	match part:
		"head":
			head_color = color
		"torso":
			torso_color = color
		"arms":
			arms_color = color
		"legs":
			legs_color = color
	save_data()


func set_background(index: int) -> void:
	background = clampi(index, 0, BACKGROUNDS.size() - 1)
	save_data()


func set_dance(index: int) -> void:
	dance = clampi(index, 0, DANCES.size() - 1)
	save_data()


func add_coins(n: int) -> void:
	coins = maxi(coins + n, 0)
	save_data()


func shop_item(id: String) -> Dictionary:
	for it in SHOP_ITEMS:
		if String(it["id"]) == id:
			return it
	for it in SHIRT_ITEMS:
		if String(it["id"]) == id:
			return it
	return {}


func owns(id: String) -> bool:
	return owned.has(id)


func is_equipped(id: String) -> bool:
	return equipped.has(id)


## Items that can't be worn together belong to the same group: "shirt" (one
## shirt at a time) or "walk" (one walk style at a time). The aura has no group,
## so it can be combined with anything. Returns "" for items without a group.
func _group_of(id: String) -> String:
	var it := shop_item(id)
	if it.is_empty():
		return ""
	var kind := String(it.get("kind", ""))
	if kind == "shirt" or kind == "walk":
		return kind
	return ""


## Takes off whatever is currently worn from the same group as `id` (a no-op
## for items without a group, or if nothing else from the group is on).
func _unequip_group_of(id: String) -> void:
	var group := _group_of(id)
	if group == "":
		return
	for other in equipped.duplicate():
		var oid := String(other)
		if oid != id and _group_of(oid) == group:
			equipped.erase(other)


## Returns true if the purchase went through (enough coins, not owned yet).
## Buying an item equips it (and takes off anything it can't be worn with).
func buy(id: String) -> bool:
	var item := shop_item(id)
	if item.is_empty() or owns(id):
		return false
	var price := int(item["price"])
	if coins < price:
		return false
	coins -= price
	owned.append(id)
	_unequip_group_of(id)
	equipped.append(id)
	save_data()
	return true


func toggle_equip(id: String) -> void:
	if not owns(id):
		return
	if equipped.has(id):
		equipped.erase(id)
	else:
		_unequip_group_of(id)
		equipped.append(id)
	save_data()


## The texture path of the shirt currently worn, or "" if none is equipped.
func current_shirt_tex() -> String:
	for it in SHIRT_ITEMS:
		if equipped.has(String(it["id"])):
			return String(it["tex"])
	return ""


## The id of the shirt currently worn, or "" if none is equipped — sent to
## other players online so their view shows the same shirt (see net.gd).
func current_shirt_id() -> String:
	for it in SHIRT_ITEMS:
		var sid := String(it["id"])
		if equipped.has(sid):
			return sid
	return ""


## Looks up a shirt's texture path by id (used when receiving another
## player's chosen shirt over the network). Returns "" for an unknown id.
func shirt_tex_for_id(id: String) -> String:
	if id == "":
		return ""
	for it in SHIRT_ITEMS:
		if String(it["id"]) == id:
			return String(it["tex"])
	return ""


## 0 = the normal walk, 1 = Swagger Walk, 2 = Coin Runner, 3 = Angel Float.
func walk_style() -> int:
	if equipped.has("angel"):
		return 3
	if equipped.has("coinrun"):
		return 2
	if equipped.has("swagger"):
		return 1
	return 0


## The walk style number an item id stands for (0 = none), used to show every
## walk running on its own shop card.
func walk_style_for_id(id: String) -> int:
	match id:
		"swagger":
			return 1
		"coinrun":
			return 2
		"angel":
			return 3
	return 0


func aura_enabled() -> bool:
	return equipped.has("aura")


func set_online(on: bool) -> void:
	online = on
	save_data()


func set_player_name(n: String) -> void:
	var clean := n.strip_edges().substr(0, NAME_MAX)
	if clean == "":
		clean = "Player%d" % randi_range(1000, 9999)
	player_name = clean
	save_data()


func set_server_url(u: String) -> void:
	var clean := u.strip_edges()
	server_url = clean if clean != "" else DEFAULT_SERVER_URL
	save_data()


func set_lang(l: String) -> void:
	lang = l if (l == "en" or l == "ar") else "en"
	save_data()


func set_username(u: String) -> void:
	var clean := u.strip_edges().to_lower().substr(0, NAME_MAX)
	if clean == "":
		return
	username = clean
	save_data()


## Finishes the one-time sign-up screen: takes the chosen name, username and
## password and marks this device as a registered account so the screen
## never shows again. The password itself is never stored or sent anywhere —
## only its SHA-256 hash, which the server checks on every join (see net.gd)
## so nobody else can take the same username without knowing the password.
func register(chosen_name: String, chosen_user: String, chosen_pass: String) -> void:
	set_player_name(chosen_name)
	var clean_user := chosen_user.strip_edges().to_lower().substr(0, NAME_MAX)
	username = clean_user if clean_user != "" else player_name.to_lower()
	password_hash = chosen_pass.sha256_text() if chosen_pass != "" else ""
	registered = true
	save_data()


## What other players get to see about you.
func make_join_info() -> Dictionary:
	return {
		"name": player_name, "head": head_color, "torso": torso_color,
		"arms": arms_color, "legs": legs_color, "hair": hair_color,
		"walk": walk_style(), "aura": aura_enabled(), "shirt": current_shirt_id(),
		"username": username, "password_hash": password_hash,
	}


func dance_id() -> String:
	return String(DANCES[dance]["id"])


func dance_name() -> String:
	return String(DANCES[dance]["name"])


func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("avatar", "head", head_color)
	cfg.set_value("avatar", "torso", torso_color)
	cfg.set_value("avatar", "arms", arms_color)
	cfg.set_value("avatar", "legs", legs_color)
	cfg.set_value("avatar", "hair", hair_color)
	cfg.set_value("avatar", "background", background)
	cfg.set_value("avatar", "dance", dance)
	cfg.set_value("shop", "coins", coins)
	cfg.set_value("shop", "owned", owned)
	cfg.set_value("shop", "equipped", equipped)
	cfg.set_value("online", "enabled", online)
	cfg.set_value("online", "name", player_name)
	cfg.set_value("online", "server", server_url)
	cfg.set_value("account", "registered", registered)
	cfg.set_value("account", "lang", lang)
	cfg.set_value("account", "username", username)
	cfg.set_value("account", "password_hash", password_hash)
	cfg.save(SAVE_PATH)


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	head_color = cfg.get_value("avatar", "head", head_color)
	torso_color = cfg.get_value("avatar", "torso", torso_color)
	arms_color = cfg.get_value("avatar", "arms", arms_color)
	legs_color = cfg.get_value("avatar", "legs", legs_color)
	hair_color = cfg.get_value("avatar", "hair", hair_color)
	background = clampi(int(cfg.get_value("avatar", "background", background)), 0, BACKGROUNDS.size() - 1)
	dance = clampi(int(cfg.get_value("avatar", "dance", dance)), 0, DANCES.size() - 1)
	online = bool(cfg.get_value("online", "enabled", online))
	player_name = String(cfg.get_value("online", "name", player_name))
	# The server address is fixed in code, so an old saved address is ignored.
	server_url = DEFAULT_SERVER_URL
	coins = maxi(int(cfg.get_value("shop", "coins", coins)), 0)
	var o = cfg.get_value("shop", "owned", [])
	if o is Array:
		owned = o.duplicate()
	var e = cfg.get_value("shop", "equipped", [])
	if e is Array:
		equipped = []
		for eid in e:
			var sid := String(eid)
			# only owned items, no duplicates, and at most one per exclusive group
			if owned.has(sid) and not equipped.has(sid):
				_unequip_group_of(sid)
				equipped.append(sid)
	# A save file already existing (we only get this far if cfg.load()
	# above succeeded) means this is not a brand-new install, even if it
	# predates the "registered" key — so default it to true here, not in
	# the class-level declaration, which stays false for truly new installs.
	registered = bool(cfg.get_value("account", "registered", true))
	lang = String(cfg.get_value("account", "lang", lang))
	username = String(cfg.get_value("account", "username", username))
	password_hash = String(cfg.get_value("account", "password_hash", password_hash))
