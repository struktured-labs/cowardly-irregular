extends Node

## PartyChatSystem
##
## Opt-in registry of optional "party chat" cutscenes (Bravely Default style).
## Story-critical cutscenes still auto-trigger in GameLoop; everything else
## lives here and surfaces via PartyChatMenu (L trigger in exploration).
##
## Each registry entry declares:
##   - title: short label shown in the menu
##   - world: 1..6, used for grouping
##   - unlock: list of _flags() flags that must all be true
##     before the chat becomes available
##
## A chat is AVAILABLE when:
##   all `unlock` flags are set AND the `party_chat_viewed_<id>` flag is not.
##
## Once played, `mark_viewed(id)` sets the viewed flag. The underlying
## cutscene is still playable via direct id (e.g. the gallery), this just
## hides it from the Party Chat menu.

signal chats_changed()

## Optional override for tests — points at a GameState-like node with
## a `game_constants: Dictionary` property. When null, falls back to the
## GameState autoload (standard runtime path).
var game_state_override: Object = null

const REGISTRY := {
	# ===== WORLD 1 — unlock once the chapter-4 sweep auto-completes =====
	"world1_chapter2": {
		"title": "The Road North",
		"world": 1,
		"unlock": ["cutscene_flag_chapter1_complete"],
	},
	"world1_chapter5": {
		"title": "Into the Forest",
		"world": 1,
		"unlock": ["cutscene_flag_chapter4_complete"],
	},
	"world1_chapter5_forest": {
		"title": "Tempo's Chase",
		"world": 1,
		"unlock": ["cutscene_flag_chapter4_complete"],
	},
	"world1_chapter7": {
		"title": "The Capital",
		"world": 1,
		"unlock": ["cutscene_flag_chapter4_complete"],
	},
	"world1_chapter8": {
		"title": "Scholar's Reckoning",
		"world": 1,
		"unlock": ["cutscene_flag_chapter4_complete"],
	},
	"world1_chapter9": {
		"title": "The Throne",
		"world": 1,
		"unlock": ["cutscene_flag_chapter4_complete"],
	},
	"world1_guidance_cave": {
		"title": "Where Next? (Cave)",
		"world": 1,
		"unlock": ["cutscene_flag_chapter1_complete"],
	},
	"world1_guidance_forest": {
		"title": "Where Next? (Forest)",
		"world": 1,
		"unlock": ["cutscene_flag_rat_king_defeated"],
	},
	"world1_guidance_capital": {
		"title": "Where Next? (Capital)",
		"world": 1,
		"unlock": ["cutscene_flag_chapter5_complete"],
	},

	# ===== WORLD 2 =====
	"world2_guidance_explore": {
		"title": "Explore the Neighborhood",
		"world": 2,
		"unlock": ["cutscene_flag_world2_chapter1_complete"],
	},

	# ===== WORLD 3 =====
	"world3_guidance_mechanism": {
		"title": "Head to the Mechanism",
		"world": 3,
		"unlock": ["cutscene_flag_world3_chapter1_complete"],
	},
	"world3_chat_teatime_brasston": {
		"title": "The 4:07 Event",
		"world": 3,
		"unlock": ["cutscene_flag_world3_chapter1_complete"],
	},
	"world3_chat_sprocket_drift": {
		"title": "The Discrepancy Book",
		"world": 3,
		"unlock": ["cutscene_flag_world3_chapter2_complete"],
	},
	"world3_chat_clockwork_bard": {
		"title": "A Song for the Schedule",
		"world": 3,
		"unlock": ["cutscene_flag_world3_chapter2_complete"],
	},

	# ===== WORLD 4 =====
	"world4_guidance_director": {
		"title": "Find the Director",
		"world": 4,
		"unlock": ["cutscene_flag_world4_chapter1_complete"],
	},
	"world4_chat_manifest_denial": {
		"title": "Not on the Manifest",
		"world": 4,
		"unlock": ["cutscene_flag_world4_chapter1_complete"],
	},
	"world4_chat_union_pamphlet": {
		"title": "Pamphlet, Unapproved",
		"world": 4,
		"unlock": ["cutscene_flag_world4_chapter2_complete"],
	},
	"world4_chat_signal_tender": {
		"title": "Unsolicited Optimization",
		"world": 4,
		"unlock": ["cutscene_flag_world4_chapter2_complete"],
	},

	# ===== WORLD 5 =====
	"world5_guidance_core": {
		"title": "Navigate to the Core",
		"world": 5,
		"unlock": ["cutscene_flag_world5_chapter1_complete"],
	},
	"world5_chat_root_access": {
		"title": "root@localhost",
		"world": 5,
		"unlock": ["cutscene_flag_world5_chapter1_complete"],
	},
	"world5_chat_memory_leak_npc": {
		"title": "A Small Leak",
		"world": 5,
		"unlock": ["cutscene_flag_world5_chapter2_complete"],
	},
	"world5_chat_packet_pharmacy": {
		"title": "Drops In, Drops Out",
		"world": 5,
		"unlock": ["cutscene_flag_world5_chapter2_complete"],
	},

	# ===== WORLD 6 =====
	"world6_guidance_question": {
		"title": "The Question Awaits",
		"world": 6,
		"unlock": ["cutscene_flag_world6_chapter1_complete"],
	},
	"world6_chat_the_remainder": {
		"title": "A Small Fraction",
		"world": 6,
		"unlock": ["cutscene_flag_world6_chapter1_complete"],
	},
	"world6_chat_the_color": {
		"title": "Defiant Red",
		"world": 6,
		"unlock": ["cutscene_flag_world6_chapter2_complete"],
	},
	"world6_chat_the_player": {
		"title": "Who Is Playing Who",
		"world": 6,
		"unlock": ["cutscene_flag_world6_chapter2_complete"],
	},

	# ===== EVENT-TRIGGERED =====
	# Unlocked by gameplay events, not narrative milestones.
	# The unlock flags in this section are emitted by cowir-overworld /
	# cowir-battle when the corresponding event fires for the first time.
	# world field is the first-natural-unlock-world for menu grouping.
	"event_chat_first_magic_shop": {
		"title": "Magic as Merchandise",
		"world": 1,
		"unlock": ["event_flag_first_magic_shop_visited"],
	},
	"event_chat_first_party_wipe": {
		"title": "After the First Time",
		"world": 1,
		"unlock": ["event_flag_first_party_wipe"],
	},
	"event_chat_level_10": {
		"title": "Double Digits",
		"world": 1,
		"unlock": ["event_flag_level_10_reached"],
	},
	"event_chat_rare_drop": {
		"title": "The Glow",
		"world": 1,
		"unlock": ["event_flag_rare_drop_found"],
	},
	"event_chat_dragon_cave": {
		"title": "At the Cave Mouth",
		"world": 3,
		"unlock": ["event_flag_dragon_cave_entered"],
	},
	"event_chat_first_autobattle": {
		"title": "The Script Runs",
		"world": 1,
		"unlock": ["event_flag_first_autobattle_enabled"],
	},
	"event_chat_first_group_attack": {
		"title": "All at Once",
		"world": 1,
		"unlock": ["event_flag_first_group_attack"],
	},
	"event_chat_one_hp_victory": {
		"title": "Close",
		"world": 1,
		"unlock": ["event_flag_one_hp_victory"],
	},
}


func get_available_chats() -> Array:
	var out: Array = []
	for id in REGISTRY.keys():
		if is_available(id):
			var entry: Dictionary = REGISTRY[id]
			out.append({
				"id": id,
				"title": entry.get("title", id),
				"world": entry.get("world", 0),
			})
	out.sort_custom(func(a, b):
		if a.world != b.world:
			return a.world < b.world
		return a.id < b.id
	)
	return out


func has_available_chats() -> bool:
	for id in REGISTRY.keys():
		if is_available(id):
			return true
	return false


func available_count() -> int:
	var n := 0
	for id in REGISTRY.keys():
		if is_available(id):
			n += 1
	return n


func is_available(id: String) -> bool:
	return _is_unlocked(id) and not _is_viewed(id)


func mark_viewed(id: String) -> void:
	if not REGISTRY.has(id):
		return
	_flags()["party_chat_viewed_" + id] = true
	chats_changed.emit()


func _is_unlocked(id: String) -> bool:
	var entry: Dictionary = REGISTRY.get(id, {})
	if entry.is_empty():
		return false
	var unlock: Array = entry.get("unlock", [])
	for flag in unlock:
		if not _flags().get(flag, false):
			return false
	return true


func _is_viewed(id: String) -> bool:
	return _flags().get("party_chat_viewed_" + id, false)


func _flags() -> Dictionary:
	if game_state_override:
		return game_state_override.game_constants
	# Autoload path — Engine.get_singleton isn't used because GameState is
	# an autoload node, not an engine singleton.
	var root := Engine.get_main_loop()
	if root is SceneTree and root.root.has_node("GameState"):
		return root.root.get_node("GameState").game_constants
	return {}
