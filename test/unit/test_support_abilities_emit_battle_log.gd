extends GutTest

## tick 170 regression: _execute_support_ability's buff/debuff/
## taunt/doom branches now emit battle_log_message so the player
## actually sees what happened. Pre-fix 10 branches were silent
## (Protect, Berserk, Armor Break, Taunt, Doom, Weaken, Slow,
## Despair, Empower, Sap) — only the buff icon eventually
## appearing on the portrait gave any feedback, easy to miss
## mid-battle.
##
## Continuation of the tick 169 hunt for missing emits in combat
## code. Method: scan each ability executor for branches that
## mutate state but don't emit feedback signals.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _support_body() -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _execute_support_ability")
	assert_gt(idx, -1, "_execute_support_ability must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


# ── Buff branches ──────────────────────────────────────────────────────

func test_defense_up_emits_protect_log() -> void:
	var body := _support_body()
	assert_true(body.contains("%s gains Protect!"),
		"defense_up must emit 'X gains Protect!' battle_log_message")


func test_attack_up_emits_berserk_log() -> void:
	var body := _support_body()
	assert_true(body.contains("%s enters Berserk!"),
		"attack_up must emit 'X enters Berserk!' battle_log_message")


func test_generic_buff_emits_empowered_log() -> void:
	var body := _support_body()
	assert_true(body.contains("%s is empowered!"),
		"generic 'buff' effect must emit 'X is empowered!' battle_log_message")


# ── Debuff branches ────────────────────────────────────────────────────

func test_defense_down_emits_armor_break_log() -> void:
	var body := _support_body()
	assert_true(body.contains("%s's armor is broken!"),
		"defense_down must emit 'X's armor is broken!' log")


func test_attack_down_emits_weaken_log() -> void:
	var body := _support_body()
	assert_true(body.contains("%s is weakened!"),
		"attack_down must emit 'X is weakened!' log")


func test_speed_down_emits_slow_log() -> void:
	var body := _support_body()
	assert_true(body.contains("%s slows down!"),
		"speed_down must emit 'X slows down!' log")


func test_all_stats_down_emits_despair_log() -> void:
	var body := _support_body()
	assert_true(body.contains("%s sinks into Despair!"),
		"all_stats_down must emit 'X sinks into Despair!' log")


func test_generic_debuff_emits_sap_log() -> void:
	var body := _support_body()
	assert_true(body.contains("%s is sapped!"),
		"generic 'debuff' effect must emit 'X is sapped!' log")


# ── Status-effect branches ─────────────────────────────────────────────

func test_taunt_emits_focus_log() -> void:
	var body := _support_body()
	assert_true(body.contains("%s taunts %s into focusing on them!"),
		"taunt must emit a battle_log_message — pre-fix only print()")


func test_doom_emits_doomed_log() -> void:
	var body := _support_body()
	assert_true(body.contains("☠ %s is doomed!"),
		"doom must emit a battle_log_message with ☠ marker — pre-fix only print()")


# ── Negative pin: pre-existing emit branches still wired ───────────────

func test_existing_branches_still_have_emits() -> void:
	# Pre-existing emits (regen, cleanse, barrier-family, volatility)
	# must not regress while I'm in this file.
	var body := _support_body()
	assert_true(body.contains("%s gains Regen!"),
		"regen emit preserved")
	assert_true(body.contains("%s cleansed %s!"),
		"cleanse emit preserved")
	assert_true(body.contains("%s is afflicted with %s!"),
		"barrier/invisible/etc emit preserved")


# ── Color-code conventions ─────────────────────────────────────────────

func test_buffs_use_positive_color_family() -> void:
	# Buff emits use cyan/orange/yellow (positive palette);
	# debuffs use red. Visual coherence with healing (lime) and
	# damage (yellow) colors elsewhere.
	var body := _support_body()
	# Sample a few — defense_up cyan, attack_up orange.
	assert_true(body.contains("[color=cyan]%s gains Protect!"),
		"defense_up must use cyan for buff feel")
	assert_true(body.contains("[color=orange]%s enters Berserk!"),
		"attack_up must use orange for aggressive-buff feel")


func test_debuffs_use_red() -> void:
	var body := _support_body()
	for fragment in [
		"[color=red]%s's armor is broken!",
		"[color=red]%s is weakened!",
		"[color=red]%s slows down!",
		"[color=red]%s sinks into Despair!",
		"[color=red]%s is sapped!",
	]:
		assert_true(body.contains(fragment),
			"debuff must use red palette: %s" % fragment)
