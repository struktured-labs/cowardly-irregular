extends GutTest

## A boss's charge turn (cowir-battle's cadence, .795) is the player's window, and on a couch the pad should say so too
## (cowir-controller 23908): a soft pulse when the charge starts, a sharper tick when the party breaks it. Both ride
## BattleJuice.rumble, so Pad Rumble and the OFF tier gate them like every other rumble. The arms emit BattleManager's
## REAL signals and read BattleJuice.rumble_wanted, so the autoload's own connection is what is judged.

var _flags_before: Dictionary = {}
var _wanted: Array = []
var _boss: Combatant = null


func before_each() -> void:
	_flags_before = GameState.battle_fx_flags.duplicate(true)
	BattleJuice._last_rumble_at = -1.0
	BattleJuice._last_rumble_amount = 0.0
	Engine.time_scale = 1.0
	_wanted = []
	BattleJuice.rumble_wanted.connect(_on_wanted)
	_boss = Combatant.new()
	_boss.combatant_name = "Glacius"
	add_child_autofree(_boss)


func after_each() -> void:
	BattleJuice.rumble_wanted.disconnect(_on_wanted)
	GameState.battle_fx_flags = _flags_before
	BattleJuice._last_rumble_at = -1.0
	Engine.time_scale = 1.0


func _on_wanted(amount: float) -> void:
	_wanted.append(amount)


func _fresh() -> void:
	BattleJuice._last_rumble_at = -1.0
	BattleJuice._last_rumble_amount = 0.0
	_wanted = []


func test_the_floor_names_every_member_this_file_drives() -> void:
	assert_true(BattleManager.has_signal("boss_charge_changed") and BattleManager.has_signal("boss_charge_broken"), "BattleManager.boss_charge_changed / boss_charge_broken must exist")
	assert_true(BattleJuice.has_signal("rumble_wanted") and "_last_rumble_at" in BattleJuice, "BattleJuice.rumble_wanted / _last_rumble_at must exist")
	assert_true("CHARGE_RUMBLE" in BattleJuice and "BREAK_RUMBLE" in BattleJuice, "BattleJuice.CHARGE_RUMBLE / BREAK_RUMBLE must exist")
	assert_true("battle_fx_flags" in GameState, "GameState.battle_fx_flags must exist")


## The wiring is the autoload's own, made once: a second connection would rumble twice per charge.
func test_battlejuice_listens_to_both_signals_once() -> void:
	assert_true(BattleManager.boss_charge_changed.is_connected(BattleJuice._on_boss_charge_changed), "BattleJuice listens for a charge changing")
	assert_true(BattleManager.boss_charge_broken.is_connected(BattleJuice._on_boss_charge_broken), "and for a charge broken")
	BattleJuice._ready()
	BattleManager.boss_charge_changed.emit(_boss, true)
	assert_eq(_wanted.size(), 1, "re-running _ready adds no second connection: one charge, one rumble")


func test_a_charge_starting_is_a_soft_pulse() -> void:
	BattleManager.boss_charge_changed.emit(_boss, true)
	assert_eq(_wanted, [BattleJuice.CHARGE_RUMBLE], "the charge starting wants the pad once, softly")
	assert_lt(BattleJuice.CHARGE_RUMBLE, 0.35, "softer than the lightest hit that rumbles (0.35 + 0.1 x power)")


## The false edge covers release, interrupt, death and end_battle: none of them is a new event in the hands.
func test_a_charge_ending_wants_nothing() -> void:
	BattleManager.boss_charge_changed.emit(_boss, false)
	assert_eq(_wanted, [], "a charge ending, by any route, does not rumble by itself")


func test_breaking_a_charge_is_a_sharper_tick() -> void:
	BattleManager.boss_charge_broken.emit(_boss, "stun")
	BattleManager.boss_charge_changed.emit(_boss, false)   # battle emits the false edge right after the break
	assert_eq(_wanted, [BattleJuice.BREAK_RUMBLE], "the break wants the pad once, and its false edge adds nothing")
	assert_gt(BattleJuice.BREAK_RUMBLE, BattleJuice.CHARGE_RUMBLE, "the payoff is felt harder than the warning")


## The pad's own switch and the OFF tier gate both, as they gate every other rumble.
func test_pad_rumble_off_and_the_off_tier_stay_silent() -> void:
	GameState.battle_fx_flags["rumble"] = false
	BattleManager.boss_charge_changed.emit(_boss, true)
	BattleManager.boss_charge_broken.emit(_boss, "silence")
	assert_eq(_wanted, [], "Pad Rumble off: neither the charge nor the break wants the motors")
	GameState.battle_fx_flags["rumble"] = true
	_fresh()
	Engine.time_scale = 4.0
	BattleManager.boss_charge_changed.emit(_boss, true)
	BattleManager.boss_charge_broken.emit(_boss, "sleep")
	Engine.time_scale = 1.0
	assert_eq(_wanted, [], "at 4x the tier is OFF and the pad stays still")
	_fresh()
	BattleManager.boss_charge_changed.emit(_boss, true)
	assert_eq(_wanted.size(), 1, "CONTROL: back at 1x with rumble on, the same charge wants the pad")
