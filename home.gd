extends Control
## Home screen — shown first instead of dropping straight into gameplay.
## White theme, portrait layout (720 x 1280 logical pixels).
##
##   - A pill toggle at the top switches between three tabs:
##       "Home" (formerly "Marketplace"): list of games (Blocky World first;
##                      append more later).
##       "Shop":        spend the coins you collected (saved between sessions).
##                      Two sub-tabs: "Items" (Swagger Walk, Coin Runner,
##                      Rainbow Aura, Angel Float — each card shows a real 3D
##                      avatar running with it; switch on/off) and
##                      "Shirts" (wearable shirt designs, 100 coins each,
##                      shown on the torso — only one worn at a time).
##       "Customize":   recolor head / torso / arms / legs, pick a backdrop,
##                      or pick which dance the avatar performs (the
##                      "Dances" chip), with a live 3D preview in front.
##   - The Home tab also has an "Online" card: switch online play on/off,
##     and edit your player name and the server address (a LineEdit pops up).
##   - In Customize, the round camera button hides every panel ("photo mode")
##     so people can take a clean screenshot. Tap anywhere to come back.
##   - A brand-new install first sees a one-time "create your account"
##     screen (see _draw_register()) that asks for a name before Home shows.
##   - A small EN/AR button (top-right of the header) switches the UI's
##     language; see the STR dictionary and _t() below. Text is translated;
##     the hand-drawn layout itself always stays left-to-right.
##
## The project runs with pointing/emulate_mouse_from_touch = false, so real
## Button/Control nodes can't receive taps (see touch_controls.gd). This
## screen is drawn and hit-tested by hand the same way, for consistency.

const BlockyScript = preload("res://blocky.gd")

const TAB_MARKET := "marketplace" # internal id only — the label shown is "Home"
const TAB_CUSTOMIZE := "customize"
const TAB_SHOP := "shop"
const TAB_KEYS := [TAB_MARKET, TAB_SHOP, TAB_CUSTOMIZE] # left -> right
const SHOP_SEC_ITEMS := "items"   # Shop sub-tab: walk styles / aura
const SHOP_SEC_SHIRTS := "shirts" # Shop sub-tab: wearable shirt designs
const SHOP_SEC_KEYS: Array[String] = [SHOP_SEC_ITEMS, SHOP_SEC_SHIRTS]
const PART_BG := "background" # 5th chip: backdrop picker instead of colors
const PART_DANCE := "dances"  # 6th chip: dance picker instead of colors
const PART_KEYS := ["head", "torso", "arms", "legs", PART_BG, PART_DANCE]
const SHOP_CARD_STEP := 256.0 # distance between two Shop cards (card height 232 + gap)
const CHIP_FONT := 22
const CHIP_GAP := 10.0
const EDIT_NAME := "name"
const EDIT_USERNAME := "username" # replaces the old, now-hidden "server" field
const EDIT_REG_NAME := "reg_name"     # sign-up screen, row 1
const EDIT_REG_USER := "reg_user"     # sign-up screen, row 2
const EDIT_REG_PASS := "reg_pass"     # sign-up screen, row 3 (masked)

## UI text in English and Arabic, looked up through _t(key). Keeping every
## string in one place (instead of translating call sites individually)
## means adding a language later only means adding a row here.
const STR := {
	"en": {
		"tab_home": "Home", "tab_shop": "Shop", "tab_customize": "Customize",
		"part_head": "Head", "part_torso": "Torso", "part_arms": "Arms", "part_legs": "Legs",
		"part_background": "Background", "part_dances": "Dances",
		"play": "Play", "items": "Items", "coins_hint": "Collect coins in the game",
		"buy_fmt": "Buy  %d", "equip": "Equip", "equipped": "Equipped",
		"recommended": "Recommended for you", "blocky_world": "Blocky World",
		"world_desc": "Explore, collect coins, and try the Parkour course",
		"rating": "Rating: 100%", "more_worlds": "More worlds are coming soon",
		"studio_title": "Studio", "studio_desc": "Build your own level and publish it for everyone",
		"community_title": "Community Games", "community_desc": "Play levels other players published",
		"more_items": "More items are coming soon", "play_with_others": "Play with others",
		"play_online": "Play online", "play_online_desc": "See other players and chat",
		"your_name": "Your name", "server": "Server", "edit": "Edit",
		"username": "Username", "password": "Password",
		"tap_exit": "Tap anywhere to exit",
		"name_title": "Your name", "server_title": "Server address",
		"edit_hint": "Press Enter / Done to save. Tap outside to save too.",
		"welcome_title": "Welcome!", "welcome_sub": "Choose a name other players will see",
		"create_account": "Create Account",
		"reg_missing": "Enter a username and password",
		"swagger_name": "Swagger Walk", "swagger_desc": "A cool strut with swinging hips",
		"aura_name": "Rainbow Aura", "aura_desc": "Glowing rings and sparks around you",
		"coinrun_name": "Coin Runner", "coinrun_desc": "Bouncy, energetic stride with a little hop on every step",
		"angel_name": "Angel Float", "angel_desc": "Angel wings, hover above the ground and fly when you move",
		"equipped_fmt": "%s equipped", "turned_off_fmt": "%s turned off",
		"bought_fmt": "Bought %s!", "not_enough_fmt": "Not enough coins — %s costs %d",
		"shop_sec_items": "Items", "shop_sec_shirts": "Shirts",
		"shirt_ironlion_name": "IronLion", "shirt_ironlion_desc": "Royal lion crest with crossed axes",
		"shirt_algeria_name": "Algeria", "shirt_algeria_desc": "Green and white national football jersey",
		"shirt_cyberdragon_name": "CyberDragon", "shirt_cyberdragon_desc": "Neon purple cyber-dragon hoodie",
		"shirt_phoenix_name": "Phoenix", "shirt_phoenix_desc": "Glowing blue phoenix emblem",
		"shirt_rebel_name": "Rebel", "shirt_rebel_desc": "Graffiti-style hoodie print with a skull",
	},
	"ar": {
		"tab_home": "الرئيسية", "tab_shop": "المتجر", "tab_customize": "تخصيص",
		"part_head": "الرأس", "part_torso": "الجذع", "part_arms": "الأذرع", "part_legs": "الأرجل",
		"part_background": "الخلفية", "part_dances": "الرقصات",
		"play": "لعب", "items": "العناصر", "coins_hint": "اجمع العملات داخل اللعبة",
		"buy_fmt": "شراء  %d", "equip": "تجهيز", "equipped": "مُجهَّز",
		"recommended": "موصى به لك", "blocky_world": "بلوكي وورلد",
		"world_desc": "استكشف، اجمع العملات، وجرّب مسار الباركور",
		"rating": "التقييم: 100%", "more_worlds": "عوالم جديدة قريبًا",
		"studio_title": "استوديو البناء", "studio_desc": "اصنع خريطتك الخاصة وانشرها لكل اللاعبين",
		"community_title": "ألعاب اللاعبين", "community_desc": "العب خرائط صنعها لاعبون ثانيون",
		"more_items": "عناصر جديدة قريبًا", "play_with_others": "العب مع الآخرين",
		"play_online": "اللعب أونلاين", "play_online_desc": "شاهد اللاعبين الآخرين وتحدث معهم",
		"your_name": "اسمك", "server": "الخادم", "edit": "تعديل",
		"username": "اسم المستخدم", "password": "كلمة المرور",
		"tap_exit": "اضغط في أي مكان للخروج",
		"name_title": "اسمك", "server_title": "عنوان الخادم",
		"edit_hint": "اضغط Enter أو تم للحفظ. اللمس خارج المربع يحفظ أيضًا.",
		"welcome_title": "أهلًا بك!", "welcome_sub": "اختر اسمًا سيظهر للاعبين الآخرين",
		"create_account": "إنشاء حساب",
		"reg_missing": "أدخل اسم مستخدم وكلمة مرور",
		"swagger_name": "مشية العرض", "swagger_desc": "مشية أنيقة مع تمايل الوركين",
		"aura_name": "هالة قوس قزح", "aura_desc": "حلقات متوهجة وشرر يحيط بك",
		"coinrun_name": "عدّاء العملات", "coinrun_desc": "خطوة نشيطة مع قفزة صغيرة في كل خطوة",
		"angel_name": "مشية الملاك", "angel_desc": "أجنحة ملاك، تطفو فوق الأرض وتطير لما تتحرك",
		"equipped_fmt": "تم تجهيز %s", "turned_off_fmt": "تم إيقاف %s",
		"bought_fmt": "تم شراء %s!", "not_enough_fmt": "العملات غير كافية — %s يكلّف %d",
		"shop_sec_items": "العناصر", "shop_sec_shirts": "القمصان",
		"shirt_ironlion_name": "الأسد الحديدي", "shirt_ironlion_desc": "شعار أسد ملكي مع فأسين متقاطعين",
		"shirt_algeria_name": "الجزائر", "shirt_algeria_desc": "قميص المنتخب الوطني بالأخضر والأبيض",
		"shirt_cyberdragon_name": "التنين السيبراني", "shirt_cyberdragon_desc": "هودي تنين بنفسجي متوهج بطابع سيبراني",
		"shirt_phoenix_name": "فينيكس", "shirt_phoenix_desc": "شعار طائر العنقاء المتوهج بالأزرق",
		"shirt_rebel_name": "ريبل", "shirt_rebel_desc": "طباعة هودي بأسلوب الغرافيتي مع جمجمة",
	},
}

## The home screen is portrait; the game itself is landscape 1280 x 720.
const UI_SIZE := Vector2i(720, 1280)
const COL_MAX := 720.0 # widest the content column gets (keeps desktop tests sane)

# --- white theme palette
const C_BG := Color("#f2f3f5")
const C_SOFT := Color("#f0f0f2")
const C_TILE := Color("#e8edf5")
const C_INK := Color("#232326")
const C_INK_2 := Color("#6f7178")
const C_GREEN := Color("#22b25a")

# --- pill toggle metrics (proportions taken from the reference design)
const TAB_FONT := 30
const TAB_H := 70.0
const TAB_PAD_X := 22.0
const TAB_OUTER := 9.0

# --- Customize sheet metrics
const SHEET_PAD := 24.0
const CHIP_H := 68.0
const PLAY_H := 92.0
const SWATCH_GAP := 14.0

# --- 3D preview camera
const CHAR_H := 2.4      # avatar height in world units (with hair)
const CHAR_MID_Y := 1.17 # avatar vertical centre in world units
const CAM_DIST := 9.0

var tab := TAB_MARKET
var shop_section := SHOP_SEC_ITEMS
var selected_part := "torso"

var preview_container: SubViewportContainer
var preview_camera: Camera3D
var preview_blocky # Blocky instance shown in the 3D preview
var preview_yaw := 0.0

var _font: Font
var _font_bold: Font
var _bg_texs: Array = [] # Texture2D (or null) per Customization.BACKGROUNDS entry
var _bg_shown := 0
var _shirt_texs := {} # id -> Texture2D (or null), for Customization.SHIRT_ITEMS thumbnails
var _bg_prev := -1 # backdrop being faded out, -1 = none
var _bg_a := 1.0   # fade-in progress of _bg_shown
var _tab_anim := 0.0 # position of the sliding pill, in tabs (0 = Marketplace, 1 = Shop, 2 = Customize)
var _tab_w: Array[float] = []
## One tiny 3D scene per Items card (id -> {"vp": SubViewport, "model": Blocky}),
## so every walk / the aura is shown on a real 3D avatar running in place.
var _shop_previews := {}
var _shop_prev_on := false
const SHOP_PREVIEW_PX := 256

var _shop_msg := ""
var _shop_msg_t := 0.0
var _shop_scroll := 0.0          # how far the Shop list is scrolled (logical px)
var _shop_press_active := false  # a finger / the mouse is down inside the Shop list
var _shop_press_id := -1
var _shop_press_pos := Vector2.ZERO
var _shop_dragging := false      # the press turned into a scroll drag (so it isn't a tap)
var _photo := false
var _hint_t := 0.0
var _inset_top := 0.0
var _inset_bottom := 0.0
var _feet := Vector2.ZERO # where the avatar's feet are on screen
var _feet_radius := 0.0

var _mouse_mode := false
var _chip_text_w: Array[float] = [] # measured label widths, so all chips fit in one row
var _edit: LineEdit                 # text box used for the name / username / sign-up fields
var _edit_field := ""               # "" = not editing, else one of the EDIT_* consts above
var _reg_name := ""                 # sign-up screen drafts, kept until "Create Account" is tapped
var _reg_user := ""
var _reg_pass := ""
var _reg_msg := ""                  # brief validation message on the sign-up screen
var _reg_msg_t := 0.0


# --------------------------------------------------------------- translation

func _t(key: String) -> String:
	var lang: String = Customization.lang
	if STR.has(lang) and STR[lang].has(key):
		return STR[lang][key]
	return String(STR["en"].get(key, key))


func _tab_label(i: int) -> String:
	match TAB_KEYS[i]:
		TAB_SHOP:
			return _t("tab_shop")
		TAB_CUSTOMIZE:
			return _t("tab_customize")
		_:
			return _t("tab_home")


func _part_label(i: int) -> String:
	match PART_KEYS[i]:
		"head":
			return _t("part_head")
		"torso":
			return _t("part_torso")
		"arms":
			return _t("part_arms")
		"legs":
			return _t("part_legs")
		PART_BG:
			return _t("part_background")
		_:
			return _t("part_dances")


func _shop_item_name(id: String) -> String:
	match id:
		"swagger":
			return _t("swagger_name")
		"aura":
			return _t("aura_name")
		"coinrun":
			return _t("coinrun_name")
		"angel":
			return _t("angel_name")
		"shirt_ironlion":
			return _t("shirt_ironlion_name")
		"shirt_algeria":
			return _t("shirt_algeria_name")
		"shirt_cyberdragon":
			return _t("shirt_cyberdragon_name")
		"shirt_phoenix":
			return _t("shirt_phoenix_name")
		"shirt_rebel":
			return _t("shirt_rebel_name")
	return id


func _shop_item_desc(id: String) -> String:
	match id:
		"swagger":
			return _t("swagger_desc")
		"aura":
			return _t("aura_desc")
		"coinrun":
			return _t("coinrun_desc")
		"angel":
			return _t("angel_desc")
		"shirt_ironlion":
			return _t("shirt_ironlion_desc")
		"shirt_algeria":
			return _t("shirt_algeria_desc")
		"shirt_cyberdragon":
			return _t("shirt_cyberdragon_desc")
		"shirt_phoenix":
			return _t("shirt_phoenix_desc")
		"shirt_rebel":
			return _t("shirt_rebel_desc")
	return ""


## The item list the Shop is currently showing (Items or Shirts sub-tab).
func _shop_active_list() -> Array:
	return Customization.SHIRT_ITEMS if shop_section == SHOP_SEC_SHIRTS else Customization.SHOP_ITEMS


func _shop_section_label(i: int) -> String:
	return _t("shop_sec_shirts") if SHOP_SEC_KEYS[i] == SHOP_SEC_SHIRTS else _t("shop_sec_items")


## Recomputed whenever the language changes (word widths differ), and once
## at startup instead of measuring the old hardcoded label lists.
func _recompute_label_widths() -> void:
	_tab_w.clear()
	for i in TAB_KEYS.size():
		_tab_w.append(_font.get_string_size(_tab_label(i), HORIZONTAL_ALIGNMENT_LEFT, -1.0, TAB_FONT).x + TAB_PAD_X * 2.0)
	_chip_text_w.clear()
	for i in PART_KEYS.size():
		_chip_text_w.append(_font.get_string_size(_part_label(i), HORIZONTAL_ALIGNMENT_LEFT, -1.0, CHIP_FONT).x)


func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	get_window().content_scale_size = UI_SIZE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mouse_mode = OS.has_feature("pc")

	_font = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.variation_embolden = 0.5
	_font_bold = fv
	_recompute_label_widths()

	for bg in Customization.BACKGROUNDS:
		var path: String = bg["path"]
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		_bg_texs.append(tex)
	_bg_shown = Customization.background

	for shirt in Customization.SHIRT_ITEMS:
		var spath: String = shirt["tex"]
		var stex: Texture2D = null
		if ResourceLoader.exists(spath):
			stex = load(spath) as Texture2D
		_shirt_texs[String(shirt["id"])] = stex

	_build_preview()
	_build_shop_previews()
	_build_editor()
	_update_insets()
	_update_preview_layout()


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
	sun.light_energy = 1.15
	root.add_child(sun)

	# Camera sits far back with a narrow FOV (almost orthographic, like a
	# catalog thumbnail). Its height and FOV are updated every frame in
	# _update_preview_layout() so the avatar always fits its space.
	preview_camera = Camera3D.new()
	preview_camera.position = Vector3(0.0, CHAR_MID_Y, CAM_DIST)
	root.add_child(preview_camera)

	preview_blocky = BlockyScript.new()
	root.add_child(preview_blocky)
	preview_blocky.build(Customization.head_color, Customization.torso_color,
		Customization.arms_color, Customization.arms_color,
		Customization.legs_color, Customization.legs_color,
		Customization.hair_color, false)
	preview_blocky.rotation.y = 0.0 # face the camera
	_apply_shop_to_preview()


## Builds the little 3D scenes behind the Shop's Items cards (walks + aura).
func _build_shop_previews() -> void:
	for it in Customization.SHOP_ITEMS:
		var id := String(it["id"])
		var kind := String(it["kind"])
		if kind != "walk" and kind != "aura":
			continue
		var sub := SubViewport.new()
		sub.size = Vector2i(SHOP_PREVIEW_PX, SHOP_PREVIEW_PX)
		sub.transparent_bg = true
		sub.own_world_3d = true
		sub.render_target_update_mode = SubViewport.UPDATE_DISABLED # only drawn while the Shop is open
		add_child(sub)

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
		sun.light_energy = 1.15
		root.add_child(sun)
		var cam := Camera3D.new()
		cam.fov = 36.0
		cam.position = Vector3(0.0, 1.05, 5.0)
		cam.current = true
		root.add_child(cam)

		var m := BlockyScript.new()
		root.add_child(m)
		m.build(Customization.head_color, Customization.torso_color,
			Customization.arms_color, Customization.arms_color,
			Customization.legs_color, Customization.legs_color,
			Customization.hair_color, false)
		m.set_walk_style(Customization.walk_style_for_id(id))
		m.set_aura(kind == "aura")
		m.rotation.y = 0.9 # three-quarter view so the stride is easy to see
		_shop_previews[id] = {"vp": sub, "model": m}


## Renders + animates the Items cards only while they're on screen, and picks
## up the player's current colors / shirt whenever the Shop is opened.
func _update_shop_previews(delta: float) -> void:
	var want := tab == TAB_SHOP and shop_section == SHOP_SEC_ITEMS
	if want != _shop_prev_on:
		_shop_prev_on = want
		if want:
			for id in _shop_previews:
				var m = _shop_previews[id]["model"]
				m.set_part_color("head", Customization.head_color)
				m.set_part_color("torso", Customization.torso_color)
				m.set_part_color("arms", Customization.arms_color)
				m.set_part_color("legs", Customization.legs_color)
				m.set_shirt(Customization.current_shirt_tex())
		for id in _shop_previews:
			var vp: SubViewport = _shop_previews[id]["vp"]
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if want else SubViewport.UPDATE_DISABLED
	if want:
		for id in _shop_previews:
			_shop_previews[id]["model"].animate(delta, 1.0, true, 0.0) # 1.0 = full run


func _process(delta: float) -> void:
	if _font == null:
		return # (headless server run: nothing to show)
	_update_insets()
	_shop_scroll = clampf(_shop_scroll, 0.0, _shop_scroll_max())
	var target := float(TAB_KEYS.find(tab))
	_tab_anim = lerpf(_tab_anim, target, clampf(delta * 14.0, 0.0, 1.0))
	_shop_msg_t = maxf(_shop_msg_t - delta, 0.0)
	_reg_msg_t = maxf(_reg_msg_t - delta, 0.0)
	_hint_t = maxf(_hint_t - delta, 0.0)
	_bg_a = minf(_bg_a + delta * 3.5, 1.0)
	if preview_blocky:
		# slow turntable sway when idle; face the camera while dancing
		preview_yaw += delta
		var yaw_target := 0.0 if preview_blocky.is_dancing() else sin(preview_yaw * 0.6) * 0.5
		preview_blocky.rotation.y = lerp_angle(preview_blocky.rotation.y, yaw_target, clampf(delta * 8.0, 0.0, 1.0))
		preview_blocky.animate(delta, 0.0, true)
	_update_shop_previews(delta)
	_update_preview_layout()
	queue_redraw()


## Keeps the layout clear of notches / gesture bars on phones. Does nothing
## on desktop (the "safe area" there is the whole screen minus the taskbar).
func _update_insets() -> void:
	_inset_top = 0.0
	_inset_bottom = 0.0
	if not OS.has_feature("mobile"):
		return
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return
	var k := size.y / float(win.y) # logical px per physical px
	var safe := DisplayServer.get_display_safe_area()
	_inset_top = clampf(float(safe.position.y) * k, 0.0, 160.0)
	_inset_bottom = clampf(float(win.y - safe.end.y) * k, 0.0, 120.0)


func _update_preview_layout() -> void:
	if preview_container == null:
		return
	preview_container.visible = (tab == TAB_CUSTOMIZE)
	var r := _preview_rect()
	preview_container.position = r.position
	preview_container.size = r.size

	# How much of the preview's height the avatar fills, and where its
	# centre sits (0 = top, 1 = bottom).
	var char_frac := 0.42
	var center_frac := 0.56
	if not _photo:
		char_frac = clampf(size.y * 0.36 / maxf(r.size.y, 1.0), 0.1, 0.8)
		center_frac = 0.5
	var extent := CHAR_H / char_frac # world units visible top-to-bottom
	var cam_y := CHAR_MID_Y - (0.5 - center_frac) * extent
	if preview_camera:
		preview_camera.position = Vector3(0.0, cam_y, CAM_DIST)
		preview_camera.fov = rad_to_deg(2.0 * atan(extent / (2.0 * CAM_DIST)))

	# Feet position (for the soft contact shadow drawn behind the avatar).
	_feet = Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * (0.5 + cam_y / extent))
	_feet_radius = 0.75 * r.size.y / extent


# ------------------------------------------------------------------ layout

func _col() -> Rect2:
	var w := minf(size.x, COL_MAX)
	return Rect2((size.x - w) * 0.5, 0.0, w, size.y)


func _header_top() -> float:
	return _inset_top + 34.0


func _header_h() -> float:
	return TAB_H + TAB_OUTER * 2.0


func _header_bottom() -> float:
	return _header_top() + _header_h()


## [capsule, then one rect per tab in TAB_KEYS order]
func _tab_rects() -> Array:
	var c := _col()
	var total := TAB_OUTER * 2.0
	for w in _tab_w:
		total += w
	var x0 := c.position.x + (c.size.x - total) * 0.5
	var y0 := _header_top()
	var out: Array = [Rect2(x0, y0, total, _header_h())]
	var x := x0 + TAB_OUTER
	for w in _tab_w:
		out.append(Rect2(x, y0 + TAB_OUTER, w, TAB_H))
		x += w
	return out


## Sits just under the header (top-left) so the wider 3-tab pill has the whole row.
func _photo_btn_rect() -> Rect2:
	return Rect2(_col().position.x + 24.0, _header_bottom() + 14.0, 76.0, 76.0)


func _swatch_cell() -> float:
	var inner := minf(size.x, COL_MAX) - 32.0 - SHEET_PAD * 2.0
	return floorf((inner - SWATCH_GAP * 5.0) / 6.0)


## The white bottom sheet of the Customize tab. The Play button always sits
## at its bottom edge, on both tabs.
func _sheet_rect() -> Rect2:
	var c := _col()
	var h := SHEET_PAD * 2.0 + CHIP_H + 22.0 + _swatch_cell() * 2.0 + SWATCH_GAP + 22.0 + PLAY_H
	var bottom := size.y - 24.0 - _inset_bottom
	return Rect2(c.position.x + 16.0, bottom - h, c.size.x - 32.0, h)


func _play_rect() -> Rect2:
	var s := _sheet_rect()
	return Rect2(s.position.x + SHEET_PAD, s.end.y - SHEET_PAD - PLAY_H, s.size.x - SHEET_PAD * 2.0, PLAY_H)


func _preview_rect() -> Rect2:
	if _photo:
		return Rect2(Vector2.ZERO, size)
	var top := _header_bottom() + 12.0
	var bottom := _sheet_rect().position.y - 6.0
	return Rect2(0.0, top, size.x, maxf(bottom - top, 100.0))


## One row of chips. Each is as wide as its label plus equal padding, and the
## padding is chosen so the whole row exactly fills the sheet.
func _chip_rect(i: int) -> Rect2:
	var s := _sheet_rect()
	var n := PART_KEYS.size()
	var inner := s.size.x - SHEET_PAD * 2.0
	var text_sum := 0.0
	for tw in _chip_text_w:
		text_sum += tw
	var pad := maxf((inner - CHIP_GAP * float(n - 1) - text_sum) / float(n * 2), 4.0)
	var x := s.position.x + SHEET_PAD
	for j in i:
		x += _chip_text_w[j] + pad * 2.0 + CHIP_GAP
	return Rect2(x, s.position.y + SHEET_PAD, _chip_text_w[i] + pad * 2.0, CHIP_H)


## Backdrop thumbnails fill the same area the color swatches use.
func _bg_card_rect(i: int) -> Rect2:
	var s := _sheet_rect()
	var n := Customization.BACKGROUNDS.size()
	var gap := SWATCH_GAP
	var w := (s.size.x - SHEET_PAD * 2.0 - gap * (n - 1)) / n
	var top := s.position.y + SHEET_PAD + CHIP_H + 22.0
	return Rect2(s.position.x + SHEET_PAD + i * (w + gap), top, w, _swatch_cell() * 2.0 + SWATCH_GAP)


## Dance cards use the same area as the backdrop thumbnails.
func _dance_card_rect(i: int) -> Rect2:
	var s := _sheet_rect()
	var n := Customization.DANCES.size()
	var gap := SWATCH_GAP
	var w := (s.size.x - SHEET_PAD * 2.0 - gap * (n - 1)) / n
	var top := s.position.y + SHEET_PAD + CHIP_H + 22.0
	return Rect2(s.position.x + SHEET_PAD + i * (w + gap), top, w, _swatch_cell() * 2.0 + SWATCH_GAP)


@warning_ignore("integer_division")
func _swatch_rect(i: int) -> Rect2:
	var s := _sheet_rect()
	var cell := _swatch_cell()
	var top := s.position.y + SHEET_PAD + CHIP_H + 22.0
	var grid_w := cell * 6.0 + SWATCH_GAP * 5.0
	var x0 := s.position.x + s.size.x * 0.5 - grid_w * 0.5
	var col := i % 6
	@warning_ignore("integer_division")
	var row := i / 6
	return Rect2(x0 + col * (cell + SWATCH_GAP), top + row * (cell + SWATCH_GAP), cell, cell)


func _market_card_rect() -> Rect2:
	var c := _col()
	return Rect2(c.position.x + 24.0, _header_bottom() + 104.0, c.size.x - 48.0, 250.0)


func _more_card_rect() -> Rect2:
	var card := _market_card_rect()
	return Rect2(card.position.x, card.end.y + 20.0, card.size.x, 92.0)


## "Community Games" card, right under the Studio card above.
func _community_card_rect() -> Rect2:
	var m := _more_card_rect()
	return Rect2(m.position.x, m.end.y + 14.0, m.size.x, 92.0)


func _online_card_rect() -> Rect2:
	var more := _community_card_rect()
	return Rect2(more.position.x, more.end.y + 70.0, more.size.x, 326.0)


## Row 0 = Play online switch, 1 = your name, 2 = username.
func _online_row_rect(i: int) -> Rect2:
	var card := _online_card_rect()
	return Rect2(card.position.x + 20.0, card.position.y + 18.0 + i * 100.0, card.size.x - 40.0, 88.0)


func _online_switch_rect() -> Rect2:
	var row := _online_row_rect(0)
	return Rect2(row.end.x - 24.0 - 96.0, row.get_center().y - 26.0, 96.0, 52.0)


func _edit_card_rect() -> Rect2:
	var c := _col()
	return Rect2(c.position.x + 28.0, _inset_top + 190.0, c.size.x - 56.0, 260.0)


func _edit_field_rect() -> Rect2:
	var r := _edit_card_rect()
	return Rect2(r.position.x + 26.0, r.position.y + 112.0, r.size.x - 52.0, 76.0)


## One-time sign-up screen shown before Home when Customization.registered
## is still false (see _draw_register()). Holds three tap-to-edit rows
## (name / username / password, same interaction as the Online card's rows)
## plus the "Create Account" button.
func _register_card_rect() -> Rect2:
	var c := _col()
	var w := minf(c.size.x - 56.0, 560.0)
	var h := 560.0
	return Rect2(c.position.x + (c.size.x - w) * 0.5, maxf((size.y - h) * 0.5, _inset_top + 20.0), w, h)


## i = 0 name, 1 username, 2 password.
func _register_row_rect(i: int) -> Rect2:
	var r := _register_card_rect()
	return Rect2(r.position.x + 32.0, r.position.y + 140.0 + i * 96.0, r.size.x - 64.0, 84.0)


func _register_btn_rect() -> Rect2:
	var r := _register_card_rect()
	return Rect2(r.position.x + 32.0, r.end.y - 32.0 - 84.0, r.size.x - 64.0, 84.0)


## Small EN/AR switch, top-right of the header row (also shown on the
## sign-up screen, at the same spot, so it always hit-tests consistently).
func _lang_btn_rect() -> Rect2:
	var c := _col()
	return Rect2(c.end.x - 24.0 - 64.0, _header_top() + (_header_h() - 44.0) * 0.5, 64.0, 44.0)


# ---------------------------------------------------------- draw helpers

func _styled(r: Rect2, bg: Color, radius: float, shadow_size: int, shadow_col: Color, border_w: int, border_col: Color, fill: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.draw_center = fill
	var rad: int = int(roundf(minf(r.size.x, r.size.y) * 0.5)) if radius < 0.0 else int(roundf(radius))
	sb.set_corner_radius_all(rad)
	sb.anti_aliasing = true
	if shadow_size > 0:
		sb.shadow_size = shadow_size
		sb.shadow_color = shadow_col
		sb.shadow_offset = Vector2(0.0, float(shadow_size) * 0.35)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_col
	sb.draw(get_canvas_item(), r)


## Flat rounded rect. radius < 0 means a full pill.
func _box(r: Rect2, col: Color, radius: float = -1.0) -> void:
	_styled(r, col, radius, 0, Color.TRANSPARENT, 0, Color.TRANSPARENT, true)


## Rounded rect with a soft drop shadow.
func _card(r: Rect2, col: Color, radius: float, shadow_size: int, shadow_col: Color) -> void:
	_styled(r, col, radius, shadow_size, shadow_col, 0, Color.TRANSPARENT, true)


## Outline only.
func _ring(r: Rect2, col: Color, radius: float, width: int) -> void:
	_styled(r, Color.TRANSPARENT, radius, 0, Color.TRANSPARENT, width, col, false)


func _text(font: Font, pos: Vector2, s: String, fs: int, col: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)


func _text_center(font: Font, center: Vector2, s: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var base := center.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(center.x - w * 0.5, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)


func _draw_cover(tex: Texture2D, dst: Rect2, alpha: float = 1.0) -> void:
	var ts := tex.get_size()
	var s := maxf(dst.size.x / ts.x, dst.size.y / ts.y)
	var src_size := dst.size / s
	var src_pos := (ts - src_size) * 0.5
	draw_texture_rect_region(tex, dst, Rect2(src_pos, src_size), Color(1, 1, 1, alpha))


## Same "cover" fit, but with rounded corners (textured polygon).
func _draw_cover_rounded(tex: Texture2D, dst: Rect2, radius: float, focus_y: float = 0.3) -> void:
	var ts := tex.get_size()
	var s := maxf(dst.size.x / ts.x, dst.size.y / ts.y)
	var src_size := dst.size / s
	# focus_y: 0 = crop from the top of the image, 1 = from the bottom
	var src_pos := Vector2((ts.x - src_size.x) * 0.5, (ts.y - src_size.y) * focus_y)
	var corners := [
		[Vector2(dst.end.x - radius, dst.position.y + radius), -PI * 0.5],
		[Vector2(dst.end.x - radius, dst.end.y - radius), 0.0],
		[Vector2(dst.position.x + radius, dst.end.y - radius), PI * 0.5],
		[Vector2(dst.position.x + radius, dst.position.y + radius), PI],
	]
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for corner in corners:
		var center: Vector2 = corner[0]
		var a0: float = corner[1]
		for j in 7:
			var a := a0 + (PI * 0.5) * float(j) / 6.0
			pts.append(center + Vector2(cos(a), sin(a)) * radius)
	for p in pts:
		uvs.append((src_pos + (p - dst.position) / s) / ts)
	draw_colored_polygon(pts, Color.WHITE, uvs, tex)


# -------------------------------------------------------------------- draw

func _draw() -> void:
	if _font == null:
		return
	if not Customization.registered:
		_draw_register()
		return
	if tab == TAB_CUSTOMIZE:
		_draw_customize_backdrop()
		if _photo:
			_draw_photo_hint()
			return
		_draw_sheet()
		_draw_play_bar()
		_draw_header()
		_draw_photo_button()
	else:
		draw_rect(Rect2(Vector2.ZERO, size), C_BG, true)
		if tab == TAB_SHOP:
			_draw_shop()
		else:
			_draw_marketplace()
		_draw_play_bar()
		_draw_header()
		if _edit_field != "":
			_draw_editor()


## Pill toggle: white capsule, a soft grey pill that slides under the
## active tab.
func _draw_header() -> void:
	var rects := _tab_rects()
	var cap: Rect2 = rects[0]
	_card(cap, Color.WHITE, -1.0, 28, Color(0, 0, 0, 0.10))
	# the grey pill slides between neighbouring tabs
	var idx := clampf(_tab_anim, 0.0, float(TAB_KEYS.size() - 1))
	var i0 := int(floorf(idx))
	var i1 := mini(i0 + 1, TAB_KEYS.size() - 1)
	var f := idx - float(i0)
	var ra: Rect2 = rects[i0 + 1]
	var rb: Rect2 = rects[i1 + 1]
	_box(Rect2(ra.position.lerp(rb.position, f), ra.size.lerp(rb.size, f)), C_SOFT)
	for i in TAB_KEYS.size():
		var r: Rect2 = rects[i + 1]
		_text_center(_font, r.get_center(), _tab_label(i), TAB_FONT, C_INK if tab == TAB_KEYS[i] else C_INK_2)
	_draw_lang_toggle()


func _draw_photo_button() -> void:
	var r := _photo_btn_rect()
	_card(r, Color.WHITE, -1.0, 24, Color(0, 0, 0, 0.14))
	var cen := r.get_center()
	# little camera: body, top bump, lens
	_ring(Rect2(cen.x - 17.0, cen.y - 8.0, 34.0, 24.0), C_INK, 7.0, 3)
	_box(Rect2(cen.x - 7.0, cen.y - 13.0, 14.0, 7.0), C_INK, 2.0)
	draw_arc(Vector2(cen.x, cen.y + 4.0), 6.5, 0.0, TAU, 24, C_INK, 3.0, true)


func _draw_photo_hint() -> void:
	if _hint_t <= 0.0:
		return
	var a := clampf(_hint_t, 0.0, 1.0)
	var label := _t("tap_exit")
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24).x + 56.0
	var r := Rect2(size.x * 0.5 - w * 0.5, size.y - 96.0 - _inset_bottom, w, 60.0)
	_box(r, Color(0, 0, 0, 0.55 * a))
	_text_center(_font, r.get_center(), label, 24, Color(1, 1, 1, a))


# ---------------------------------------------------------------- shop tab

func _shop_balance_rect() -> Rect2:
	var c := _col()
	return Rect2(c.position.x + 24.0, _header_bottom() + 30.0, c.size.x - 48.0, 96.0)


## Two-way "Items / Shirts" segmented control, sitting under the balance card.
func _shop_section_rect(i: int) -> Rect2:
	var bal := _shop_balance_rect()
	var top := bal.end.y + 22.0
	var w := (bal.size.x - 10.0) * 0.5
	return Rect2(bal.position.x + float(i) * (w + 10.0), top, w, 64.0)


func _shop_card_rect(i: int) -> Rect2:
	var c := _col()
	var top := _shop_section_rect(0).end.y + 60.0 - _shop_scroll
	return Rect2(c.position.x + 24.0, top + float(i) * SHOP_CARD_STEP, c.size.x - 48.0, 232.0)


## The part of the screen the Shop list is visible in: under the Items/Shirts
## switch and above the Play bar. Cards outside it are scrolled out of view.
func _shop_list_rect() -> Rect2:
	var top := _shop_section_rect(0).end.y + 48.0
	var bottom := _play_rect().position.y - 14.0
	return Rect2(0.0, top, size.x, maxf(bottom - top, 100.0))


## How far the list can scroll: its full height (cards + the "more items"
## strip) minus the height that fits on screen.
func _shop_scroll_max() -> float:
	var content := 12.0 + float(_shop_active_list().size()) * SHOP_CARD_STEP + 92.0 + 16.0
	return maxf(content - _shop_list_rect().size.y, 0.0)


func _shop_button_rect(i: int) -> Rect2:
	var r := _shop_card_rect(i)
	return Rect2(r.end.x - 24.0 - 250.0, r.end.y - 24.0 - 68.0, 250.0, 68.0)


func _coin_icon(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color(0.9, 0.55, 0.05))            # darker rim
	draw_circle(center, radius * 0.8, Color(1.0, 0.85, 0.2))       # bright face
	var d := radius * 0.42                                           # little diamond in the middle
	var pts := PackedVector2Array([center + Vector2(0.0, -d), center + Vector2(d, 0.0), center + Vector2(0.0, d), center + Vector2(-d, 0.0)])
	draw_colored_polygon(pts, Color(1.0, 0.97, 0.7))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.85, 0.55, 0.05), maxf(radius * 0.07, 1.5), true)


func _draw_shop() -> void:
	var bal := _shop_balance_rect()
	var view := _shop_list_rect()
	var list := _shop_active_list()

	# The list scrolls, so it is drawn first. The fixed parts (balance card,
	# Items/Shirts switch, heading) and the strip above the Play bar are then
	# painted over its edges, so nothing ever shows through or under them.
	for i in list.size():
		var it: Dictionary = list[i]
		var id := String(it["id"])
		var r := _shop_card_rect(i)
		if r.end.y < view.position.y or r.position.y > view.end.y:
			continue
		_card(r, Color.WHITE, 40.0, 30, Color(0, 0, 0, 0.07))
		var thumb := Rect2(r.position + Vector2(20.0, 20.0), Vector2(200.0, r.size.y - 40.0))
		_box(thumb, C_TILE, 30.0)
		_draw_shop_icon(String(it["kind"]), thumb, id)

		var tx := thumb.end.x + 24.0
		_text(_font_bold, Vector2(tx, r.position.y + 66.0), _shop_item_name(id), 34, C_INK)
		draw_multiline_string(_font, Vector2(tx, r.position.y + 102.0), _shop_item_desc(id),
			HORIZONTAL_ALIGNMENT_LEFT, r.end.x - 24.0 - tx, 21, 2, C_INK_2)

		var b := _shop_button_rect(i)
		var price := int(it["price"])
		if Customization.owns(id):
			var on2 := Customization.is_equipped(id)
			_box(b, C_INK if on2 else C_SOFT)
			_text_center(_font_bold, b.get_center(), _t("equipped") if on2 else _t("equip"), 28, Color.WHITE if on2 else C_INK)
		else:
			var can := Customization.coins >= price
			_box(b, C_GREEN if can else Color("#c9cbd1"))
			_text_center(_font_bold, Vector2(b.get_center().x - 22.0, b.get_center().y), _t("buy_fmt") % price, 30, Color.WHITE)
			_coin_icon(Vector2(b.end.x - 42.0, b.get_center().y), 17.0)

	var more := Rect2(_shop_card_rect(0).position.x, _shop_card_rect(list.size()).position.y, _shop_card_rect(0).size.x, 92.0)
	if more.end.y >= view.position.y and more.position.y <= view.end.y:
		_box(more, Color("#e9eaee"), 32.0)
		_text(_font, Vector2(more.position.x + 32.0, more.get_center().y + 8.0), _t("more_items"), 22, C_INK_2)

	draw_rect(Rect2(0.0, 0.0, size.x, view.position.y), C_BG, true)
	draw_rect(Rect2(0.0, view.end.y, size.x, size.y - view.end.y), C_BG, true)

	# balance
	_card(bal, Color.WHITE, 40.0, 30, Color(0, 0, 0, 0.07))
	_coin_icon(Vector2(bal.position.x + 66.0, bal.get_center().y), 30.0)
	_text(_font_bold, Vector2(bal.position.x + 116.0, bal.get_center().y + 17.0), str(Customization.coins), 48, C_INK)
	var hint := _t("coins_hint")
	var hw := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x
	_text(_font, Vector2(bal.end.x - 30.0 - hw, bal.get_center().y + 7.0), hint, 20, C_INK_2)

	# "Items" / "Shirts" segmented control
	for i in SHOP_SEC_KEYS.size():
		var sr := _shop_section_rect(i)
		var on: bool = SHOP_SEC_KEYS[i] == shop_section
		_box(sr, C_INK if on else C_SOFT, 20.0)
		_text_center(_font_bold, sr.get_center(), _shop_section_label(i), 26, Color.WHITE if on else C_INK_2)

	# heading (the current section's name), or the result of the last tap for a moment
	var head_pos := Vector2(bal.position.x + 8.0, _shop_section_rect(0).end.y + 34.0)
	if _shop_msg_t > 0.0:
		_text(_font_bold, head_pos, _shop_msg, 28, Color(0.1, 0.5, 0.25))
	else:
		_text(_font_bold, head_pos, _shop_section_label(SHOP_SEC_KEYS.find(shop_section)), 28, C_INK)

	# thin scrollbar on the right edge when the list is longer than the screen
	var max_scroll := _shop_scroll_max()
	if max_scroll > 0.0:
		var track := Rect2(size.x - 14.0, view.position.y + 6.0, 6.0, view.size.y - 12.0)
		_box(track, Color(0, 0, 0, 0.06))
		var thumb_h := maxf(track.size.y * view.size.y / (view.size.y + max_scroll), 40.0)
		var thumb_y := track.position.y + (track.size.y - thumb_h) * (_shop_scroll / max_scroll)
		_box(Rect2(track.position.x, thumb_y, track.size.x, thumb_h), Color(0, 0, 0, 0.25))


## Picture for a shop card (the thumbnail tile). Walk / aura items show a real
## 3D avatar running in place with that item on (see _build_shop_previews);
## shirts show their real design image.
func _draw_shop_icon(kind: String, tile: Rect2, id: String = "") -> void:
	if kind == "shirt":
		var tex: Texture2D = _shirt_texs.get(id)
		if tex:
			_draw_cover_rounded(tex, tile, 30.0, 0.15)
		return
	if not _shop_previews.has(id):
		return
	var vp: SubViewport = _shop_previews[id]["vp"]
	var s := tile.size.y
	draw_texture_rect(vp.get_texture(), Rect2(tile.get_center() - Vector2(s, s) * 0.5, Vector2(s, s)), false)


func _shop_tap(i: int) -> void:
	var list := _shop_active_list()
	var it: Dictionary = list[i]
	var id := String(it["id"])
	var nm := _shop_item_name(id)
	if Customization.owns(id):
		Customization.toggle_equip(id)
		_shop_msg = _t("equipped_fmt") % nm if Customization.is_equipped(id) else _t("turned_off_fmt") % nm
	elif Customization.buy(id):
		_shop_msg = _t("bought_fmt") % nm
	else:
		_shop_msg = _t("not_enough_fmt") % [nm, int(it["price"])]
	_shop_msg_t = 2.6
	_apply_shop_to_preview()


## Shows the equipped items on the Customize screen's live preview.
func _apply_shop_to_preview() -> void:
	if preview_blocky:
		preview_blocky.set_walk_style(Customization.walk_style())
		preview_blocky.set_aura(Customization.aura_enabled())
		preview_blocky.set_shirt(Customization.current_shirt_tex())


## Dimmed overlay with the text box for the name / username / sign-up field.
func _draw_editor() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55), true)
	var card := _edit_card_rect()
	_card(card, Color.WHITE, 40.0, 30, Color(0, 0, 0, 0.2))
	var title := ""
	match _edit_field:
		EDIT_NAME, EDIT_REG_NAME:
			title = _t("name_title")
		EDIT_USERNAME, EDIT_REG_USER:
			title = _t("username")
		EDIT_REG_PASS:
			title = _t("password")
	_text_center(_font_bold, Vector2(card.get_center().x, card.position.y + 58.0), title, 32, C_INK)
	var hint := _t("edit_hint")
	_text_center(_font, Vector2(card.get_center().x, card.end.y - 40.0), hint, 20, C_INK_2)


## One-time sign-up screen for a brand-new install. Three tap-to-edit rows
## (name / username / password — same interaction as the Online card's rows:
## tapping one opens the dimmed box from _draw_editor() above) hold drafts
## in _reg_name / _reg_user / _reg_pass until "Create Account" is tapped,
## which calls _submit_registration(). That calls Customization.register(),
## flipping Customization.registered to true — after that _draw() stops
## calling this and shows the normal Home screen instead.
func _draw_register() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG, true)
	var card := _register_card_rect()
	_card(card, Color.WHITE, 40.0, 36, Color(0, 0, 0, 0.12))
	_text_center(_font_bold, Vector2(card.get_center().x, card.position.y + 56.0), _t("welcome_title"), 32, C_INK)
	_text_center(_font, Vector2(card.get_center().x, card.position.y + 92.0), _t("welcome_sub"), 19, C_INK_2)

	var labels := [_t("your_name"), _t("username"), _t("password")]
	var values := [_reg_name, _reg_user, _reg_pass]
	for i in 3:
		var r := _register_row_rect(i)
		_box(r, C_SOFT, 26.0)
		_text(_font, Vector2(r.position.x + 24.0, r.position.y + 30.0), String(labels[i]), 19, C_INK_2)
		var raw := String(values[i])
		var shown := "•".repeat(raw.length()) if i == 2 else raw
		draw_string(_font_bold, Vector2(r.position.x + 24.0, r.position.y + 64.0), shown,
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 48.0, 26, C_INK)

	var b := _register_btn_rect()
	if _reg_msg_t > 0.0:
		_text_center(_font, Vector2(card.get_center().x, b.position.y - 18.0), _reg_msg, 19, Color(0.75, 0.15, 0.15))
	_box(b, C_GREEN, 24.0)
	_text_center(_font_bold, b.get_center(), _t("create_account"), 28, Color.WHITE)
	_draw_lang_toggle()
	if _edit_field != "": # a row is being edited: dim everything and show the text box card
		_draw_editor()


## Validates the sign-up drafts and, if they're good, hands them to
## Customization.register() (see there for what happens with the password).
func _submit_registration() -> void:
	var user := _reg_user.strip_edges()
	var pwd := _reg_pass
	if user == "" or pwd == "":
		_reg_msg = _t("reg_missing")
		_reg_msg_t = 2.6
		return
	Customization.register(_reg_name.strip_edges(), user, pwd)


func _draw_lang_toggle() -> void:
	var r := _lang_btn_rect()
	_card(r, Color.WHITE, -1.0, 18, Color(0, 0, 0, 0.10))
	var label := "AR" if Customization.lang == "en" else "EN"
	_text_center(_font_bold, r.get_center(), label, 22, C_INK)


func _build_editor() -> void:
	_edit = LineEdit.new()
	_edit.visible = false
	_edit.context_menu_enabled = false
	_edit.add_theme_font_size_override("font_size", 30)
	_edit.add_theme_color_override("font_color", C_INK)
	_edit.add_theme_color_override("caret_color", C_INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SOFT
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	_edit.add_theme_stylebox_override("normal", sb)
	_edit.add_theme_stylebox_override("focus", sb)
	_edit.text_submitted.connect(_on_edit_submitted)
	add_child(_edit)


func _begin_edit(field: String) -> void:
	_edit_field = field
	_edit.secret = (field == EDIT_REG_PASS)
	_edit.max_length = Customization.NAME_MAX
	match field:
		EDIT_NAME:
			_edit.text = Customization.player_name
		EDIT_USERNAME:
			_edit.text = Customization.username
		EDIT_REG_NAME:
			_edit.text = _reg_name
		EDIT_REG_USER:
			_edit.text = _reg_user
		EDIT_REG_PASS:
			_edit.text = _reg_pass
	var r := _edit_field_rect()
	_edit.position = r.position
	_edit.size = r.size
	_edit.visible = true
	_edit.grab_focus()
	_edit.caret_column = _edit.text.length()


@warning_ignore("shadowed_variable")
func _on_edit_submitted(_text: String) -> void:
	_finish_edit(true)


func _finish_edit(commit: bool) -> void:
	if _edit_field == "":
		return
	if commit:
		match _edit_field:
			EDIT_NAME:
				Customization.set_player_name(_edit.text)
			EDIT_USERNAME:
				Customization.set_username(_edit.text)
			EDIT_REG_NAME:
				_reg_name = _edit.text
			EDIT_REG_USER:
				_reg_user = _edit.text
			EDIT_REG_PASS:
				_reg_pass = _edit.text
	_edit_field = ""
	_edit.secret = false
	_edit.release_focus()
	_edit.visible = false
	DisplayServer.virtual_keyboard_hide()


func _draw_marketplace() -> void:
	var card := _market_card_rect()
	_text(_font_bold, Vector2(card.position.x + 8.0, card.position.y - 26.0), _t("recommended"), 28, C_INK)

	_card(card, Color.WHITE, 40.0, 30, Color(0, 0, 0, 0.07))
	var thumb := Rect2(card.position + Vector2(20.0, 20.0), Vector2(210.0, card.size.y - 40.0))
	_box(thumb, C_TILE, 30.0)
	_draw_avatar_icon(thumb)

	var text_x := thumb.end.x + 26.0
	var text_w := card.end.x - 24.0 - text_x
	_text(_font_bold, Vector2(text_x, card.position.y + 78.0), _t("blocky_world"), 38, C_INK)
	draw_multiline_string(_font, Vector2(text_x, card.position.y + 118.0),
		_t("world_desc"),
		HORIZONTAL_ALIGNMENT_LEFT, text_w, 22, 3, C_INK_2)

	var rating := _t("rating")
	var rw := _font.get_string_size(rating, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x + 36.0
	var chip := Rect2(text_x, card.end.y - 20.0 - 44.0, rw, 44.0)
	_box(chip, Color(0.87, 0.96, 0.90))
	_text_center(_font, chip.get_center(), rating, 20, Color(0.1, 0.5, 0.25))

	_draw_game_row(_more_card_rect(), "🛠️", _t("studio_title"), _t("studio_desc"))
	_draw_game_row(_community_card_rect(), "🌍", _t("community_title"), _t("community_desc"))
	_draw_online_card()


## One clickable row for Studio / Community Games: an emoji tile, title +
## one-line description, and a small chevron (it always navigates away, so
## there's no on/off state to show like the Shop's equip buttons have).
func _draw_game_row(r: Rect2, emoji: String, title: String, desc: String) -> void:
	_card(r, Color.WHITE, 28.0, 20, Color(0, 0, 0, 0.06))
	var tile := Rect2(r.position + Vector2(14.0, 14.0), Vector2(r.size.y - 28.0, r.size.y - 28.0))
	_box(tile, C_TILE, 18.0)
	_text_center(_font_bold, tile.get_center(), emoji, 30, C_INK)
	var tx := tile.end.x + 20.0
	_text(_font_bold, Vector2(tx, r.position.y + 36.0), title, 26, C_INK)
	_text(_font, Vector2(tx, r.position.y + 64.0), desc, 18, C_INK_2)
	_text_center(_font_bold, Vector2(r.end.x - 26.0, r.get_center().y), "›", 30, C_INK_2)


func _draw_online_card() -> void:
	var card := _online_card_rect()
	_text(_font_bold, Vector2(card.position.x + 8.0, card.position.y - 26.0), _t("play_with_others"), 28, C_INK)
	_card(card, Color.WHITE, 40.0, 30, Color(0, 0, 0, 0.07))

	# row 0: on/off switch
	var r0 := _online_row_rect(0)
	_box(r0, C_SOFT, 30.0)
	_text(_font_bold, Vector2(r0.position.x + 28.0, r0.position.y + 40.0), _t("play_online"), 30, C_INK)
	_text(_font, Vector2(r0.position.x + 28.0, r0.position.y + 70.0), _t("play_online_desc"), 20, C_INK_2)
	var sw := _online_switch_rect()
	var on := Customization.online
	_box(sw, C_GREEN if on else Color("#c9cbd1"))
	var knob_x := sw.end.x - 26.0 if on else sw.position.x + 26.0
	draw_circle(Vector2(knob_x, sw.get_center().y), 21.0, Color.WHITE)

	# rows 1 & 2: tap to edit
	var labels := [_t("your_name"), _t("username")]
	var values := [Customization.player_name, Customization.username]
	for i in 2:
		var r := _online_row_rect(i + 1)
		_box(r, C_SOFT, 30.0)
		_text(_font, Vector2(r.position.x + 28.0, r.position.y + 32.0), String(labels[i]), 20, C_INK_2)
		draw_string(_font_bold, Vector2(r.position.x + 28.0, r.position.y + 68.0), String(values[i]),
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 130.0, 28, C_INK)
		_text(_font, Vector2(r.end.x - 86.0, r.position.y + 50.0), _t("edit"), 22, C_INK_2)


## Tiny blocky avatar in the player's current colors (Marketplace thumbnail).
func _draw_avatar_icon(tile: Rect2) -> void:
	var k := tile.size.y * 0.36
	var o := Vector2(tile.get_center().x, tile.end.y - tile.size.y * 0.12)
	_avatar_box(o, k, -0.2, 0.0, 0.4, 0.8, Customization.legs_color)
	_avatar_box(o, k, 0.2, 0.0, 0.4, 0.8, Customization.legs_color)
	_avatar_box(o, k, 0.0, 0.8, 0.8, 0.8, Customization.torso_color)
	_avatar_box(o, k, -0.6, 0.78, 0.4, 0.8, Customization.arms_color)
	_avatar_box(o, k, 0.6, 0.78, 0.4, 0.8, Customization.arms_color)
	_avatar_box(o, k, 0.0, 1.61, 0.46, 0.46, Customization.head_color)
	_avatar_box(o, k, 0.0, 1.93, 0.5, 0.16, Customization.hair_color)
	_avatar_box(o, k, -0.1, 1.80, 0.07, 0.1, Color(0.1, 0.1, 0.12))
	_avatar_box(o, k, 0.1, 1.80, 0.07, 0.1, Color(0.1, 0.1, 0.12))


## cx = box centre x, y0 = box bottom, both in avatar units (feet at 0).
func _avatar_box(o: Vector2, k: float, cx: float, y0: float, w: float, h: float, col: Color) -> void:
	draw_rect(Rect2(o.x + (cx - w * 0.5) * k, o.y - (y0 + h) * k, w * k, h * k), col, true)


func _draw_customize_backdrop() -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, Color("#0b1020"), true)
	if _bg_a < 1.0 and _bg_prev >= 0 and _bg_prev < _bg_texs.size() and _bg_texs[_bg_prev]:
		_draw_cover(_bg_texs[_bg_prev], full)
	if _bg_shown < _bg_texs.size() and _bg_texs[_bg_shown]:
		_draw_cover(_bg_texs[_bg_shown], full, _bg_a)
	# soft contact shadow under the avatar
	draw_set_transform(_feet, 0.0, Vector2(1.0, 0.26))
	for i in 3:
		var k := 1.0 - float(i) * 0.28
		draw_circle(Vector2.ZERO, _feet_radius * k, Color(0, 0, 0, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_sheet() -> void:
	_card(_sheet_rect(), Color(1, 1, 1, 0.95), 46.0, 44, Color(0, 0, 0, 0.22))

	for i in PART_KEYS.size():
		var chip := _chip_rect(i)
		var active: bool = PART_KEYS[i] == selected_part
		_box(chip, C_INK if active else C_SOFT)
		var label := _part_label(i)
		_text_center(_font, chip.get_center(), label, CHIP_FONT, Color.WHITE if active else C_INK_2)

	if selected_part == PART_BG:
		_draw_backdrop_picker()
		return
	if selected_part == PART_DANCE:
		_draw_dance_picker()
		return

	var cur := Customization.get_color(selected_part)
	for i in Customization.PALETTE.size():
		var r := _swatch_rect(i)
		var c: Color = Customization.PALETTE[i]
		_box(r, c, 24.0)
		if c.is_equal_approx(cur):
			_ring(r.grow(7.0), C_INK, 30.0, 4)
		else:
			_ring(r, Color(0, 0, 0, 0.10), 24.0, 2)


func _draw_backdrop_picker() -> void:
	for i in Customization.BACKGROUNDS.size():
		var r := _bg_card_rect(i)
		if i < _bg_texs.size() and _bg_texs[i]:
			_draw_cover_rounded(_bg_texs[i], r, 26.0)
		else:
			_box(r, C_SOFT, 26.0)
		# name tag in the bottom-left corner
		var nm: String = Customization.BACKGROUNDS[i]["name"]
		var tw := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x + 28.0
		var tag := Rect2(r.position.x + 10.0, r.end.y - 10.0 - 38.0, tw, 38.0)
		_box(tag, Color(0, 0, 0, 0.55))
		_text_center(_font, tag.get_center(), nm, 20, Color.WHITE)
		if i == Customization.background:
			_ring(r.grow(7.0), C_INK, 33.0, 4)
		else:
			_ring(r, Color(0, 0, 0, 0.10), 26.0, 2)


## The three dance cards. Each shows a little avatar (in your current colors)
## frozen in that dance's signature pose; the highlighted one is equipped and
## is what the big preview above performs.
func _draw_dance_picker() -> void:
	for i in Customization.DANCES.size():
		var r := _dance_card_rect(i)
		var d: Dictionary = Customization.DANCES[i]
		var col: Color = d["color"]
		_box(r, col.lightened(0.55), 26.0)
		_draw_dance_icon(String(d["id"]), r)
		var nm := String(d["name"])
		var tw := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x + 28.0
		var tag := Rect2(r.position.x + 10.0, r.end.y - 10.0 - 38.0, tw, 38.0)
		_box(tag, Color(0, 0, 0, 0.55))
		_text_center(_font, tag.get_center(), nm, 20, Color.WHITE)
		if i == Customization.dance:
			_ring(r.grow(7.0), C_INK, 33.0, 4)
		else:
			_ring(r, Color(0, 0, 0, 0.10), 26.0, 2)


## Static mini avatar striking the dance's pose. Angles are measured from
## "hanging straight down", positive toward the right of the screen.
func _draw_dance_icon(id: String, r: Rect2) -> void:
	var k := r.size.y * 0.27
	var o := Vector2(r.get_center().x, r.end.y - 52.0)
	var aa := 0.1   # arm A (right of screen)
	var ab := -0.1  # arm B (left of screen)
	var la := 0.0   # leg A
	var lb := 0.0   # leg B
	match id:
		"disco":
			aa = 2.7
			ab = -0.5
			lb = -0.45
		"floss":
			aa = 1.15
			ab = 0.2
			la = 0.1
			lb = 0.1
		"robot":
			aa = 1.57
			ab = -3.14
	_draw_mini_avatar(o, k, aa, ab, la, lb)


## Little front-view avatar in the player's colors. o = feet, k = pixels per
## avatar unit; the four angles pose arms A/B and legs A/B (0 = hanging down).
func _draw_mini_avatar(o: Vector2, k: float, aa: float, ab: float, la: float, lb: float) -> void:
	# legs, torso, arms, head
	_limb_poly(o + Vector2(0.2 * k, -0.8 * k), la, 0.8 * k, 0.4 * k, Customization.legs_color)
	_limb_poly(o + Vector2(-0.2 * k, -0.8 * k), lb, 0.8 * k, 0.4 * k, Customization.legs_color)
	_avatar_box(o, k, 0.0, 0.8, 0.8, 0.8, Customization.torso_color)
	_limb_poly(o + Vector2(0.6 * k, -1.58 * k), aa, 0.8 * k, 0.4 * k, Customization.arms_color)
	_limb_poly(o + Vector2(-0.6 * k, -1.58 * k), ab, 0.8 * k, 0.4 * k, Customization.arms_color)
	_avatar_box(o, k, 0.0, 1.61, 0.46, 0.46, Customization.head_color)
	_avatar_box(o, k, 0.0, 1.93, 0.5, 0.16, Customization.hair_color)
	_avatar_box(o, k, -0.1, 1.80, 0.07, 0.1, Color(0.1, 0.1, 0.12))
	_avatar_box(o, k, 0.1, 1.80, 0.07, 0.1, Color(0.1, 0.1, 0.12))


## A rotated rectangle hanging from `pivot` at angle `ang` (0 = straight down).
func _limb_poly(pivot: Vector2, ang: float, length: float, width: float, col: Color) -> void:
	var dir := Vector2(sin(ang), cos(ang))
	var side := Vector2(cos(ang), -sin(ang)) * width * 0.5
	var tip := pivot + dir * length
	draw_colored_polygon(PackedVector2Array([pivot - side, pivot + side, tip + side, tip - side]), col)


func _draw_play_bar() -> void:
	var r := _play_rect()
	_card(r, C_GREEN, -1.0, 26, Color(0.13, 0.7, 0.35, 0.35))
	var label := _t("play")
	var w := _font_bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36).x
	var icon_w := 26.0
	var gap := 16.0
	var x0 := r.get_center().x - (icon_w + gap + w) * 0.5
	var cy := r.get_center().y
	draw_colored_polygon(PackedVector2Array([
		Vector2(x0, cy - 15.0), Vector2(x0, cy + 15.0), Vector2(x0 + icon_w, cy)
	]), Color.WHITE)
	_text_center(_font_bold, Vector2(x0 + icon_w + gap + w * 0.5, cy), label, 36, Color.WHITE)


# ------------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press(t.position, t.index)
		else:
			_shop_release(t.index, t.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_shop_move(d.index, d.position, d.relative)
	elif _mouse_mode and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb.position, 99)
			else:
				_shop_release(99, mb.position)
		elif mb.pressed and tab == TAB_SHOP and _edit_field == "" and Customization.registered:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_shop_scroll = clampf(_shop_scroll - 90.0, 0.0, _shop_scroll_max())
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_shop_scroll = clampf(_shop_scroll + 90.0, 0.0, _shop_scroll_max())
	elif _mouse_mode and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_shop_move(99, mm.position, mm.relative)


## Dragging inside the Shop list scrolls it. A press only becomes a "tap on a
## card" if it is released without having turned into a drag (see _shop_release).
func _shop_move(id: int, pos: Vector2, rel: Vector2) -> void:
	if not _shop_press_active or id != _shop_press_id:
		return
	if not _shop_dragging and pos.distance_to(_shop_press_pos) > 16.0:
		_shop_dragging = true
	if _shop_dragging:
		_shop_scroll = clampf(_shop_scroll - rel.y, 0.0, _shop_scroll_max())


func _shop_release(id: int, pos: Vector2) -> void:
	if not _shop_press_active or id != _shop_press_id:
		return
	_shop_press_active = false
	var was_drag := _shop_dragging
	_shop_dragging = false
	if was_drag or tab != TAB_SHOP or not _shop_list_rect().has_point(pos):
		return
	var list := _shop_active_list()
	for i in list.size():
		if _shop_card_rect(i).has_point(pos):
			_shop_tap(i)
			return


func _press(pos: Vector2, id: int = 99) -> void:
	if _lang_btn_rect().has_point(pos): # works everywhere, even mid sign-up
		Customization.set_lang("ar" if Customization.lang == "en" else "en")
		_recompute_label_widths()
		return
	if _edit_field != "": # a text box is open (name/username/sign-up row): it owns every tap
		if not _edit_card_rect().has_point(pos):
			_finish_edit(true)
		return
	if not Customization.registered: # sign-up screen: only its own controls respond
		var reg_fields := [EDIT_REG_NAME, EDIT_REG_USER, EDIT_REG_PASS]
		for i in 3:
			if _register_row_rect(i).has_point(pos):
				_begin_edit(reg_fields[i])
				return
		if _register_btn_rect().has_point(pos):
			_submit_registration()
		return
	if _photo: # photo mode: any tap brings the UI back
		_photo = false
		return

	if tab == TAB_CUSTOMIZE and _photo_btn_rect().has_point(pos):
		_photo = true
		_hint_t = 2.6
		return

	var rects := _tab_rects()
	for i in TAB_KEYS.size():
		@warning_ignore("shadowed_variable_base_class")
		var tr: Rect2 = rects[i + 1]
		var hit := Rect2(tr.position.x, tr.position.y - 14.0, tr.size.x, tr.size.y + 28.0)
		if hit.has_point(pos):
			tab = TAB_KEYS[i]
			_shop_scroll = 0.0
			return

	if _play_rect().has_point(pos):
		_start_game()
		return

	if tab == TAB_MARKET:
		if _market_card_rect().has_point(pos):
			_start_game()
			return
		if _more_card_rect().has_point(pos):
			Studio.open_mode = ""
			get_tree().change_scene_to_file("res://studio.tscn")
			return
		if _community_card_rect().has_point(pos):
			Studio.open_mode = "browse"
			get_tree().change_scene_to_file("res://studio.tscn")
			return
		if _online_row_rect(0).has_point(pos):
			Customization.set_online(not Customization.online)
			return
		if _online_row_rect(1).has_point(pos):
			_begin_edit(EDIT_NAME)
			return
		if _online_row_rect(2).has_point(pos):
			_begin_edit(EDIT_USERNAME)
			return
	elif tab == TAB_SHOP:
		for i in SHOP_SEC_KEYS.size():
			if _shop_section_rect(i).has_point(pos):
				shop_section = SHOP_SEC_KEYS[i]
				_shop_scroll = 0.0
				return
		# A tap on a card is decided when the finger lifts, so that dragging
		# the list up and down can scroll it without buying anything.
		if _shop_list_rect().has_point(pos):
			_shop_press_active = true
			_shop_press_id = id
			_shop_press_pos = pos
			_shop_dragging = false
	else:
		for i in PART_KEYS.size():
			if _chip_rect(i).has_point(pos):
				_select_part(PART_KEYS[i])
				return
		if selected_part == PART_DANCE:
			for i in Customization.DANCES.size():
				if _dance_card_rect(i).has_point(pos):
					_choose_dance(i)
					return
			return
		if selected_part == PART_BG:
			for i in Customization.BACKGROUNDS.size():
				if _bg_card_rect(i).has_point(pos):
					_choose_background(i)
					return
			return
		for i in Customization.PALETTE.size():
			if _swatch_rect(i).has_point(pos):
				var c: Color = Customization.PALETTE[i]
				Customization.set_color(selected_part, c)
				if preview_blocky:
					preview_blocky.set_part_color(selected_part, c)
				return


## Switches the chip row's selection. Opening "Dances" starts the equipped
## dance on the preview; any other chip returns the avatar to idle.
func _select_part(key: String) -> void:
	selected_part = key
	if preview_blocky == null:
		return
	if key == PART_DANCE:
		preview_blocky.play_dance(Customization.dance_id())
	else:
		preview_blocky.stop_dance()


func _choose_dance(i: int) -> void:
	Customization.set_dance(i)
	if preview_blocky:
		preview_blocky.play_dance(Customization.dance_id())


func _choose_background(i: int) -> void:
	if i == Customization.background:
		return
	Customization.set_background(i)
	_bg_prev = _bg_shown
	_bg_shown = i
	_bg_a = 0.0


func _start_game() -> void:
	get_tree().change_scene_to_file("res://main.tscn")
