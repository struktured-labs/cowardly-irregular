extends GutTest

## tick 144 regression: party LLM dialogue triggers (low_hp,
## big_hit_taken) must fire on status-effect ticks just like
## regular damage. Pre-fix _on_damage_dealt_for_party_dialogue
## only listened to BattleManager.damage_dealt, so a burning Cleric
## who lost 32% max HP to a burn tick got NO "big hit taken" quip,
## and a poisoned Bard who crossed below 25% from a poison tick
## got NO "low_hp" quip.
##
## Tick 143 added status_tick_damage signals on Combatant. Tick 144
## adds a parallel handler in BattleManager that connects per-party
## member at start_battle and applies the same trigger semantics
## (with is_crit forced false — DoTs don't crit — and the source
## string passed through for future per-source dialogue variations).

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _fn_body(name: String) -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func " + name)
	assert_gt(idx, -1, "%s must exist" % name)
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


# ── Handler declaration ──────────────────────────────────────────────────

func test_status_tick_handler_exists() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("func _on_status_tick_damage_for_party_dialogue(amount: int, source: String, target: Combatant) -> void:"),
		"BattleManager must declare _on_status_tick_damage_for_party_dialogue with (amount, source, target) signature")


# ── Trigger semantics: big_hit_taken ─────────────────────────────────────

func test_handler_fires_big_hit_taken_above_threshold() -> void:
	# Pin: big_hit_taken fires when amount > max_hp * BIG_HIT_PCT.
	# is_crit is hardcoded false (DoT ticks aren't crits).
	var body := _fn_body("_on_status_tick_damage_for_party_dialogue")
	assert_true(body.contains("var big: bool = amount > int(float(target.max_hp) * BIG_HIT_HP_PCT_THRESHOLD)"),
		"big-hit threshold must use BIG_HIT_HP_PCT_THRESHOLD constant")
	assert_true(body.contains("_maybe_fire_party_line(target, \"big_hit_taken\", {\"damage\": amount, \"is_crit\": false, \"source\": source})"),
		"big-hit trigger must pass is_crit=false (DoT ticks don't crit) and the source string")


# ── Trigger semantics: low_hp ────────────────────────────────────────────

func test_handler_fires_low_hp_on_threshold_crossing() -> void:
	# Pin: low_hp fires only when pre>=threshold AND post<threshold.
	# Same logic as the regular damage handler — don't refire if
	# already below threshold.
	var body := _fn_body("_on_status_tick_damage_for_party_dialogue")
	assert_true(body.contains("if pre_hp_pct >= LOW_HP_PCT_THRESHOLD and post_hp_pct < LOW_HP_PCT_THRESHOLD:"),
		"low_hp must fire only on downward threshold crossing — not re-fire if already below")
	assert_true(body.contains("_maybe_fire_party_line(target, \"low_hp\", {\"hp_pct\": post_hp_pct, \"source\": source})"),
		"low_hp trigger must pass hp_pct + source string")


# ── Defensive guards ─────────────────────────────────────────────────────

func test_handler_guards_target_valid_and_alive_and_in_party() -> void:
	var body := _fn_body("_on_status_tick_damage_for_party_dialogue")
	assert_true(body.contains("if target == null or not is_instance_valid(target):"),
		"handler must guard target validity")
	assert_true(body.contains("if not (target in player_party):"),
		"handler must filter to player_party only (don't trigger on enemy DoTs)")
	assert_true(body.contains("if not target.is_alive:"),
		"handler must skip dead targets")
	assert_true(body.contains("if amount <= 0:"),
		"handler must skip zero/negative amounts")


# ── big_hit_taken takes priority over low_hp ─────────────────────────────

func test_big_hit_short_circuits_low_hp() -> void:
	# Pin: if big, return early — don't ALSO fire low_hp on the
	# same tick. Matches the damage_dealt handler's semantics.
	var body := _fn_body("_on_status_tick_damage_for_party_dialogue")
	# The big branch must `return` before reaching the low_hp branch.
	var big_idx: int = body.find("if big:")
	var low_idx: int = body.find("if pre_hp_pct >=")
	assert_gt(big_idx, -1)
	assert_gt(low_idx, -1)
	assert_lt(big_idx, low_idx, "big branch must be checked first")
	# Pin the return inside big branch (between big_idx and low_idx).
	var window: String = body.substr(big_idx, low_idx - big_idx)
	assert_true(window.contains("return"),
		"big_hit branch must `return` — prevents firing both quips on the same tick")


# ── Connect site at start_battle ─────────────────────────────────────────

func test_start_battle_connects_status_tick_per_party_member() -> void:
	# Pin the connect loop. status_tick_damage is per-Combatant
	# (unlike damage_dealt which is on BattleManager itself), so
	# we connect inside the for-each-party-member loop.
	var body := _fn_body("start_battle")
	assert_true(body.contains("member.status_tick_damage.connect(_on_status_tick_damage_for_party_dialogue.bind(member))"),
		"start_battle must connect status_tick_damage on each party member")
	assert_true(body.contains("if not member.status_tick_damage.is_connected(_on_status_tick_damage_for_party_dialogue):"),
		"connect must be guarded with is_connected to avoid duplicate handlers across battle restarts")


# ── Pre-existing damage_dealt handler still wired ───────────────────────

func test_damage_dealt_handler_still_wired() -> void:
	# Negative regression: don't accidentally remove the existing
	# damage_dealt subscription while wiring the new tick path.
	var body := _fn_body("start_battle")
	assert_true(body.contains("damage_dealt.connect(_on_damage_dealt_for_party_dialogue)"),
		"existing damage_dealt subscription must remain wired — sanity")


# ── pre_hp_pct calculation matches damage handler ────────────────────────

func test_pre_hp_pct_calc_matches_damage_handler() -> void:
	# Both handlers use the same pre_hp_pct formula:
	# (current_hp + amount) / max(max_hp, 1) * 100.
	var tick_body := _fn_body("_on_status_tick_damage_for_party_dialogue")
	var dmg_body := _fn_body("_on_damage_dealt_for_party_dialogue")
	var calc: String = "float(target.current_hp + amount) / float(maxi(target.max_hp, 1)) * 100.0"
	assert_true(tick_body.contains(calc),
		"tick handler must use the same pre_hp_pct formula as the damage handler")
	assert_true(dmg_body.contains(calc),
		"damage handler must still use the canonical pre_hp_pct formula")
