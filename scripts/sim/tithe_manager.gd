class_name TitheManager
extends RefCounted
## The Imperial tithe: the main pressure source, and the source of charters.
##
## Founding: no tithe is levied until the hive houses FOUNDING_POPULATION
## citizens. Reaching it founds the hive, grants one charter and starts cycle 1.
##
## After that, every cycle the Administratum demands a new mix of goods,
## growing in size and changing in kind, so a hive built to make one thing well
## is always about to be wrong. Demands are drawn only from tithe goods the
## hive's unlocked buildings can make. Delivery earns charters: two for full
## delivery, one for 75% or more, none below.
## TODO: the win and loss conditions are an open question in the design doc.

signal hive_founded
signal cycle_started(cycle: int, quota: Dictionary)
signal cycle_resolved(cycle: int, delivered: Dictionary, quota: Dictionary, ratio: float, charters: int)

const FOUNDING_POPULATION := 2500 ## TUNE: citizens housed before the first tithe
const FOUNDING_CHARTERS := 1
const CYCLE_LENGTH := 480.0      ## TUNE: seconds of game time per tithe cycle
const GROWTH_PER_CYCLE := 0.35   ## TUNE: quota scale added each cycle
const FAVOUR_START := 50.0

var economy: Economy
var unlocks: Unlocks
var rng := RandomNumberGenerator.new()
var founded := false
var cycle: int = 0
var time_left: float = CYCLE_LENGTH
var quota: Dictionary = {}       # item -> amount
var favour: float = FAVOUR_START ## 0..100. Imperial regard for the hive.
var history: Array = []          # [{ cycle, ratio }]
var _last_items: Array = []


func _init(p_economy: Economy, seed_value: int, p_unlocks: Unlocks = null) -> void:
	economy = p_economy
	unlocks = p_unlocks
	rng.seed = seed_value


func advance(delta: float) -> void:
	if not founded:
		if economy.total_population() >= FOUNDING_POPULATION:
			found()
		return
	time_left -= delta
	if time_left <= 0.0:
		resolve()
		_start_cycle()


## Founds the hive: first charter and the first tithe cycle.
func found() -> void:
	if founded:
		return
	founded = true
	if unlocks:
		unlocks.award(FOUNDING_CHARTERS)
	hive_founded.emit()
	_start_cycle()


## Takes what it can from the Bastion district's stockpile, adjusts favour
## and awards charters.
func resolve() -> void:
	var delivered := {}
	var total_owed := 0
	var total_given := 0
	for item in quota:
		var owed := int(quota[item])
		var given := economy.tithe_take(item, owed)
		delivered[item] = given
		total_owed += owed
		total_given += given
	var ratio := 1.0 if total_owed == 0 else float(total_given) / float(total_owed)
	# Full delivery earns favour, anything under three quarters costs it.
	favour = clampf(favour + (ratio - 0.75) * 40.0, 0.0, 100.0)
	var earned := charters_for(ratio)
	if unlocks:
		unlocks.award(earned)
	history.append({"cycle": cycle, "ratio": ratio})
	cycle_resolved.emit(cycle, delivered, quota.duplicate(), ratio, earned)


static func charters_for(ratio: float) -> int:
	if ratio >= 0.999:
		return 2
	if ratio >= 0.75:
		return 1
	return 0


func _start_cycle() -> void:
	cycle += 1
	time_left = CYCLE_LENGTH
	quota = _make_quota(cycle)
	economy.tithe_quota = quota
	cycle_started.emit(cycle, quota.duplicate())


## Early cycles ask for basics; later ones mix in finished war materiel, but
## only goods the hive is permitted to make.
func _make_quota(n: int) -> Dictionary:
	var pool := []
	for def in Database.sorted_items():
		if not def.is_tithe_eligible():
			continue
		if unlocks and not unlocks.can_produce(def.id):
			continue
		# The first tithe is always plain steel, so the opening goal is clear.
		if n <= 1 and def.id != &"steel":
			continue
		if n <= 3 and def.tier > ItemDef.Tier.COMPONENT and def.id != &"autogun_rounds":
			continue
		pool.append(def)
	if pool.is_empty():
		pool.append(Database.item(&"steel"))
	var count := clampi(1 + int(n / 2.0), 1, 3)
	var scale := 1.0 + GROWTH_PER_CYCLE * (n - 1)
	# With fewer goods to ask for than the cycle wants, ask for more of each.
	if pool.size() < count:
		scale *= float(count) / pool.size()
	var picked := {}
	var tries := 0
	while picked.size() < mini(count, pool.size()) and tries < 50:
		tries += 1
		var choice: ItemDef = pool[rng.randi() % pool.size()]
		if picked.has(choice.id):
			continue
		# Rotate: avoid repeating last cycle's items when there is a choice.
		if _last_items.has(choice.id) and pool.size() > count + _last_items.size() and tries < 25:
			continue
		picked[choice.id] = int(round(choice.tithe_base * scale * rng.randf_range(0.8, 1.2)))
	_last_items = picked.keys()
	return picked
