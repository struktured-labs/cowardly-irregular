extends GutTest

## tick 176 regression: party-member deaths emit a battle log
## line. Pre-fix the HP bar dropped to 0, ally KO quip optionally
## fired, but NO log line said "X has fallen!" — players had to
## look at the HP bars to notice. Enemy deaths emit "X has been
## defeated!" via BattleScene._on_enemy_died (line 3296); this
## closes the parity gap.
##
## Sample bug scenario: party in a 5-vs-5 brawl, multiple events
## fire each tick. A burning Cleric tick'd dead while the player
## was selecting Mage's action. Pre-fix the player wouldn't
## notice until the next turn rotation showed the grayed-out
## portrait — sometimes 30+ seconds later.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Death announcement in _on_party_hp_changed ──────────────────────────

func test_party_death_emits_fallen_log() -> void:
	var src := _read(BATTLE_SCENE)
	# Find _on_party_hp_changed body.
	var idx: int = src.find("func _on_party_hp_changed")
	assert_gt(idx, -1, "_on_party_hp_changed must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("[color=red]✖ %s has fallen![/color]"),
		"party HP-changed handler must emit '✖ X has fallen!' on KO")


func test_party_death_log_uses_red_for_severity() -> void:
	# Red matches the severity palette: enemy defeat is yellow
	# (neutral "hostile gone"), party defeat is red (player's
	# loss, more urgent).
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _on_party_hp_changed")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	# Pin red+✖ marker for severity.
	assert_true(body.contains("[color=red]✖"),
		"party death log must use red + ✖ for severity (vs enemy death's yellow)")


func test_party_death_log_inside_drop_to_0_branch() -> void:
	# The log must fire ONLY when HP drops from >0 to <=0, not
	# every time HP changes. Pin the structural placement.
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _on_party_hp_changed")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	var drop_to_zero_idx: int = body.find("if new_value <= 0 and old_value > 0:")
	var log_idx: int = body.find("has fallen!")
	assert_gt(drop_to_zero_idx, -1, "drop-to-zero guard must exist")
	assert_gt(log_idx, -1, "fallen log must exist")
	assert_lt(drop_to_zero_idx, log_idx,
		"fallen log must be INSIDE the drop-to-zero block — else it fires on every HP change")


func test_party_death_log_guards_member_index_bounds() -> void:
	# Defensive: party_members array could change between connect
	# and signal fire (e.g., autogrind tearing down). Pin the
	# bounds guard.
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _on_party_hp_changed")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	# Pin: the log code path checks member_idx < party_members.size()
	assert_true(body.contains("if member_idx < party_members.size():"),
		"fallen log path must guard member_idx against party_members.size()")


# ── Ally KO quip still fires (no regression) ────────────────────────────

func test_ally_ko_quip_still_fires() -> void:
	# Non-regression: the existing ALLY_KO_QUIPS path must still
	# work alongside the new log emit.
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _on_party_hp_changed")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("_try_combat_quip(ALLY_KO_QUIPS, reactor)"),
		"ALLY_KO_QUIPS quip path must remain — runs alongside the new log emit")


# ── Enemy death log parity check ────────────────────────────────────────

func test_enemy_death_log_still_in_place() -> void:
	# Cross-pin: the enemy death log is the parity reference for
	# this fix. Make sure it's preserved.
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("[color=yellow]%s has been defeated![/color]"),
		"enemy death log preserved (parity reference)")


# ── Formation special announce duplication fix from tick 176 ───────────

func test_formation_special_announce_no_longer_duplicates_name() -> void:
	# Tick 175 added "✦ FORMATION SPECIAL: <Name> ✦" but each
	# formation branch already ends with "★ <Name> — description ★"
	# — duplicate naming read as two lines for one event. Tick 176
	# strips the name from the opener.
	var bm_src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# Positive pin: name-less opener.
	assert_true(bm_src.contains("[color=gold]✦ FORMATION SPECIAL ✦[/color]"),
		"_execute_formation_special opener must be name-less")
	# Negative pin: the named version must be gone.
	assert_false(bm_src.contains("[color=gold]✦ FORMATION SPECIAL: %s ✦[/color]"),
		"the tick-175 named opener must be gone — was duplicating with descriptor")
	# The descriptor must remain (cross-pin sample with four_heroes).
	assert_true(bm_src.contains("[color=cyan]★ Four Heroes — balanced strike + party healed 25%! ★[/color]"),
		"four_heroes descriptor preserved — it carries the name + effect summary")
