extends RefCounted
class_name BattleMenuPlacer

## Where a battle menu goes, and why (struktured via main 23421: "we need to be hyperintelligent about where to place
## the menus, and why"). One solver for the command menu, its submenus, the tooltip and the zoom chip, used only while
## a player drives the menu by hand (main 23422: autobattle and the grind keep the cheap placement).
##
## Candidates are scored in two tiers. HARD constraints reject a slot outright: off-screen, over a HUD panel, over the
## targeted monster, over a targetable battler's nameplate, over an ancestor menu, or a tooltip not flush with its menu.
## SOFT terms rank what survives: battlers covered (target-list ones cost 3x), distance from the actor, the jump from
## the last placement, leaving this turn's side, and room to spare. Only when NO slot passes HARD does it relax, first
## allowing ancestor cover and then target cover, and `why` says so (main 23420: a packed screen may overlap, minimally).
## Static and scene-free: a test drives it with rects.

const STEP := 24.0
const FLUSH := 6.0
const GAP := 4.0
const MARGIN := 8.0
const W_TARGET_LIST := 3.0
const W_BATTLER := 1.0
const W_DISTANCE := 0.02
const W_JUMP := 0.06
const W_SIDE := 400.0
const W_ROOM := 2.0


## req: {kind: "root"|"submenu"|"tooltip"|"chip", size, vp, actor, parent, ancestors[], target, target_list[],
##       battlers[], hud[], nameplates[], last, side}. Missing keys mean "none". Returns {rect, why, slot, cost, relaxed}.
static func solve(req: Dictionary) -> Dictionary:
	var cands: Array = candidates(req)
	var best := {}
	for relax in [0, 1, 2]:
		for c in cands:
			var verdict := _hard(req, c["rect"], relax)
			if verdict != "":
				c["killed"] = verdict
				continue
			var scored := _score(req, c)
			if best.is_empty() or scored["cost"] < best["cost"]:
				best = scored
				best["relaxed"] = relax
		if not best.is_empty():
			break
	if best.is_empty():
		var size: Vector2 = req.get("size", Vector2.ZERO)
		var vp: Vector2 = req.get("vp", Vector2(1280, 720))
		return {"rect": Rect2((vp - size) * 0.5, size), "why": "no slot fits on screen; centred", "slot": "centre", "cost": INF, "relaxed": 3}
	best["why"] = _why(req, best, cands)
	return best


## Every slot this kind may take: beside its anchor on four sides, plus (root/submenu) a grid over the free field.
static func candidates(req: Dictionary) -> Array:
	var kind: String = str(req.get("kind", "root"))
	var size: Vector2 = req.get("size", Vector2.ZERO)
	var vp: Vector2 = req.get("vp", Vector2(1280, 720))
	var out: Array = []
	var anchor: Rect2 = req.get("parent", Rect2()) if kind != "root" else req.get("actor", Rect2())
	if kind == "chip":
		var inner := anchor.grow(-GAP)
		out.append({"slot": "inside bottom-right", "rect": Rect2(inner.end - size, size)})
		out.append({"slot": "inside bottom-left", "rect": Rect2(Vector2(inner.position.x, inner.end.y - size.y), size)})
		out.append({"slot": "inside top-right", "rect": Rect2(Vector2(inner.end.x - size.x, inner.position.y), size)})
		return out
	var gap: float = 0.0 if kind == "tooltip" else GAP
	if anchor.has_area():
		out.append({"slot": "left of %s" % _noun(kind), "rect": Rect2(Vector2(anchor.position.x - gap - size.x, anchor.position.y), size)})
		out.append({"slot": "right of %s" % _noun(kind), "rect": Rect2(Vector2(anchor.end.x + gap, anchor.position.y), size)})
		out.append({"slot": "below %s" % _noun(kind), "rect": Rect2(Vector2(anchor.position.x, anchor.end.y + gap), size)})
		out.append({"slot": "above %s" % _noun(kind), "rect": Rect2(Vector2(anchor.position.x, anchor.position.y - gap - size.y), size)})
		# Flush variants aligned to the anchor's other edge, so a list taller than its parent can still sit beside it.
		out.append({"slot": "left of %s, bottom-aligned" % _noun(kind), "rect": Rect2(Vector2(anchor.position.x - gap - size.x, anchor.end.y - size.y), size)})
		out.append({"slot": "right of %s, bottom-aligned" % _noun(kind), "rect": Rect2(Vector2(anchor.end.x + gap, anchor.end.y - size.y), size)})
	if kind == "tooltip":
		return out
	var y := MARGIN
	while y + size.y <= vp.y - MARGIN:
		var x := MARGIN
		while x + size.x <= vp.x - MARGIN:
			out.append({"slot": "field @%d,%d" % [int(x), int(y)], "rect": Rect2(Vector2(x, y), size)})
			x += STEP
		y += STEP
	return out


## "" when the slot is legal, else the first constraint it breaks. relax 1 allows ancestor cover, 2 also target cover.
static func _hard(req: Dictionary, r: Rect2, relax: int) -> String:
	var vp: Vector2 = req.get("vp", Vector2(1280, 720))
	if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > vp.x or r.end.y > vp.y:
		return "off-screen"
	for h in req.get("hud", []):
		if r.intersects(h["rect"]):
			return "over %s" % h["id"]
	for n in req.get("nameplates", []):
		if r.intersects(n["rect"]):
			return "over %s's name" % n["id"]
	if relax < 1:
		for a in req.get("ancestors", []):
			if r.intersects(a):
				return "over its parent menu"
	if relax < 2:
		var t = req.get("target", null)
		if t is Dictionary and r.intersects(t["rect"]):
			return "over the target %s" % t["id"]
	if str(req.get("kind", "")) == "tooltip":
		var p: Rect2 = req.get("parent", Rect2())
		if not r.grow(FLUSH).intersects(p):
			return "detached from its menu"
	return ""


static func _score(req: Dictionary, c: Dictionary) -> Dictionary:
	var r: Rect2 = c["rect"]
	var terms := {}
	var t = req.get("target", null)
	if t is Dictionary:
		terms["target cover"] = _area(r, t["rect"]) * W_TARGET_LIST * 3.0
	var tl := 0.0
	for b in req.get("target_list", []):
		tl += _area(r, b["rect"])
	terms["target-list cover"] = tl * W_TARGET_LIST
	var other := 0.0
	for b in req.get("battlers", []):
		other += _area(r, b["rect"])
	terms["battler cover"] = other * W_BATTLER
	var actor: Rect2 = req.get("actor", Rect2())
	if actor.has_area():
		terms["distance"] = r.get_center().distance_to(actor.get_center()) * W_DISTANCE * r.size.length()
	var last: Rect2 = req.get("last", Rect2())
	if last.has_area():
		terms["jump"] = r.get_center().distance_to(last.get_center()) * W_JUMP * r.size.length()
	var side: String = str(req.get("side", ""))
	if side != "" and actor.has_area():
		var mine := "left" if r.get_center().x < actor.get_center().x else "right"
		terms["side change"] = W_SIDE if mine != side else 0.0
	terms["room"] = -_room(req, r) * W_ROOM
	var cost := 0.0
	for k in terms:
		cost += terms[k]
	return {"rect": r, "slot": c["slot"], "cost": cost, "terms": terms}


## The clearance to the nearest obstacle, capped, so a slot with breathing room beats one that just scrapes past.
static func _room(req: Dictionary, r: Rect2) -> float:
	var best := 48.0
	var obstacles: Array = []
	for h in req.get("hud", []):
		obstacles.append(h["rect"])
	for a in req.get("ancestors", []):
		obstacles.append(a)
	var t = req.get("target", null)
	if t is Dictionary:
		obstacles.append(t["rect"])
	for o in obstacles:
		best = minf(best, _gap(r, o))
	return maxf(best, 0.0)


static func _gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
	var dy := maxf(0.0, maxf(b.position.y - a.end.y, a.position.y - b.end.y))
	return maxf(dx, dy)


static func _area(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	return i.size.x * i.size.y if i.size.x > 0.0 and i.size.y > 0.0 else 0.0


## One line: the slot, the term that decided it, and the best rival slot with what ruled it out.
static func _why(req: Dictionary, best: Dictionary, cands: Array) -> String:
	var lead := ""
	var t = req.get("target", null)
	if int(best.get("relaxed", 0)) >= 2 and t is Dictionary:
		lead = "packed: no clear slot; least cover = %s %d px²" % [t["id"], int(_area(best["rect"], t["rect"]))]
	elif int(best.get("relaxed", 0)) == 1:
		lead = "packed: overlaps its parent menu, nothing else fits"
	elif t is Dictionary:
		lead = "target %s clear" % t["id"]
	else:
		var top_k := ""
		var top_v := -INF
		for k in best["terms"]:
			if absf(float(best["terms"][k])) > top_v:
				top_v = absf(float(best["terms"][k]))
				top_k = k
		lead = "decided by %s" % top_k
	var rival := ""
	for c in cands:
		if c["slot"] != best["slot"] and c.has("killed") and not str(c["slot"]).begins_with("field"):
			rival = "; %s %s" % [c["slot"], c["killed"]]
			break
	return "%s %s: %s%s" % [str(req.get("kind", "root")), best["slot"], lead, rival]


static func _noun(kind: String) -> String:
	return "actor" if kind == "root" else ("menu" if kind == "tooltip" else "parent")
