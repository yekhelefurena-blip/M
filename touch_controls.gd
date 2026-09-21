extends Control
## Touch controls drawn and handled entirely in code.
## Left half: floating joystick.  Right half: drag to rotate camera.
## Buttons: jump (bottom right), wave, dance, shadows toggle, shift-lock
## toggle (top right). Plus two overlays owned here too, since project settings
## disable touch->mouse emulation and real Controls can't receive taps:
## the "choose a minigame" menu, and the "Leave Parkour" pill.
## On desktop the mouse acts like a finger (for quick testing).
##
## Visual style: dark "glass" buttons with a light ring and crisp vector
## glyphs (no emoji / font dependencies). Glyphs are drawn around (0, 0) in
## a ~±26 box and placed with draw_set_transform(), so they scale cleanly.

signal jump_pressed
signal wave_pressed
signal dance_pressed
signal chat_pressed        # open the chat box
signal chat_send_pressed   # "Send" inside the chat box
signal chat_cancel_pressed # tapped outside the chat box
signal shadows_pressed
signal lock_pressed
signal game_chosen(mode: String) # "coinrush" or "parkour"
signal leave_pressed
signal home_pressed # back to the Marketplace/Customize menu

const JOY_R := 120.0

# --- look ---
const ACCENT := Color(1.0, 0.85, 0.2)
const ICON := Color(1.0, 1.0, 1.0, 1.0)
const HOLE := Color(0.09, 0.10, 0.16, 1.0) # "cut-out" colour inside glyphs
const BTN_BG := Color(0.07, 0.08, 0.13, 0.58)
const BTN_BG_HOT := Color(0.22, 0.24, 0.34, 0.78)
const BTN_BG_ON := Color(0.32, 0.26, 0.05, 0.82)
const PANEL_BG := Color(0.05, 0.06, 0.10, 0.90)

# --- chat look ---
const CHAT_SHOW_TIME := 11.0 # seconds a message stays on screen (when the box is closed)
const CHAT_FS := 22
const NAME_FS := 20
const PAD_X := 14.0
const PAD_Y := 7.0
const NAME_COLORS := [
	Color("#ff8a80"), Color("#ffb74d"), Color("#fff176"), Color("#81c784"),
	Color("#4dd0e1"), Color("#64b5f6"), Color("#ba68c8"), Color("#f48fb1"),
]

var move_vec := Vector2.ZERO
var cam_delta := Vector2.ZERO

var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _cam_id := -1
var _flash := {"jump": 0.0, "wave": 0.0, "dance": 0.0, "shadow": 0.0, "lock": 0.0, "home": 0.0, "chat": 0.0}
var _mouse_mode := false
var _lock_on := false

var menu_open := false
var parkour_active := false
## main.gd keeps this up to date so the DANCE button lights up while dancing.
var dance_on := false
## main.gd keeps this up to date so the sun icon shows a slash when shadows are off.
var shadows_on := true

## Online chat (all set by main.gd). The chat *log* is drawn here; the text box
## itself is a real LineEdit that main.gd places at chat_edit_rect().
var chat_available := false # show the chat button (only while connected)
var chat_open := false
var chat_lines: Array = []  # {name, text, age, sys}
var online_status := ""

var _font: Font
var _font_bold: Font
var _sb := StyleBoxFlat.new() # reused for every rounded panel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mouse_mode = OS.has_feature("pc")
	_font = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.variation_embolden = 0.5
	_font_bold = fv


func set_lock_state(on: bool) -> void:
	_lock_on = on


func open_game_menu() -> void:
	menu_open = true


func close_game_menu() -> void:
	menu_open = false


func set_parkour_active(active: bool) -> void:
	parkour_active = active


func _btn_pos(b: String) -> Vector2:
	match b:
		"jump":
			return Vector2(size.x - 150.0, size.y - 150.0)
		"wave":
			return Vector2(size.x - 310.0, size.y - 100.0)
		"dance":
			return Vector2(size.x - 300.0, size.y - 225.0)
		"chat":
			return Vector2(size.x - 80.0, 320.0)
		"lock":
			return Vector2(size.x - 80.0, 160.0)
		"home":
			return Vector2(size.x - 80.0, 240.0)
	return Vector2(size.x - 80.0, 80.0)


func _btn_radius(b: String) -> float:
	match b:
		"jump":
			return 72.0
		"wave":
			return 50.0
		"dance":
			return 46.0
	return 36.0


# ------------------------------------------------------------ chat layout

func chat_input_rect() -> Rect2:
	return Rect2(16.0, 76.0, minf(size.x - 32.0, 720.0), 66.0)


## Where main.gd should put the LineEdit (between the bubble icon and Send).
func chat_edit_rect() -> Rect2:
	var r := chat_input_rect()
	return Rect2(r.position.x + 58.0, r.position.y + 6.0, r.size.x - 58.0 - 78.0, r.size.y - 12.0)


## Tap area of the Send button (full height of the box, right end).
func _chat_send_rect() -> Rect2:
	var r := chat_input_rect()
	return Rect2(r.end.x - 72.0, r.position.y, 72.0, r.size.y)


func _send_center() -> Vector2:
	var r := chat_input_rect()
	return Vector2(r.end.x - 38.0, r.get_center().y)


## Called when the chat box opens so a held joystick doesn't keep running.
func reset_touches() -> void:
	_joy_id = -1
	_cam_id = -1
	move_vec = Vector2.ZERO


func _menu_rect(which: int) -> Rect2:
	var w := 440.0
	var h := 104.0
	var cx := size.x * 0.5
	var cy := size.y * 0.5 + (float(which) - 0.5) * (h + 22.0)
	return Rect2(cx - w * 0.5, cy - h * 0.5, w, h)


func _leave_rect() -> Rect2:
	var w := 320.0
	var h := 66.0
	return Rect2(size.x * 0.5 - w * 0.5, 20.0, w, h)


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.index, d.position, d.relative)
	elif _mouse_mode:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_press(99, mb.position)
				else:
					_release(99)
		elif event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				_drag(99, mm.position, mm.relative)


func _press(id: int, pos: Vector2) -> void:
	# while the chat box is open it owns every tap
	if chat_open:
		if _chat_send_rect().has_point(pos):
			_flash["chat"] = 0.15
			chat_send_pressed.emit()
		elif not chat_input_rect().has_point(pos):
			chat_cancel_pressed.emit()
		return
	# The game-choice menu and the "leave parkour" pill take priority over
	# everything else, and swallow the touch either way while open.
	if menu_open:
		if _menu_rect(0).has_point(pos):
			_flash["jump"] = 0.15
			menu_open = false
			game_chosen.emit("coinrush")
		elif _menu_rect(1).has_point(pos):
			_flash["jump"] = 0.15
			menu_open = false
			game_chosen.emit("parkour")
		return
	if parkour_active and _leave_rect().has_point(pos):
		leave_pressed.emit()
		return

	for b in ["jump", "wave", "dance", "shadow", "lock", "home", "chat"]:
		if b == "chat" and not chat_available:
			continue
		if pos.distance_to(_btn_pos(b)) <= _btn_radius(b) + 14.0:
			_flash[b] = 0.15
			if b == "jump":
				jump_pressed.emit()
			elif b == "wave":
				wave_pressed.emit()
			elif b == "dance":
				dance_pressed.emit()
			elif b == "chat":
				chat_pressed.emit()
			elif b == "shadow":
				shadows_pressed.emit()
			elif b == "lock":
				lock_pressed.emit()
			else:
				home_pressed.emit()
			return
	if pos.x < size.x * 0.5:
		if _joy_id == -1:
			_joy_id = id
			_joy_origin = pos
			_joy_pos = pos
	else:
		if _cam_id == -1:
			_cam_id = id


func _release(id: int) -> void:
	if id == _joy_id:
		_joy_id = -1
		move_vec = Vector2.ZERO
	elif id == _cam_id:
		_cam_id = -1


func _drag(id: int, pos: Vector2, rel: Vector2) -> void:
	if menu_open or (parkour_active and id == 99 and _leave_rect().has_point(pos)):
		return
	if id == _joy_id:
		var d := pos - _joy_origin
		if d.length() > JOY_R:
			d = d.normalized() * JOY_R
		_joy_pos = _joy_origin + d
		var v := d / JOY_R
		move_vec = v if v.length() > 0.15 else Vector2.ZERO
	elif id == _cam_id:
		cam_delta += rel


func _process(delta: float) -> void:
	for k in _flash.keys():
		_flash[k] = maxf(0.0, _flash[k] - delta)
	queue_redraw()


func _hot(k: String) -> bool:
	return float(_flash[k]) > 0.0


# ---------------------------------------------------------- draw helpers

## Rounded rectangle via the shared StyleBoxFlat (optional border + soft shadow).
func _panel(r: Rect2, bg: Color, radius: float, border_w: int = 0, border_col: Color = Color.TRANSPARENT, shadow_size: int = 0, shadow_col: Color = Color(0, 0, 0, 0.3)) -> void:
	_sb.bg_color = bg
	_sb.set_corner_radius_all(int(roundf(radius)))
	_sb.anti_aliasing = true
	_sb.set_border_width_all(border_w)
	_sb.border_color = border_col
	_sb.shadow_size = shadow_size
	_sb.shadow_color = shadow_col
	_sb.shadow_offset = Vector2(0.0, float(shadow_size) * 0.35)
	_sb.draw(get_canvas_item(), r)


## Filled rounded rectangle as a polygon (safe inside draw_set_transform()).
func _rrect(r: Rect2, rad: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var corners: Array[Vector2] = [
		r.position + Vector2(rad, rad),
		Vector2(r.end.x - rad, r.position.y + rad),
		r.end - Vector2(rad, rad),
		Vector2(r.position.x + rad, r.end.y - rad),
	]
	var starts: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
	for i in 4:
		for s in 5:
			var a: float = starts[i] + (PI * 0.5) * float(s) / 4.0
			pts.append(corners[i] + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, col)


## Line with round ends.
func _cap(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	draw_line(a, b, col, w, true)
	draw_circle(a, w * 0.5, col)
	draw_circle(b, w * 0.5, col)


func _gx(c: Vector2, k: float, rot: float = 0.0) -> void:
	draw_set_transform(c, rot, Vector2(k, k))


func _gx_end() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _text_c(font: Font, center: Vector2, s: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var base := center.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(center.x - w * 0.5, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)


## Glass button: soft shadow, dark translucent disc, light ring, top highlight.
func _round_btn(c: Vector2, rad: float, hot: bool, on: bool = false) -> void:
	draw_circle(c + Vector2(0.0, 5.0), rad + 3.0, Color(0, 0, 0, 0.20))
	var bg := BTN_BG
	if on:
		bg = BTN_BG_ON
	elif hot:
		bg = BTN_BG_HOT
	draw_circle(c, rad, bg)
	var ring := ACCENT if on else Color(1, 1, 1, 0.55)
	draw_arc(c, rad - 1.5, 0.0, TAU, 56, ring, 3.0, true)
	draw_arc(c, rad - 7.0, PI * 1.15, PI * 1.85, 20, Color(1, 1, 1, 0.16), 3.0, true)


# ----------------------------------------------------------------- glyphs
# All drawn around (0, 0); call _gx() before and _gx_end() after.

func _g_jump(col: Color) -> void:
	_cap(Vector2(0, 22), Vector2(0, -14), 9.0, col)
	_cap(Vector2(-19, -2), Vector2(0, -22), 9.0, col)
	_cap(Vector2(19, -2), Vector2(0, -22), 9.0, col)


func _g_hand(col: Color) -> void:
	_cap(Vector2(-3, 10), Vector2(3, 10), 26.0, col)             # palm
	var xs: Array[float] = [-12.0, -4.0, 4.0, 12.0]
	var tops: Array[float] = [-14.0, -22.0, -20.0, -10.0]
	for i in 4:
		_cap(Vector2(xs[i], 6.0), Vector2(xs[i], tops[i]), 7.5, col)
	_cap(Vector2(-13, 12), Vector2(-24, 1), 8.0, col)            # thumb


func _g_note(col: Color) -> void:
	draw_circle(Vector2(-10, 17), 7.0, col)
	draw_circle(Vector2(12, 11), 7.0, col)
	draw_line(Vector2(-4, 17), Vector2(-4, -16), col, 4.0, true)
	draw_line(Vector2(18, 11), Vector2(18, -22), col, 4.0, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-6, -17), Vector2(20, -25), Vector2(20, -15), Vector2(-6, -7)]), col)


func _g_chat(col: Color, hole: Color) -> void:
	_rrect(Rect2(-20, -17, 40, 28), 9.0, col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-10, 8), Vector2(-13, 20), Vector2(4, 8)]), col)
	for i in 3:
		draw_circle(Vector2(-9.0 + 9.0 * float(i), -3.0), 3.0, hole)


func _g_sun(col: Color, slashed: bool) -> void:
	draw_circle(Vector2.ZERO, 9.0, col)
	for i in 8:
		var d := Vector2.RIGHT.rotated(TAU * float(i) / 8.0)
		draw_line(d * 14.5, d * 21.0, col, 4.0, true)
	if slashed:
		_cap(Vector2(-20, -20), Vector2(20, 20), 9.0, HOLE)
		_cap(Vector2(-20, -20), Vector2(20, 20), 4.0, Color(1.0, 0.45, 0.45))


func _g_lock(col: Color, closed: bool) -> void:
	if closed:
		draw_arc(Vector2(0, -4), 9.0, PI, TAU, 20, col, 4.0, true)
		draw_line(Vector2(-9, -4), Vector2(-9, 1), col, 4.0, true)
		draw_line(Vector2(9, -4), Vector2(9, 1), col, 4.0, true)
	else:
		draw_arc(Vector2(0, -11), 9.0, PI, TAU, 20, col, 4.0, true)
		draw_line(Vector2(9, -11), Vector2(9, -1), col, 4.0, true)
	_rrect(Rect2(-13, -2, 26, 21), 5.0, col)
	draw_circle(Vector2(0, 7.5), 3.2, HOLE)
	draw_line(Vector2(0, 8.5), Vector2(0, 13.5), HOLE, 3.0, true)


func _g_home(col: Color) -> void:
	_rrect(Rect2(-15, -4, 30, 24), 3.0, col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -25), Vector2(-25, -2), Vector2(25, -2)]), col)
	draw_rect(Rect2(-4, 7, 8, 13), HOLE, true)


func _g_coin(col: Color) -> void:
	draw_circle(Vector2.ZERO, 19.0, col)
	draw_arc(Vector2.ZERO, 12.5, 0.0, TAU, 32, Color(col.r * 0.6, col.g * 0.5, 0.0, 0.9), 3.0, true)
	_cap(Vector2(-3, -6), Vector2(-3, 6), 3.0, Color(col.r * 0.6, col.g * 0.5, 0.0, 0.9))


func _g_mountain(col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-24, 17), Vector2(-7, -15), Vector2(3, 2), Vector2(10, -9), Vector2(24, 17)]), col)


# ------------------------------------------------------------------- draw

func _draw() -> void:
	if menu_open:
		_draw_menu()
		return # keep the choice front-and-center, no other buttons underneath

	_draw_chat()
	_draw_joystick()
	_draw_buttons()
	if parkour_active:
		_draw_leave()


func _draw_joystick() -> void:
	if _joy_id != -1:
		draw_circle(_joy_origin, JOY_R, Color(1, 1, 1, 0.12))
		draw_arc(_joy_origin, JOY_R, 0.0, TAU, 64, Color(1, 1, 1, 0.45), 3.0, true)
		draw_circle(_joy_pos + Vector2(0.0, 4.0), 50.0, Color(0, 0, 0, 0.18))
		draw_circle(_joy_pos, 48.0, Color(1, 1, 1, 0.55))
		draw_arc(_joy_pos, 48.0, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 2.5, true)
	else:
		var hint := Vector2(170.0, size.y - 150.0)
		draw_arc(hint, JOY_R, 0.0, TAU, 64, Color(1, 1, 1, 0.22), 3.0, true)
		draw_circle(hint, 46.0, Color(1, 1, 1, 0.12))


func _draw_buttons() -> void:
	# jump
	var jp := _btn_pos("jump")
	_round_btn(jp, _btn_radius("jump"), _hot("jump"))
	_gx(jp, 1.45)
	_g_jump(ICON)
	_gx_end()

	# wave (a little hand that wiggles when tapped)
	var wp := _btn_pos("wave")
	_round_btn(wp, _btn_radius("wave"), _hot("wave"))
	var wiggle := sin(float(Time.get_ticks_msec()) * 0.03) * 0.3 if _hot("wave") else 0.0
	_gx(wp + Vector2(0.0, 2.0), 1.2, -0.12 + wiggle)
	_g_hand(ICON)
	_gx_end()

	# dance (lights up while the avatar is dancing)
	var dp := _btn_pos("dance")
	_round_btn(dp, _btn_radius("dance"), _hot("dance"), dance_on)
	_gx(dp, 1.15)
	_g_note(ACCENT if dance_on else ICON)
	_gx_end()

	# chat button — only while connected to a server
	if chat_available:
		var cp := _btn_pos("chat")
		_round_btn(cp, _btn_radius("chat"), _hot("chat"))
		_gx(cp + Vector2(0.0, -1.0), 0.85)
		_g_chat(ICON, HOLE)
		_gx_end()

	# shadows (sun; slashed when shadows are off)
	var sp := _btn_pos("shadow")
	_round_btn(sp, _btn_radius("shadow"), _hot("shadow"))
	_gx(sp, 0.85)
	_g_sun(ICON if shadows_on else Color(1, 1, 1, 0.55), not shadows_on)
	_gx_end()

	# shift lock (padlock, closed + yellow while on)
	var lp := _btn_pos("lock")
	_round_btn(lp, _btn_radius("lock"), _hot("lock"), _lock_on)
	_gx(lp + Vector2(0.0, 1.0), 0.85)
	_g_lock(ACCENT if _lock_on else ICON, _lock_on)
	_gx_end()

	# home (back to Marketplace/Customize menu)
	var hp := _btn_pos("home")
	_round_btn(hp, _btn_radius("home"), _hot("home"))
	_gx(hp + Vector2(0.0, 1.0), 0.80)
	_g_home(ICON)
	_gx_end()


## "Leave parkour" pill (shown outside the menu too, once a run is active).
func _draw_leave() -> void:
	var r := _leave_rect()
	_panel(r, Color(0.08, 0.09, 0.13, 0.80), r.size.y * 0.5, 2, Color(1, 1, 1, 0.5), 10)
	var cy := r.get_center().y
	_cap(Vector2(r.position.x + 40.0, cy - 10.0), Vector2(r.position.x + 30.0, cy), 4.0, ICON)
	_cap(Vector2(r.position.x + 30.0, cy), Vector2(r.position.x + 40.0, cy + 10.0), 4.0, ICON)
	_text_c(_font_bold, Vector2(r.get_center().x + 14.0, cy), "LEAVE PARKOUR", 25, Color(1, 1, 1, 0.97))


## Online status pill, recent chat messages, and the input box while typing.
func _draw_chat() -> void:
	var x := 20.0
	var wrap := minf(size.x * 0.46, 560.0)
	var log_y := 132.0

	if chat_open:
		_draw_chat_input()
		log_y = chat_input_rect().end.y + 14.0
	elif online_status != "":
		_draw_status_pill()

	# pick the newest messages that fit the free space (oldest first, newest at the bottom)
	var avail := size.y - log_y - (20.0 if chat_open else 250.0)
	var picked: Array = []
	var used := 0.0
	for i in range(chat_lines.size() - 1, -1, -1):
		var l: Dictionary = chat_lines[i]
		if not chat_open and float(l["age"]) >= CHAT_SHOW_TIME:
			break
		var lay := _layout_line(l, wrap)
		var need := float(lay["h"]) + 8.0
		if used + need > avail and not picked.is_empty():
			break
		used += need
		picked.push_front(lay)
		if picked.size() >= 8:
			break

	var y := log_y
	for it in picked:
		var d: Dictionary = it
		var age := float(d["age"])
		var a := 1.0 if chat_open else clampf((CHAT_SHOW_TIME - age) / 1.5, 0.0, 1.0)
		var t_in := clampf(age / 0.25, 0.0, 1.0)
		var ease_in := 1.0 - (1.0 - t_in) * (1.0 - t_in)
		a *= ease_in
		var bx := x - (1.0 - ease_in) * 36.0
		var bw := float(d["w"])
		var bh := float(d["h"])
		var txt := String(d["text"])
		if bool(d["sys"]):
			_panel(Rect2(bx, y, bw, bh), Color(0.25, 0.19, 0.03, 0.62 * a), 14.0)
			draw_circle(Vector2(bx + PAD_X + 3.0, y + bh * 0.5), 4.0, Color(1.0, 0.85, 0.3, a))
			draw_multiline_string(_font, Vector2(bx + PAD_X + 16.0, y + PAD_Y + _font.get_ascent(CHAT_FS)),
				txt, HORIZONTAL_ALIGNMENT_LEFT, wrap, CHAT_FS, -1, Color(1.0, 0.92, 0.6, a))
		else:
			_panel(Rect2(bx, y, bw, bh), Color(0.04, 0.05, 0.09, 0.62 * a), 14.0)
			var nm := String(d["name"])
			var nc := _name_color(nm)
			nc.a = a
			var name_w := float(d["name_w"])
			if bool(d["inline"]):
				var base := y + PAD_Y + maxf(_font.get_ascent(CHAT_FS), _font_bold.get_ascent(NAME_FS))
				draw_string(_font_bold, Vector2(bx + PAD_X, base), nm, HORIZONTAL_ALIGNMENT_LEFT, -1.0, NAME_FS, nc)
				draw_string(_font, Vector2(bx + PAD_X + name_w + 10.0, base), txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, CHAT_FS, Color(1, 1, 1, a))
			else:
				var nh := _font_bold.get_height(NAME_FS)
				draw_string(_font_bold, Vector2(bx + PAD_X, y + PAD_Y + _font_bold.get_ascent(NAME_FS)), nm,
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, NAME_FS, nc)
				draw_multiline_string(_font, Vector2(bx + PAD_X, y + PAD_Y + nh + _font.get_ascent(CHAT_FS)),
					txt, HORIZONTAL_ALIGNMENT_LEFT, wrap, CHAT_FS, -1, Color(1, 1, 1, a))
		y += bh + 8.0


func _name_color(nm: String) -> Color:
	var c: Color = NAME_COLORS[absi(nm.hash()) % NAME_COLORS.size()]
	return c


## Measures one chat line. Short messages share a row with the sender's name;
## long ones wrap underneath it.
func _layout_line(l: Dictionary, wrap: float) -> Dictionary:
	var txt := String(l["text"])
	var nm := String(l["name"])
	var is_sys: bool = l["sys"]
	var out := {"sys": is_sys, "name": nm, "text": txt, "age": float(l["age"]),
		"inline": false, "name_w": 0.0, "w": 0.0, "h": 0.0}
	if is_sys:
		var ssz := _font.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, wrap, CHAT_FS)
		out["w"] = ssz.x + PAD_X * 2.0 + 16.0
		out["h"] = ssz.y + PAD_Y * 2.0
		return out
	var name_w := _font_bold.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1.0, NAME_FS).x
	var one_w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CHAT_FS).x
	out["name_w"] = name_w
	if name_w + 10.0 + one_w <= wrap:
		var line_h := maxf(_font.get_height(CHAT_FS), _font_bold.get_height(NAME_FS))
		out["inline"] = true
		out["w"] = PAD_X * 2.0 + name_w + 10.0 + one_w
		out["h"] = line_h + PAD_Y * 2.0
	else:
		var msz := _font.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, wrap, CHAT_FS)
		out["w"] = PAD_X * 2.0 + maxf(name_w, msz.x)
		out["h"] = PAD_Y * 2.0 + _font_bold.get_height(NAME_FS) + msz.y
	return out


func _draw_status_pill() -> void:
	var tw := _font.get_string_size(online_status, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x
	var r := Rect2(16.0, 78.0, tw + 56.0, 38.0)
	_panel(r, Color(0.04, 0.05, 0.09, 0.58), 19.0)
	var dot := Color(0.35, 0.9, 0.5) if chat_available else Color(1.0, 0.72, 0.3)
	var dc := Vector2(r.position.x + 22.0, r.get_center().y)
	draw_circle(dc, 9.0, Color(dot.r, dot.g, dot.b, 0.28))
	draw_circle(dc, 5.0, dot)
	var base := r.get_center().y + (_font.get_ascent(20) - _font.get_descent(20)) * 0.5
	draw_string(_font, Vector2(r.position.x + 40.0, base), online_status,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(1, 1, 1, 0.95))


## The chat box: rounded glass bar, bubble icon on the left, round Send on the right.
## (The text itself is the LineEdit main.gd places at chat_edit_rect().)
func _draw_chat_input() -> void:
	var r := chat_input_rect()
	_panel(r, PANEL_BG, r.size.y * 0.5, 2, Color(1, 1, 1, 0.35), 14, Color(0, 0, 0, 0.35))
	_gx(Vector2(r.position.x + 33.0, r.get_center().y), 0.62)
	_g_chat(Color(1, 1, 1, 0.75), PANEL_BG)
	_gx_end()

	var sc := _send_center()
	var send_col := Color(0.30, 0.90, 0.52) if _hot("chat") else Color(0.16, 0.78, 0.40)
	draw_circle(sc, 27.0, send_col)
	draw_arc(sc, 26.0, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 2.0, true)
	# paper plane
	draw_colored_polygon(PackedVector2Array([
		sc + Vector2(-11, -12), sc + Vector2(15, 0), sc + Vector2(-11, 12), sc + Vector2(-6, 0)]), Color.WHITE)


func _draw_menu() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.62), true)

	var titles := ["Coin Rush", "Parkour"]
	var subs := ["Grab coins in 45s", "Climb the parkour course"]
	var cols := [Color(1.0, 0.8, 0.2), Color(0.35, 0.85, 0.55)]
	for i in 2:
		var r := _menu_rect(i)
		var c: Color = cols[i]
		_panel(r, Color(0.08, 0.09, 0.14, 0.94), 26.0, 3, Color(c.r, c.g, c.b, 0.9), 16, Color(0, 0, 0, 0.4))
		var ic := Vector2(r.position.x + 58.0, r.get_center().y)
		draw_circle(ic, 34.0, Color(c.r, c.g, c.b, 0.22))
		draw_arc(ic, 34.0, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.8), 2.5, true)
		_gx(ic, 0.95)
		if i == 0:
			_g_coin(c)
		else:
			_g_mountain(c)
		_gx_end()
		draw_string(_font_bold, Vector2(r.position.x + 108.0, r.position.y + 45.0), String(titles[i]),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 32, Color(1, 1, 1, 0.98))
		draw_string(_font, Vector2(r.position.x + 108.0, r.position.y + 78.0), String(subs[i]),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(1, 1, 1, 0.72))
		var cx := r.end.x - 32.0
		var cy := r.get_center().y
		_cap(Vector2(cx - 5.0, cy - 11.0), Vector2(cx + 5.0, cy), 4.0, Color(1, 1, 1, 0.7))
		_cap(Vector2(cx + 5.0, cy), Vector2(cx - 5.0, cy + 11.0), 4.0, Color(1, 1, 1, 0.7))

	_text_c(_font_bold, Vector2(size.x * 0.5, _menu_rect(0).position.y - 44.0), "Choose a game", 32, Color(1, 1, 1, 0.97))
