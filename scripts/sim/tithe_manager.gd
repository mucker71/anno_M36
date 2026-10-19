class_name TitheManager
extends RefCounted
## The Imperial tithe: the main pressure source. Every cycle the Administratum
## demands a new mix of goods, growing in size and changing in kind, so a hive
## built to make one thing well is always about to be wrong.
## TODO: the win and loss conditions are an open question in the design doc.

signal cycle_started(cycle: int, quota: Dictionary)
signal cycle_resolved(cycle: int, delivered: Dictionary, quota: Dictionary, ratio: float)

const CYCLE_LENGTH := 480.0      ## TUNE: seconds of game time per tithe cycle
const GROWTH_PER_CYCLE := 0.35   ## TUNE: quota scale added each cycle
const FAVOUR_START := 50.0

var economy: Economy
var rng := RandomNumberGenerator.new()
var cycle: int = 0
var time_left: float = CYCLE_LENGTH
var quota: Dictionary = {}       # item -> amount
var favour: float = FAVOUR_START ## 0..100. Imperial regard for the hive.
var history: Array = []          # [{ cycle, ratio }]
var _last_items: Array = []


func _init(p_economy: Economy, seed_value: int) -> void:
	economy = p_economy
	rng.seed = seed_value
	_start_cycle()


func advance(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		resolve()
		_start_cycle()


## Takes what it can from the Bastion district's stockpile and adjusts favour.
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
	history.append({"cycle": cycle, "ratio": ratio})
	cycle_resolved.emit(cycle, delivered, quota.duplicate(), ratio)


func _start_cycle() -> void:
	cycle += 1
	time_left = CYCLE_LENGTH
	quota = _make_quota(cycle)
	economy.tithe_quota = quota
	cycle_started.emit(cycle, quota.duplicate())


## Early cycles ask for basics; later ones mix in finished war materiel.
func _make_quota(n: int) -> Dictionary:
	var pool := []
	for def in Database.sorted_items():
		if not def.is_tithe_eligible():
			continue
		# The first tithe is always plain steel, so the opening goal is clear.
		if n <= 1 and def.id != &"steel":
			continue
		if n <= 3 and def.tier > ItemDef.Tier.COMPONENT and def.id != &"autogun_rounds":
			continue
		pool.append(def)
	var count := clampi(1 + int(n / 2.0), 1, 3)
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
		var scale := 1.0 + GROWTH_PER_CYCLE * (n - 1)
		picked[choice.id] = int(round(choice.tithe_base * scale * rng.randf_range(0.8, 1.2)))
	_last_items = picked.keys()
	return picked
