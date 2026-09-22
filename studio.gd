extends Control
## The Studio — "Roblox Studio مصغّر" for Blocky World.
##
## Two modes (see Studio.open_mode when this scene starts):
##   Editor  — a top-down grid. Pick a tool from the palette on the right,
##             tap a cell to place it, drag to paint several at once. One
##             "بداية" (start) and at least one "نهاية" (finish) are required
##             before you can publish. A Trigger block opens a tiny script
##             box (see level_script.gd) — a few fixed commands, never real
##             code, so nothing a player writes can do anything but the
##             handful of things listed there.
##   Browse  — "ألعاب اللاعبين": the list of levels every other player has
##             published, fetched live from the server. Tap Play to try one
##             with your own character, colors, and walk — main.tscn builds
##             it fresh from the JSON, nothing is downloaded as code.
##
## Publishing sends the level's data to the server (see net.gd's
## publish_level RPC); the server stores it and tells every connected player
## right away, so a new level shows up for everyone without an app update.

const BlockyScript = preload("res://blocky.gd")

const UI_SIZE := Vector2i(720, 1280)
const C_BG := Color("#f2f3f5")
const C_SOFT := Color("#f0f0f2")
const C_TILE := Color("#e8edf5")
const C_INK := Color("#232326")
const C_INK_2 := Color("#6f7178")
const C_GREEN := Color("#22b25a")
const C_RED := Color("#d5473f")

const GRID_N := 16                    # 16 x 16 cells
const MAX_CELLS := 220                # published-level size cap (matches net.gd)
## "ramp" climbs 1 unit across the cell (rotate with the R field below);
## "bounce" / "speed" are Trigger blocks with the matching action already
## written for you — no code needed for the two most common parkour pieces.
const TOOLS := ["platform", "wall", "ramp", "coin", "bounce", "speed", "start", "finish", "trigger", "erase"]
const HEIGHT_TOOLS := ["platform", "wall"]   # the height stepper only affects these

var lang := "ar"
var _font: Font
var _font_bold: FontVariation
var _mouse_mode := false

## "edit" | "browse"
var mode := "edit"

# ------------------------------------------------------------- editor state
var cells := {}          # "gx,gy" -> {"t": type, "c": "#hex" (optional), "s": script text (trigger only)}
var tool := "platform"
var cur_height := 1        # 1..4, used for newly placed platform/wall cells
var level_speed_mult := 1.0 # 0.6..1.8, whole-level player speed
var level_jump_mult := 1.0  # 0.6..1.8, whole-level jump strength
var title_text := ""
var _painting := false
var _paint_touch_id := -1
var _last_paint := ""
var _publishing := false
var _pub_msg := ""
var _pub_msg_t := 0.0
var _pub_msg_ok := true

var _title_edit: LineEdit
var _script_edit: TextEdit
var _script_cell := ""     # which cell _script_edit is currently editing ("" = closed)
var _script_errors: Array = []

# 3D preview of your own avatar (top-left corner), just for a bit of life
var preview_container: SubViewportContainer
var preview_blocky # BlockyScript instance
var preview_yaw := 0.0

# ------------------------------------------------------------ browse state
var _levels: Array = []      # [{"id":..,"title":..,"author":..,"cells":int}]
var _levels_loading := false
var _levels_scroll := 0.0
var _play_requesting := ""


func _ready() -> void:
	get_window().content_scale_size = UI_SIZE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mouse_mode = OS.has_feature("pc")
	lang = Customization.lang

	_font = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.variation_embolden = 0.5
	_font_bold = fv

	mode = Studio.open_mode
	Studio.open_mode = ""

	_title_edit = LineEdit.new()
	_title_edit.visible = false
	_title_edit.max_length = 24
	_title_edit.context_menu_enabled = false
	_title_edit.add_theme_font_size_override("font_size", 26)
	_title_edit.add_theme_color_override("font_color", C_INK)
	_title_edit.add_theme_color_override("caret_color", C_INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = C_INK
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	_title_edit.add_theme_stylebox_override("normal", sb)
	_title_edit.add_theme_stylebox_override("focus", sb)
	_title_edit.text_submitted.connect(func(_s): _title_edit.release_focus())
	_title_edit.focus_exited.connect(func(): title_text = _title_edit.text; _title_edit.visible = false; DisplayServer.virtual_keyboard_hide())
	add_child(_title_edit)

	_script_edit = TextEdit.new()
	_script_edit.visible = false
	_script_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_script_edit.add_theme_font_size_override("font_size", 22)
	_script_edit.add_theme_color_override("font_color", C_INK)
	_script_edit.add_theme_color_override("caret_color", C_INK)
	_script_edit.add_theme_color_override("background_color", Color.WHITE)
	_script_edit.text_changed.connect(_on_script_changed)
	add_child(_script_edit)

	Net.level_published_result.connect(_on_level_published)
	Net.levels_list_received.connect(_on_levels_list)
	Net.level_added_live.connect(_on_level_added_live)
	Net.level_data_received.connect(_on_level_data)

	if mode == "browse":
		_refresh_levels()
	else:
		_build_preview()

	queue_redraw()


func _process(delta: float) -> void:
	_pub_msg_t = maxf(_pub_msg_t - delta, 0.0)
	if preview_blocky:
		preview_yaw += delta
		preview_blocky.rotation.y = sin(preview_yaw * 0.6) * 0.5
		preview_blocky.animate(delta, 0.5, true)
	queue_redraw()


# --------------------------------------------------------------- 3D preview
func _build_preview() -> void:
	preview_container = SubViewportContainer.new()
	preview_container.stretch = true
	preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview_container)
	var sub := SubViewport.new()
	sub.transparent_bg = true
	sub.own_world_3d = true
	preview_container.add_child(sub)
	var root := Node3D.new()
	sub.add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.68)
	e.ambient_light_energy = 1.1
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 36.0
	cam.position = Vector3(0.0, 1.05, 5.0)
	cam.current = true
	root.add_child(cam)
	preview_blocky = BlockyScript.new()
	root.add_child(preview_blocky)
	preview_blocky.build(Customization.head_color, Customization.torso_color,
		Customization.arms_color, Customization.arms_color,
		Customization.legs_color, Customization.legs_color,
		Customization.hair_color, false)
	preview_blocky.set_walk_style(Customization.walk_style())
	preview_blocky.set_aura(Customization.aura_enabled())


# ------------------------------------------------------------------- layout
func _grid_rect() -> Rect2:
	return Rect2(24.0, 148.0, 480.0, 480.0)


func _cell_px() -> float:
	return _grid_rect().size.x / float(GRID_N)


func _cell_rect(gx: int, gy: int) -> Rect2:
	var g := _grid_rect()
	var s := _cell_px()
	return Rect2(g.position + Vector2(gx * s, gy * s), Vector2(s, s))


func _cell_at(pos: Vector2) -> Vector2i:
	var g := _grid_rect()
	if not g.has_point(pos):
		return Vector2i(-1, -1)
	var s := _cell_px()
	var gx := int((pos.x - g.position.x) / s)
	var gy := int((pos.y - g.position.y) / s)
	return Vector2i(clampi(gx, 0, GRID_N - 1), clampi(gy, 0, GRID_N - 1))


func _key(gx: int, gy: int) -> String:
	return "%d,%d" % [gx, gy]


func _palette_rect(i: int) -> Rect2:
	return Rect2(528.0, 148.0 + float(i) * 54.0, 168.0, 50.0)


## "-" / value / "+" stepper, shared layout for height + the two level-wide
## sliders below it. `row` picks the y position; the three sub-rects are the
## minus button, the value label area, and the plus button.
func _stepper_rects(row: int) -> Dictionary:
	var y := 706.0 + float(row) * 58.0
	var r := Rect2(24.0, y, 480.0, 50.0)
	return {"row": r, "minus": Rect2(r.position, Vector2(50.0, 50.0)),
		"plus": Rect2(Vector2(r.end.x - 50.0, r.position.y), Vector2(50.0, 50.0))}


func _publish_rect() -> Rect2:
	return Rect2(24.0, 900.0, 480.0, 74.0)


func _clear_rect() -> Rect2:
	return Rect2(528.0, 900.0, 168.0, 74.0)


func _back_rect() -> Rect2:
	return Rect2(20.0, 24.0, 120.0, 60.0)


func _lang_rect() -> Rect2:
	return Rect2(size.x - 90.0, 24.0, 66.0, 52.0)


func _level_card_rect(i: int) -> Rect2:
	return Rect2(24.0, 148.0 + float(i) * 156.0 - _levels_scroll, size.x - 48.0, 140.0)


# ------------------------------------------------------------------ helpers
func _t(en: String, ar: String) -> String:
	return ar if lang == "ar" else en


func _box(r: Rect2, col: Color, radius: float = -1.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius) if radius >= 0.0 else int(minf(r.size.x, r.size.y) * 0.5))
	sb.anti_aliasing = true
	sb.draw(get_canvas_item(), r)


func _ring(r: Rect2, col: Color, radius: float, w: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.draw_center = false
	sb.set_corner_radius_all(int(radius))
	sb.set_border_width_all(int(w))
	sb.border_color = col
	sb.anti_aliasing = true
	sb.draw(get_canvas_item(), r)


func _text(pos: Vector2, s: String, fs: int, col: Color, bold: bool = false) -> void:
	draw_string(_font_bold if bold else _font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)


func _text_center(center: Vector2, s: String, fs: int, col: Color, bold: bool = false) -> void:
	var f := _font_bold if bold else _font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var base := center.y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	draw_string(f, Vector2(center.x - w * 0.5, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)


## Colour + short label shown for each tool / placed cell.
func _tool_look(id: String) -> Array:
	match id:
		"platform":
			return [Color("#9aa4b2"), _t("Platform", "منصة")]
		"wall":
			return [Color("#5b6472"), _t("Wall", "جدار")]
		"ramp":
			return [Color("#8a6d4a"), _t("Ramp", "منحدر")]
		"coin":
			return [Color("#f0b429"), _t("Coin", "عملة")]
		"bounce":
			return [Color("#2ec4d6"), _t("Bounce Pad", "مطب نطة")]
		"speed":
			return [Color("#ff8a3d"), _t("Speed Pad", "مطب سرعة")]
		"start":
			return [Color("#22b25a"), _t("Start", "بداية")]
		"finish":
			return [Color("#d5473f"), _t("Finish", "نهاية")]
		"trigger":
			return [Color("#7c5cff"), _t("Trigger + code", "مشغّل + كود")]
		_:
			return [Color("#c7c9cf"), _t("Erase", "مسح")]


# ---------------------------------------------------------------------- draw
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG, true)
	if mode == "browse":
		_draw_browse()
	else:
		_draw_editor()
	_box(_back_rect(), C_SOFT, 18.0)
	_text_center(_back_rect().get_center(), _t("< Back", "< رجوع"), 24, C_INK, true)
	_box(_lang_rect(), C_SOFT, 14.0)
	_text_center(_lang_rect().get_center(), "AR" if lang == "en" else "EN", 22, C_INK, true)


func _draw_editor() -> void:
	_text(Vector2(24.0, 46.0), _t("Studio", "استوديو البناء"), 40, C_INK, true)
	_text(Vector2(24.0, 78.0), _t("Build a level, add a bit of code, publish it for everyone",
		"اصنع خريطة، أضف شوية كود، وانشرها لكل اللاعبين"), 20, C_INK_2)

	if preview_container:
		var pr := Rect2(size.x - 150.0, 82.0, 130.0, 130.0)
		preview_container.position = pr.position
		preview_container.size = pr.size

	# title field
	var title_rect := Rect2(160.0, 96.0, 340.0, 44.0)
	if not _title_edit.visible:
		_box(title_rect, Color.WHITE, 14.0)
		_ring(title_rect, C_INK_2, 14.0, 1.0)
		var shown := title_text if title_text != "" else _t("Level title — tap to type", "اسم الخريطة — اضغط للكتابة")
		_text(Vector2(title_rect.position.x + 14.0, title_rect.get_center().y + 7.0), shown, 22, C_INK if title_text != "" else C_INK_2)

	# grid
	var g := _grid_rect()
	_box(g, Color.WHITE, 16.0)
	var s := _cell_px()
	for gy in GRID_N:
		for gx in GRID_N:
			var r := _cell_rect(gx, gy)
			var c: Dictionary = cells.get(_key(gx, gy), {})
			if c.size() > 0:
				var t := String(c["t"])
				var look := _tool_look(t)
				_box(r.grow(-1.5), look[0])
				if t == "trigger":
					_text_center(r.get_center(), "λ", 26, Color.WHITE, true)
				elif t == "start":
					_text_center(r.get_center(), "▶", 16, Color.WHITE, true)
				elif t == "finish":
					_text_center(r.get_center(), "🏁", 14, Color.WHITE)
				elif t == "bounce":
					_text_center(r.get_center(), "↑", 20, Color.WHITE, true)
				elif t == "speed":
					_text_center(r.get_center(), "»", 20, Color.WHITE, true)
				elif t == "ramp":
					var arrows := ["↑", "→", "↓", "←"]
					_text_center(r.get_center(), arrows[int(c.get("r", 0)) % 4], 20, Color.WHITE, true)
				elif t in HEIGHT_TOOLS and int(c.get("h", 1)) > 1:
					_text_center(r.get_center() + Vector2(0.0, -2.0), str(int(c["h"])), 18, Color.WHITE, true)
	# faint grid lines on top
	for i in (GRID_N + 1):
		draw_line(g.position + Vector2(i * s, 0.0), g.position + Vector2(i * s, g.size.y), Color(0, 0, 0, 0.05), 1.0)
		draw_line(g.position + Vector2(0.0, i * s), g.position + Vector2(g.size.x, i * s), Color(0, 0, 0, 0.05), 1.0)
	_ring(g, C_INK_2, 16.0, 1.0)

	# palette
	for i in TOOLS.size():
		var id: String = TOOLS[i]
		var r := _palette_rect(i)
		var on: bool = (tool == id)
		_box(r, C_INK if on else Color.WHITE, 16.0)
		var look := _tool_look(id)
		draw_rect(Rect2(r.position + Vector2(14.0, 14.0), Vector2(18.0, 18.0)), look[0] if id != "erase" else C_INK_2, true)
		_text(r.position + Vector2(42.0, 42.0), look[1], 20, Color.WHITE if on else C_INK, on)

	# height stepper — greyed out unless the current tool actually uses it
	var h_on := tool in HEIGHT_TOOLS
	_draw_stepper(0, _t("Height", "الارتفاع"), "%d" % cur_height, h_on)
	_draw_stepper(1, _t("Player speed", "سرعة اللاعب"), "×%.1f" % level_speed_mult, true)
	_draw_stepper(2, _t("Player jump", "قفزة اللاعب"), "×%.1f" % level_jump_mult, true)

	# cell count
	var used := cells.size()
	_text(Vector2(24.0, 890.0), ("%d / %d " % [used, MAX_CELLS]) + _t("cells used", "خلية مستخدمة"), 18, C_INK_2)

	# publish / clear
	var can_publish = _has_start() and _has_finish() and used > 0 and not _publishing
	_box(_publish_rect(), C_GREEN if can_publish else Color("#c9cbd1"), 20.0)
	_text_center(_publish_rect().get_center(), _t("Publish for everyone", "نشر للجميع"), 26, Color.WHITE, true)
	_box(_clear_rect(), Color("#f4d9d7"), 20.0)
	_text_center(_clear_rect().get_center(), _t("Clear", "تفريغ"), 22, C_RED, true)

	if _pub_msg_t > 0.0:
		_text_center(Vector2(size.x * 0.5, 996.0), _pub_msg, 22, C_GREEN if _pub_msg_ok else C_RED, true)
	elif not _has_start() or not _has_finish():
		_text_center(Vector2(size.x * 0.5, 996.0),
			_t("Needs one Start and at least one Finish", "لازم نقطة بداية ونهاية وحدة على الأقل"), 20, C_INK_2)

	if _script_cell != "":
		_draw_script_panel()


func _draw_script_panel() -> void:
	var r := Rect2(40.0, 300.0, 640.0, 560.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35), true)
	_box(r, Color.WHITE, 24.0)
	_text(r.position + Vector2(24.0, 40.0), _t("Trigger code", "كود المشغّل"), 28, C_INK, true)
	_text(r.position + Vector2(24.0, 72.0),
		_t("on_touch <action>  /  on_timer <secs> <action>", "عند_اللمس <أمر>  /  عند_الوقت <ثواني> <أمر>"),
		17, C_INK_2)
	_text(r.position + Vector2(24.0, 96.0),
		_t("actions: give_coins N, lose_coins N, win, lose, message text, teleport gx gy, speed mult secs, bounce",
			"الأوامر: اعطي_عملات ن، خصم_عملات ن، فوز، خسارة، رسالة نص، انتقل gx gy، سرعة مضاعف ثواني، نطة"),
		14, C_INK_2)

	var box := Rect2(r.position + Vector2(24.0, 130.0), Vector2(r.size.x - 48.0, 260.0))
	_script_edit.position = box.position
	_script_edit.size = box.size

	var ey := box.end.y + 16.0
	if _script_errors.size() > 0:
		_text(Vector2(box.position.x, ey + 14.0), _t("Lines not understood:", "أسطر ما فهمتها:"), 18, C_RED, true)
		for i in mini(_script_errors.size(), 4):
			_text(Vector2(box.position.x, ey + 40.0 + i * 24.0), "· " + String(_script_errors[i]), 16, C_RED)
	else:
		_text(Vector2(box.position.x, ey + 14.0), _t("Looks good!", "تمام، مفهوم!"), 18, C_GREEN, true)

	var done := Rect2(r.end.x - 160.0, r.end.y - 70.0, 136.0, 48.0)
	_box(done, C_INK, 16.0)
	_text_center(done.get_center(), _t("Done", "تم"), 22, Color.WHITE, true)


## "-" [ label: value ] "+"  — used for the height / speed / jump steppers.
func _draw_stepper(row: int, label: String, value: String, enabled: bool) -> void:
	var rects := _stepper_rects(row)
	var r: Rect2 = rects["row"]
	_box(r, Color.WHITE if enabled else C_SOFT, 14.0)
	var ink := C_INK if enabled else C_INK_2
	_box(rects["minus"], C_SOFT if enabled else C_TILE, 12.0)
	_text_center(rects["minus"].get_center(), "-", 26, ink, true)
	_box(rects["plus"], C_SOFT if enabled else C_TILE, 12.0)
	_text_center(rects["plus"].get_center(), "+", 26, ink, true)
	_text(r.position + Vector2(62.0, 32.0), label, 20, ink)
	_text_center(Vector2(r.end.x - 90.0, r.get_center().y), value, 22, ink, true)


func _draw_browse() -> void:
	_text(Vector2(24.0, 46.0), _t("Community Games", "ألعاب اللاعبين"), 36, C_INK, true)
	_text(Vector2(24.0, 78.0), _t("Levels other players built and published — play with your own character",
		"خرائط صنعها لاعبون ثانيون ونشروها — العب فيها بشخصيتك أنت"), 19, C_INK_2)

	if Net.state != Net.State.ONLINE:
		_text_center(Vector2(size.x * 0.5, 300.0),
			_t("Go online from Home to browse levels", "شغّل الاونلاين من الصفحة الرئيسية عشان تشوف الخرائط"), 22, C_INK_2)
		return
	if _levels_loading:
		_text_center(Vector2(size.x * 0.5, 300.0), _t("Loading...", "جاري التحميل..."), 22, C_INK_2)
		return
	if _levels.is_empty():
		_text_center(Vector2(size.x * 0.5, 300.0), _t("No levels published yet — be the first!", "ما في خرائط لسا — كن أول واحد!"), 22, C_INK_2)
		return

	for i in _levels.size():
		var r := _level_card_rect(i)
		if r.end.y < 140.0 or r.position.y > size.y:
			continue
		var lv: Dictionary = _levels[i]
		_box(r, Color.WHITE, 24.0)
		_text(r.position + Vector2(24.0, 40.0), String(lv.get("title", "?")), 26, C_INK, true)
		_text(r.position + Vector2(24.0, 70.0), _t("by ", "بواسطة ") + String(lv.get("author", "?")), 18, C_INK_2)
		_text(r.position + Vector2(24.0, 96.0), "%d " % int(lv.get("cells", 0)) + _t("blocks", "قطعة"), 16, C_INK_2)
		var play := Rect2(r.end.x - 148.0, r.get_center().y - 26.0, 124.0, 52.0)
		var busy := _play_requesting == String(lv.get("id", ""))
		_box(play, Color("#c9cbd1") if busy else C_GREEN, 16.0)
		_text_center(play.get_center(), _t("...", "...") if busy else _t("Play", "لعب"), 22, Color.WHITE, true)


# ----------------------------------------------------------------- editing
func _has_start() -> bool:
	for k in cells:
		if cells[k]["t"] == "start":
			return true
	return false


func _has_finish() -> bool:
	for k in cells:
		if cells[k]["t"] == "finish":
			return true
	return false


func _place(gx: int, gy: int) -> void:
	var key := _key(gx, gy)
	if tool == "erase":
		cells.erase(key)
		return
	if tool == "ramp" and cells.has(key) and cells[key]["t"] == "ramp":
		cells[key]["r"] = (int(cells[key].get("r", 0)) + 1) % 4 # tap an existing ramp to spin it
		return
	if cells.size() >= MAX_CELLS and not cells.has(key):
		return
	if tool == "start" or tool == "finish":
		# only one of each — clear any previous one first
		for k in cells.keys():
			if cells[k]["t"] == tool:
				cells.erase(k)
	if tool == "trigger":
		cells[key] = {"t": "trigger", "s": String(cells.get(key, {}).get("s", ""))}
		_open_script(key)
		return
	if tool == "ramp":
		cells[key] = {"t": "ramp", "r": 0}
		return
	if tool in HEIGHT_TOOLS:
		cells[key] = {"t": tool, "h": cur_height}
		return
	cells[key] = {"t": tool}


func _open_script(key: String) -> void:
	_script_cell = key
	_script_edit.text = String(cells[key].get("s", ""))
	_on_script_changed()
	_script_edit.visible = true
	_script_edit.grab_focus()


func _close_script() -> void:
	if _script_cell != "" and cells.has(_script_cell):
		cells[_script_cell]["s"] = _script_edit.text
	_script_cell = ""
	_script_edit.visible = false
	DisplayServer.virtual_keyboard_hide()


func _on_script_changed() -> void:
	_script_errors = LevelScript.parse(_script_edit.text)["errors"]


func _clear_all() -> void:
	cells.clear()
	title_text = ""
	_pub_msg = ""
	cur_height = 1
	level_speed_mult = 1.0
	level_jump_mult = 1.0


# ------------------------------------------------------------- publish/net
func _level_dict() -> Dictionary:
	var arr: Array = []
	for k in cells:
		var c: Dictionary = cells[k]
		var parts := String(k).split(",")
		var e := {"x": int(parts[0]), "y": int(parts[1]), "t": c["t"]}
		if c.has("s") and String(c["s"]).strip_edges() != "":
			e["s"] = String(c["s"])
		if c.has("h"):
			e["h"] = int(c["h"])
		if c.has("r"):
			e["r"] = int(c["r"])
		arr.append(e)
	return {"n": GRID_N, "cells": arr, "speed_mult": level_speed_mult, "jump_mult": level_jump_mult}


func _publish() -> void:
	if _publishing or not _has_start() or not _has_finish() or cells.is_empty():
		return
	if Net.state != Net.State.ONLINE:
		_pub_msg = _t("Go online from Home first", "شغّل الاونلاين من الصفحة الرئيسية أول")
		_pub_msg_ok = false; _pub_msg_t = 3.0
		return
	_publishing = true
	var meta := {"title": title_text if title_text != "" else _t("Untitled", "بلا اسم"), "author": Customization.player_name}
	Net.publish_level.rpc_id(1, meta, _level_dict())


func _on_level_published(ok: bool, code: String) -> void:
	_publishing = false
	_pub_msg_ok = ok
	match code:
		"ok":
			_pub_msg = _t("Published! Everyone can try it now", "تم النشر! يقدر الكل يجربها الحين")
		"save_failed":
			_pub_msg = _t("Server couldn't save it — try again", "تعذّر الحفظ على السيرفر، حاول مرة ثانية")
		_:
			_pub_msg = _t("Needs one Start and at least one Finish", "لازم نقطة بداية ونهاية وحدة على الأقل")
	_pub_msg_t = 3.5
	if ok:
		_clear_all()


func _refresh_levels() -> void:
	if Net.state != Net.State.ONLINE:
		return
	_levels_loading = true
	Net.request_levels.rpc_id(1)


func _on_levels_list(list: Array) -> void:
	_levels = list
	_levels_loading = false


func _on_level_added_live(meta: Dictionary) -> void:
	if mode == "browse":
		_levels.insert(0, meta)


func _on_level_data(meta: Dictionary, data: Dictionary) -> void:
	_play_requesting = ""
	if data.is_empty():
		return # level was removed / couldn't be read — silently ignore the tap
	Studio.play_level({"meta": meta, "data": data})
	get_tree().change_scene_to_file("res://main.tscn")


# ------------------------------------------------------------------- input
func _press(pos: Vector2, idx: int) -> void:
	if _back_rect().has_point(pos):
		if _script_cell != "":
			_close_script()
		get_tree().change_scene_to_file("res://home.tscn")
		return
	if _lang_rect().has_point(pos):
		lang = "en" if lang == "ar" else "ar"
		Customization.set_lang(lang)
		return
	if mode == "browse":
		if Net.state == Net.State.ONLINE and _levels_loading == false and _levels.is_empty():
			pass
		for i in _levels.size():
			var r := _level_card_rect(i)
			var play := Rect2(r.end.x - 148.0, r.get_center().y - 26.0, 124.0, 52.0)
			if play.has_point(pos) and _play_requesting == "":
				var lv: Dictionary = _levels[i]
				_play_requesting = String(lv.get("id", ""))
				Net.request_level.rpc_id(1, _play_requesting)
				return
		return

	if _script_cell != "":
		var r := Rect2(40.0, 300.0, 640.0, 560.0)
		var done := Rect2(r.end.x - 160.0, r.end.y - 70.0, 136.0, 48.0)
		if done.has_point(pos) or not r.has_point(pos):
			_close_script()
		return

	var title_rect := Rect2(160.0, 96.0, 340.0, 44.0)
	if title_rect.has_point(pos):
		_title_edit.text = title_text
		_title_edit.position = title_rect.position
		_title_edit.size = title_rect.size
		_title_edit.visible = true
		_title_edit.grab_focus()
		_title_edit.caret_column = _title_edit.text.length()
		return

	for i in TOOLS.size():
		if _palette_rect(i).has_point(pos):
			tool = TOOLS[i]
			return

	if tool in HEIGHT_TOOLS:
		var hs := _stepper_rects(0)
		if hs["minus"].has_point(pos):
			cur_height = maxi(1, cur_height - 1); return
		if hs["plus"].has_point(pos):
			cur_height = mini(4, cur_height + 1); return
	var sp := _stepper_rects(1)
	if sp["minus"].has_point(pos):
		level_speed_mult = snappedf(clampf(level_speed_mult - 0.2, 0.6, 1.8), 0.1); return
	if sp["plus"].has_point(pos):
		level_speed_mult = snappedf(clampf(level_speed_mult + 0.2, 0.6, 1.8), 0.1); return
	var jp := _stepper_rects(2)
	if jp["minus"].has_point(pos):
		level_jump_mult = snappedf(clampf(level_jump_mult - 0.2, 0.6, 1.8), 0.1); return
	if jp["plus"].has_point(pos):
		level_jump_mult = snappedf(clampf(level_jump_mult + 0.2, 0.6, 1.8), 0.1); return

	if _publish_rect().has_point(pos):
		_publish()
		return
	if _clear_rect().has_point(pos):
		_clear_all()
		return

	var c := _cell_at(pos)
	if c.x >= 0:
		_painting = true
		_paint_touch_id = idx
		_last_paint = _key(c.x, c.y)
		_place(c.x, c.y)


func _drag(pos: Vector2, idx: int) -> void:
	if not _painting or idx != _paint_touch_id or tool == "start" or tool == "finish" or tool == "trigger":
		return
	var c := _cell_at(pos)
	if c.x < 0:
		return
	var key := _key(c.x, c.y)
	if key == _last_paint:
		return
	_last_paint = key
	_place(c.x, c.y)


func _release(idx: int) -> void:
	if idx == _paint_touch_id:
		_painting = false
		_paint_touch_id = -1


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press(t.position, t.index)
		else:
			_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.position, d.index)
	elif _mouse_mode and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb.position, 99)
			else:
				_release(99)
		elif mb.pressed and mode == "browse":
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_levels_scroll = maxf(_levels_scroll - 90.0, 0.0)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_levels_scroll += 90.0
	elif _mouse_mode and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_drag(mm.position, 99)
