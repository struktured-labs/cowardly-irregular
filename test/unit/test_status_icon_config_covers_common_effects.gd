extends GutTest

## tick 129 regression: STATUS_ICON_CONFIG must have explicit entries
## for the most common status effects in data/abilities.json. Pre-fix,
## anything not in the config fell through to
## `status.substr(0, 3).to_upper()` — vague 3-letter abbreviation
## that surfaced "ATT" both for attack_up AND attack_down (opposite
## effects, identical icon).
##
## Buff/debuff pairs use green/red color coding + ± suffix for instant
## visual distinction.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"

## Most common status effects that any player will see in normal play.
const REQUIRED_STATUS_KEYS: Array[String] = [
	# Crowd control / debuffs (pre-tick-129 baseline)
	"exposed", "cannot_defer", "stun", "sleep", "confuse", "fear", "charm",
	"blind", "curse", "regen", "permakilled",
	# Tick 129 additions
	"attack_up", "attack_down",
	"defense_up", "defense_down",
	"magic_up", "magic_down",
	"speed_up", "speed_down",
	"burn", "poison", "silence", "barrier", "haste", "slow",
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_every_required_status_has_a_config_entry() -> void:
	var src := _read(BATTLE_SCENE)
	# Locate the const block.
	var idx: int = src.find("const STATUS_ICON_CONFIG")
	assert_gt(idx, -1, "STATUS_ICON_CONFIG must exist")
	var end_idx: int = src.find("\n}", idx)
	assert_gt(end_idx, -1, "STATUS_ICON_CONFIG must have a closing brace")
	var body: String = src.substr(idx, end_idx - idx + 2)
	for key in REQUIRED_STATUS_KEYS:
		var quoted: String = "\"" + key + "\":"
		assert_true(body.contains(quoted),
			"STATUS_ICON_CONFIG must contain entry for '%s' — without it, the player sees the vague substr(0, 3) fallback" % key)


func test_buff_debuff_pairs_use_distinct_colors() -> void:
	# Load the const at runtime to compare colors structurally rather
	# than via string matching.
	var script_class = load(BATTLE_SCENE)
	var cfg: Dictionary = script_class.STATUS_ICON_CONFIG
	# Pairs: buff (green) vs matching debuff (red).
	for pair in [["attack_up", "attack_down"],
	             ["defense_up", "defense_down"],
	             ["magic_up", "magic_down"],
	             ["speed_up", "speed_down"]]:
		var buff_id: String = pair[0]
		var debuff_id: String = pair[1]
		assert_true(cfg.has(buff_id) and cfg.has(debuff_id),
			"Both %s and %s must be in STATUS_ICON_CONFIG" % [buff_id, debuff_id])
		var buff_color: Color = cfg[buff_id]["color"]
		var debuff_color: Color = cfg[debuff_id]["color"]
		assert_ne(buff_color, debuff_color,
			"%s and %s must have distinct colors — same color defeats the buff-vs-debuff visual distinction" % [buff_id, debuff_id])
		# Pin specific semantic colors: buff is green-dominant (g > r),
		# debuff is red-dominant (r > g).
		assert_gt(buff_color.g, buff_color.r,
			"%s buff color must be green-dominant (g > r) — semantic 'good' color" % buff_id)
		assert_gt(debuff_color.r, debuff_color.g,
			"%s debuff color must be red-dominant (r > g) — semantic 'bad' color" % debuff_id)


func test_buff_debuff_labels_use_plus_minus_suffix() -> void:
	# Pin: stat-modifier pairs use +/- suffix for instant clarity.
	# Without this, players have to memorize which color is which.
	var script_class = load(BATTLE_SCENE)
	var cfg: Dictionary = script_class.STATUS_ICON_CONFIG
	for stat in ["attack", "defense", "magic", "speed"]:
		var buff_label: String = cfg[stat + "_up"]["label"]
		var debuff_label: String = cfg[stat + "_down"]["label"]
		assert_true(buff_label.ends_with("+"),
			"%s_up label must end with '+' — visual 'goes up' tell" % stat)
		assert_true(debuff_label.ends_with("-"),
			"%s_down label must end with '-' — visual 'goes down' tell" % stat)


func test_labels_fit_in_icon_width() -> void:
	# Pin: each label must be 4 chars or fewer. Icons are sized for
	# narrow text; longer labels would clip.
	var script_class = load(BATTLE_SCENE)
	var cfg: Dictionary = script_class.STATUS_ICON_CONFIG
	for status_id in cfg:
		var label: String = cfg[status_id]["label"]
		assert_lte(label.length(), 4,
			"%s label '%s' exceeds 4 chars — would clip in the status icon row" % [status_id, label])


func test_existing_status_entries_preserved() -> void:
	# Negative pin: don't accidentally drop any pre-tick-129 entry
	# while adding the new ones.
	var script_class = load(BATTLE_SCENE)
	var cfg: Dictionary = script_class.STATUS_ICON_CONFIG
	for legacy in ["exposed", "cannot_defer", "stun", "sleep", "confuse",
	               "fear", "charm", "blind", "curse", "regen", "permakilled"]:
		assert_true(cfg.has(legacy),
			"pre-tick-129 status '%s' must remain in the config" % legacy)


func test_fallback_path_still_present_for_unknown_statuses() -> void:
	# Sanity: the substr(0, 3).to_upper() fallback path must remain
	# for statuses NOT in the config. We don't want to crash on a
	# brand-new effect — just degrade visibility.
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("status.substr(0, 3).to_upper()"),
			"_refresh_status_icons must keep the substr(0, 3) fallback for unknown statuses")
