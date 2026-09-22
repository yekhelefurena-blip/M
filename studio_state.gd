extends Node
## Autoload "Studio". A tiny mailbox between scenes — nothing here is saved
## to disk; it only survives the scene change from Studio (or the community
## browser) into main.tscn.
##
##   open_mode: what studio.tscn should show when it starts —
##              "" = the Studio grid editor (build a level)
##              "browse" = the Community Games list
##   pending_mode: what main.tscn should do when it starts —
##              "" = the normal open world (default)
##              "play" = build and run pending_level instead
##   pending_level: the level {"meta": {...}, "data": {...}} to play.

var open_mode := ""
var pending_mode := ""
var pending_level := {}


## Called by main.gd once it has read (and acted on) the pending level, so a
## later "Home -> Blocky World" doesn't re-trigger it.
func consume_pending() -> Dictionary:
	var lvl := pending_level
	pending_mode = ""
	pending_level = {}
	return lvl


func play_level(level: Dictionary) -> void:
	pending_mode = "play"
	pending_level = level
