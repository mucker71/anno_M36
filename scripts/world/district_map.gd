class_name DistrictMap
extends RefCounted
## Districts are painted areas of the map. Every building sits wholly inside
## one district. Each district keeps its own stockpile, needs, workforce and
## morale, so a hive is many local economies tied together by transport.

signal changed

const MAX_DISTRICTS := 8
const NAMES := ["Bastion Ward", "Ward Secundus", "Ward Tertius", "Ward Quartus",
	"Ward Quintus", "Ward Sextus", "Ward Septimus", "Ward Octavus"]
const COLOURS := [Color(0.85, 0.70, 0.30), Color(0.35, 0.65, 0.85), Color(0.75, 0.35, 0.35),
	Color(0.45, 0.75, 0.40), Color(0.70, 0.45, 0.80), Color(0.85, 0.55, 0.25),
	Color(0.40, 0.75, 0.75), Color(0.80, 0.80, 0.80)]


class District:
	var id: int
	var name: String
	var colour: Color
	var stockpile: Dictionary = {}           # item -> int
	## Stock the district wants on hand, from local consumption (set by Freight).
	var targets: Dictionary = {}             # item -> int
	var depots: Array = []                   # BuildingInstance
	var stations: Array = []                 # BuildingInstance
	var haul_capacity: float = 0.0           # units per second over roads
	var haul_load: float = 0.0               # smoothed fraction used
	var population: Dictionary = {}          # caste -> housed citizens
	var employed: Dictionary = {}            # caste -> residents with jobs
	var jobs: Dictionary = {}                # caste -> workers wanted here
	var basic_satisfaction: Dictionary = {}  # caste -> 0..1
	var comfort_satisfaction: Dictionary = {}
	var fervour_coverage: int = 0
	var order_coverage: int = 0
	var morale: float = 0.5
	var productivity: float = 1.0
	var need_owed: Dictionary = {}
	var need_met: Dictionary = {}

	func amount(item: StringName) -> int:
		return int(stockpile.get(item, 0))

	func add(item: StringName, n: int) -> void:
		if n != 0:
			stockpile[item] = amount(item) + n

	func take(item: StringName, n: int) -> int:
		var got := mini(n, amount(item))
		if got > 0:
			stockpile[item] = amount(item) - got
		return got

	func total_population() -> int:
		var t := 0
		for c in population:
			t += int(population[c])
		return t


var size: Vector2i
var districts: Array[District] = []
var _cells: Dictionary = {}   # Vector2i -> district id


func _init(map_size: Vector2i) -> void:
	size = map_size


func create() -> District:
	if districts.size() >= MAX_DISTRICTS:
		return null
	var d := District.new()
	d.id = districts.size()
	d.name = NAMES[d.id]
	d.colour = COLOURS[d.id]
	districts.append(d)
	changed.emit()
	return d


func get_district(id: int) -> District:
	return districts[id] if id >= 0 and id < districts.size() else null


func id_at(c: Vector2i) -> int:
	return int(_cells.get(c, -1))


func at(c: Vector2i) -> District:
	return get_district(id_at(c))


## Assigns cells (id -1 clears). The caller filters out cells under buildings.
func paint(cells: Array, id: int) -> void:
	for c in cells:
		if id < 0:
			_cells.erase(c)
		else:
			_cells[c] = id
	changed.emit()


func cell_count(id: int) -> int:
	var n := 0
	for c in _cells:
		if int(_cells[c]) == id:
			n += 1
	return n


func painted_cells() -> Dictionary:
	return _cells


## The district a footprint sits in, or -1 if it is outside or straddles two.
func district_of(cells: Array) -> int:
	var id := -2
	for c in cells:
		var here := id_at(c)
		if here < 0:
			return -1
		if id == -2:
			id = here
		elif here != id:
			return -1
	return maxi(id, -1)
