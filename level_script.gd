class_name LevelScript
extends RefCounted
## The "بعض الأكواد" (a bit of code) a level creator can attach to a Trigger
## block, in the Studio. This is a tiny fixed-vocabulary language, not real
## code: parse() only ever turns a line into one of a handful of known
## {"op": ...} dictionaries below. There is no eval(), no load(), and no way
## to reach any other part of the game — every line either becomes one of
## these exact ops or is reported as an error, so a script downloaded from
## another player's published level can never do anything but the six things
## below, however it's worded.
##
## One event per line:
##   on_touch <action>        عند_اللمس <action>
##   on_timer <secs> <action> عند_الوقت <secs> <action>
##
## Actions:
##   give_coins <n>   اعطي_عملات <n>     (1..1000)
##   lose_coins <n>   خصم_عملات <n>      (1..1000)
##   win              فوز
##   lose             خسارة  / خساره
##   message <text>   رسالة <text>       (rest of the line, shown as a toast)
##   teleport <gx> <gy>  انتقل <gx> <gy>  (grid cell to send the player to)
##   speed <mult> <secs>  سرعة <مضاعف> <ثواني>   (temporary speed boost/slow)
##   bounce               نطة                    (an instant upward launch)
##
## (the "Speed Pad" and "Bounce Pad" tools in the Studio just place a Trigger
## with one of these two lines already written for you — no typing needed)

const EVENT_TOUCH := ["on_touch", "عند_اللمس"]
const EVENT_TIMER := ["on_timer", "عند_الوقت"]
const ACT_GIVE := ["give_coins", "اعطي_عملات"]
const ACT_LOSE_COINS := ["lose_coins", "خصم_عملات"]
const ACT_WIN := ["win", "فوز"]
const ACT_LOSE := ["lose", "خسارة", "خساره"]
const ACT_MSG := ["message", "رسالة"]
const ACT_TP := ["teleport", "انتقل"]
const ACT_SPEED := ["speed", "سرعة"]
const ACT_BOUNCE := ["bounce", "نطة"]
const MAX_LINES := 12


## Splits on runs of whitespace, dropping empty pieces (String.split(" ", false)
## only collapses single-space runs, so a stray double space would leave "").
static func _words(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	for w in s.split(" "):
		if w != "":
			out.append(w)
	return out


static func _action_from(word: String, rest: PackedStringArray) -> Variant:
	if word in ACT_GIVE:
		if rest.size() < 1 or not rest[0].is_valid_int():
			return null
		return {"op": "give_coins", "n": clampi(int(rest[0]), 1, 1000)}
	if word in ACT_LOSE_COINS:
		if rest.size() < 1 or not rest[0].is_valid_int():
			return null
		return {"op": "lose_coins", "n": clampi(int(rest[0]), 1, 1000)}
	if word in ACT_WIN:
		return {"op": "win"}
	if word in ACT_LOSE:
		return {"op": "lose"}
	if word in ACT_MSG:
		var text := " ".join(Array(rest))
		return {"op": "message", "text": text.substr(0, 80)}
	if word in ACT_TP:
		if rest.size() < 2 or not rest[0].is_valid_float() or not rest[1].is_valid_float():
			return null
		return {"op": "teleport", "gx": float(rest[0]), "gy": float(rest[1])}
	if word in ACT_SPEED:
		if rest.size() < 2 or not rest[0].is_valid_float() or not rest[1].is_valid_float():
			return null
		return {"op": "speed", "mult": clampf(float(rest[0]), 0.3, 3.0), "secs": clampf(float(rest[1]), 0.2, 30.0)}
	if word in ACT_BOUNCE:
		return {"op": "bounce"}
	return null


## -> {"touch": [action, ...], "timers": [{"t": secs, "action": action}, ...],
##     "errors": [line, ...]}  (bad or unrecognized lines, shown back to the
##     creator in the Studio so they can fix them — a level with errors can
##     still be placed / published, the bad lines are just skipped at runtime).
static func parse(text: String) -> Dictionary:
	var touch: Array = []
	var timers: Array = []
	var errors: Array = []
	var lines := text.split("\n")
	for raw in lines:
		if touch.size() + timers.size() >= MAX_LINES:
			break
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var w := _words(line)
		if w.size() < 2:
			errors.append(line); continue
		if w[0] in EVENT_TOUCH:
			var action = _action_from(w[1], w.slice(2))
			if action == null:
				errors.append(line); continue
			touch.append(action)
		elif w[0] in EVENT_TIMER:
			if w.size() < 3 or not w[1].is_valid_float():
				errors.append(line); continue
			var action2 = _action_from(w[2], w.slice(3))
			if action2 == null:
				errors.append(line); continue
			timers.append({"t": clampf(float(w[1]), 0.0, 600.0), "action": action2})
		else:
			errors.append(line)
	return {"touch": touch, "timers": timers, "errors": errors}


## Short one-line summary shown on the trigger's card in the Studio (e.g.
## "لمس: +5 عملات" so the creator can tell blocks apart without reopening each).
static func summarize(text: String, lang: String) -> String:
	var p := parse(text)
	var n: int = p["touch"].size() + p["timers"].size()
	if n == 0:
		return "فاضي — اضغط لتعديل الكود" if lang == "ar" else "empty — tap to edit the code"
	return ("%d سطر" % n) if lang == "ar" else ("%d line(s)" % n)
