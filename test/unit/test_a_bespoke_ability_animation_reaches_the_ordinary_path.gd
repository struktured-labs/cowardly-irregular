extends GutTest

## Priority-2 ability/animation audit (2026-10-25): four job sheets carry per-ability art, and only
## `steal` ever reached a player outside Full Render — `_ability_anim_name` had ONE caller,
## `_play_ability_full_render`, so the ordinary path asked for the ability's `animation` FIELD (a
## shared bucket: "skill", "buff", "cast_meta") and a PHYSICAL ability asked for nothing at all,
## because `_animate_melee_attack` took no ability argument. These arms pin WHICH path plays the
## named art, and the control pins that a sheet without the art is unchanged.

## The SCENE, not the script: a bare BattleScene.gd.new() has no UI tree, so every UI write in the action path
## aborted (5 SCRIPT ERRORs per run: turn_info at BattleUIManager:970, then the turn-order strip at :1018/:1041)
## while each arm's own asserts still scored. 25 other battle tests already build the .tscn; this one was the outlier.
const SCENE := preload("res://src/battle/BattleScene.tscn")
const MANIFEST := "res://data/sprite_manifest.json"
const ABILITIES := "res://data/abilities.json"
const STD_ANIMS := ["idle", "walk", "attack", "hit", "dead", "death", "cast", "defend", "item",
	"victory", "defeat", "advance", "defer", "dash", "lunge", "run", "base", "weak"]

var _scene
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
var _bm_guard
var _saved_scale: float = 1.0
var _hero: Combatant
var _foe: Combatant


func _json(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


func _c(n: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 400, "max_mp": 80, "attack": 20, "defense": 10, "magic": 20, "speed": 10})
	add_child_autofree(c)
	return c


## A sheet is just its animation names here — the wiring claim must not depend on artist pixels.
func _sheet(names: Array) -> AnimatedSprite2D:
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(16, 16)
	var sf := SpriteFrames.new()
	for n in names:
		if not sf.has_animation(n):
			sf.add_animation(n)
		sf.add_frame(n, tex)
		sf.add_frame(n, tex)
		sf.set_animation_loop(n, false)
		## Slow on purpose: at a default 5 fps one frame outlives ~1 process frame at time_scale 8, and a frame-polled await can step straight over it.
		sf.set_animation_speed(n, 0.5)
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = sf
	spr.animation = "idle" if sf.has_animation("idle") else str(names[0])
	return spr


func _rig(hero_anims: Array, foe_anims: Array) -> Array:
	var hs := _sheet(hero_anims)
	hs.position = Vector2(900, 300)
	_scene.add_child(hs)
	var fs := _sheet(foe_anims)
	fs.position = Vector2(300, 300)
	_scene.add_child(fs)
	var ha := BattleAnimator.new()
	_scene.add_child(ha)
	ha.setup(hs)
	var fa := BattleAnimator.new()
	_scene.add_child(fa)
	fa.setup(fs)
	_scene.party_sprite_nodes.assign([hs])
	_scene.enemy_sprite_nodes.assign([fs])
	_scene.party_animators.assign([ha])
	_scene.enemy_animators.assign([fa])
	return [hs, fs]


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	## The real scene drives BattleManager into PLAYER_SELECTING, so the whole autoload is snapshotted, not just its parties.
	_bm_guard = BattleStateGuard.new()
	_bm_guard.snapshot()
	_saved_scale = Engine.time_scale
	_scene = SCENE.instantiate()
	add_child_autofree(_scene)
	_hero = _c("Fighter")
	_foe = _c("Goblin")
	_scene.party_members.assign([_hero] as Array[Combatant])
	_scene.test_enemies.assign([_foe] as Array[Combatant])
	BattleManager.player_party.assign([_hero] as Array[Combatant])
	BattleManager.enemy_party.assign([_foe] as Array[Combatant])
	## >0.55 keeps _full_render_active false — these arms are about the ORDINARY path — and runs the lunge tween out fast.
	Engine.time_scale = 8.0


func after_each() -> void:
	Engine.time_scale = _saved_scale
	_bm_guard.restore()


func _act(ability_id: String, targets: Array) -> void:
	_scene._on_action_executing(_hero, {"type": "ability", "ability_id": ability_id, "targets": targets})


## Wait for the CONDITION under a bound, never a wall-clock sleep (CLAUDE.md).
func _await_anim(spr: AnimatedSprite2D, want: String) -> bool:
	for _i in range(240):
		if spr.animation == want:
			return true
		await get_tree().process_frame
	return spr.animation == want


## Every animation name any sheet declares. `animations` is a LIST on battle sheets and a
## name->{row,frames} DICT on overworld ones, and casting blind aborts the caller mid-arm.
func _sheet_animation_names() -> Dictionary:
	var names := {}
	var manifest := _json(MANIFEST)
	for sec in manifest.keys():
		var rows: Variant = manifest[sec]
		if not (rows is Dictionary):
			continue
		for key in (rows as Dictionary).keys():
			var row: Variant = (rows as Dictionary)[key]
			if not (row is Dictionary):
				continue
			var anims: Variant = (row as Dictionary).get("animations", [])
			if anims is Array:
				for a in (anims as Array):
					names[str(a)] = true
			elif anims is Dictionary:
				for a in (anims as Dictionary).keys():
					names[str(a)] = true
	return names


## Ability ids some sheet draws by name. Derived, never listed — the set grew by one the day the
## Bard's songs landed, and a pinned list would have gone quietly stale instead of reporting it.
func _bespoke_ability_ids() -> Array:
	var sheet_anims := _sheet_animation_names()
	var abilities := _json(ABILITIES)
	var out: Array = []
	for aid in abilities.keys():
		if sheet_anims.has(str(aid)) and not STD_ANIMS.has(str(aid)):
			out.append(str(aid))
	out.sort()
	return out


func test_the_sheets_carry_per_ability_art_the_animation_field_cannot_request() -> void:
	var abilities := _json(ABILITIES)
	assert_gt(abilities.size(), 0, "abilities.json must parse")
	var bespoke: Array = _bespoke_ability_ids()
	assert_gt(bespoke.size(), 0, "a sheet somewhere must name an ability id, or there is no art to route")
	## The ones whose `animation` field names something else: the field physically cannot ask for them.
	var unrequestable: Array = []
	for aid in bespoke:
		var field: String = str((abilities[aid] as Dictionary).get("animation", ""))
		if field != aid:
			unrequestable.append("%s(field=%s)" % [aid, field])
	assert_gt(unrequestable.size(), 0,
		"If every bespoke id were also its own `animation` field this guard would be moot — it is not: " + str(unrequestable))
	gut.p("bespoke ability art: %d; unreachable via the `animation` field: %d -> %s"
		% [bespoke.size(), unrequestable.size(), str(unrequestable)])


func test_a_physical_ability_swings_its_own_art_at_the_contact_frame() -> void:
	var ability := JobSystem.get_ability("power_strike")
	assert_eq(str(ability.get("type", "")), "physical", "floor: power_strike must still be physical, or this arm tests the wrong branch")
	assert_ne(str(ability.get("animation", "")), "power_strike", "floor: the `animation` field must still be a bucket, else nothing was ever broken")
	var rig := _rig(["idle", "attack", "cast", "power_strike"], ["idle", "hit"])
	var hs: AnimatedSprite2D = rig[0]
	assert_ne(hs.animation, "power_strike", "control: the art is not already playing before the action")
	_act("power_strike", [_foe])
	var reached: bool = await _await_anim(hs, "power_strike")
	assert_true(reached,
		"a physical ability with its own sheet art must swing THAT at the contact frame; played '%s'. _animate_melee_attack takes an ability_anim argument for exactly this." % hs.animation)


func test_a_song_plays_its_own_art_instead_of_the_buff_bucket() -> void:
	var ability := JobSystem.get_ability("battle_hymn")
	assert_ne(str(ability.get("type", "")), "physical", "floor: battle_hymn must stay off the melee branch")
	assert_ne(str(ability.get("animation", "")), "battle_hymn", "floor: the `animation` field must still be a bucket")
	var rig := _rig(["idle", "attack", "cast", "battle_hymn"], ["idle", "hit"])
	var hs: AnimatedSprite2D = rig[0]
	_act("battle_hymn", [_hero])
	assert_eq(hs.animation, "battle_hymn",
		"the ordinary cast path must ask for the sheet's own art, not the '%s' bucket" % str(ability.get("animation", "")))


func test_a_sheet_without_the_art_is_left_exactly_as_it_was() -> void:
	## The loud direction: without this arm, "everything plays the id" would pass the two above.
	var rig := _rig(["idle", "attack", "cast"], ["idle", "hit"])
	var hs: AnimatedSprite2D = rig[0]
	_act("power_strike", [_foe])
	var swung: bool = await _await_anim(hs, "attack")
	assert_true(swung, "no bespoke art -> the generic attack still swings; played '%s'" % hs.animation)
	_act("battle_hymn", [_hero])
	assert_eq(hs.animation, "cast", "no bespoke art -> the bucket still resolves to cast")


func test_a_bucket_the_sheet_does_carry_still_wins_over_an_id_it_does_not() -> void:
	## `cure` has no art of its own and its bucket is `heal`, which the sheet HAS — so correct
	## behaviour is "heal" while an ungated id-always-wins is "cast". The arm above cannot tell those
	## apart: both of its fallbacks happen to land on the old answer, so it stays green either way.
	var ability := JobSystem.get_ability("cure")
	assert_eq(str(ability.get("animation", "")), "heal", "floor: cure's bucket must still be heal")
	var rig := _rig(["idle", "attack", "cast", "heal"], ["idle", "hit"])
	var hs: AnimatedSprite2D = rig[0]
	_act("cure", [_hero])
	assert_eq(hs.animation, "heal",
		"an id the sheet does not draw must lose to a bucket it does; 'cast' here means the sheet gate is gone")
