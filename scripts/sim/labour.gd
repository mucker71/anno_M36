class_name Labour
extends RefCounted
## Matches workers in housing to jobs they can walk to.
##
## Each housing block offers workers of its caste (fewer if its district's
## basic needs are short). Jobs are filled nearest-first along the people
## network (walkways and roads), up to WALK_RANGE tiles. Long commutes cost
## efficiency, so housing near work is worth the space it takes.
## Workers may cross district lines: a housing district can feed an industrial one.
##
## The result also drives the crowd visuals: every assignment is a real route.

const WALK_RANGE := 60            ## TUNE: furthest commute in tiles
const LONG_COMMUTE_PENALTY := 0.4 ## TUNE: efficiency lost at full range
const BASE_AVAILABILITY := 0.4    ## share of residents who work even when needs fail

class Assignment:
	var housing: BuildingInstance
	var job: BuildingInstance
	var caste: StringName
	var workers: int
	var distance: int

var grid: BuildGrid
var assignments: Array[Assignment] = []
## Per housing uid: tile distance map over the people graph. Rebuilt on topology change.
var _dist_cache: Dictionary = {}
var _cache_version := -1


func _init(p_grid: BuildGrid) -> void:
	grid = p_grid


## basic_satisfaction(district_id, caste) -> 0..1 supplies how hungry each block is.
func allocate(basic_satisfaction: Callable) -> void:
	if _cache_version != grid.topology_version:
		_dist_cache.clear()
		_cache_version = grid.topology_version
	assignments.clear()

	var housing: Array[BuildingInstance] = []
	var available := {}   # uid -> workers left
	for b in grid.buildings:
		b.workers_assigned.clear()
		if b.def.is_housing():
			housing.append(b)
			var sat: float = basic_satisfaction.call(b.district_id, b.def.housing_caste) if b.market_access else 0.0
			available[b.uid] = int(b.def.housing_capacity * (BASE_AVAILABILITY + (1.0 - BASE_AVAILABILITY) * sat))
			if not _dist_cache.has(b.uid):
				var starts := grid.transport.touching(b.cells, TransportGrid.Graph.PEOPLE)
				_dist_cache[b.uid] = grid.transport.distances(TransportGrid.Graph.PEOPLE, starts, WALK_RANGE)

	for job in grid.buildings:
		var needed := job_requirements(job)
		if needed.is_empty():
			job.staffing = 1.0
			continue
		var job_tiles := grid.transport.touching(job.cells, TransportGrid.Graph.PEOPLE)
		var worst := 1.0
		for caste in needed:
			var want: int = needed[caste]
			if want <= 0:
				continue
			# Candidate homes of this caste, nearest first.
			var options := []
			for h in housing:
				if h.def.housing_caste != caste or int(available[h.uid]) <= 0:
					continue
				var d := _distance(h, job_tiles)
				if d >= 0:
					options.append([d, h])
			options.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1].uid < b[1].uid))
			var filled := 0.0
			var got := 0
			for o in options:
				if got >= want:
					break
				var h: BuildingInstance = o[1]
				var take := mini(want - got, int(available[h.uid]))
				available[h.uid] = int(available[h.uid]) - take
				got += take
				filled += take * (1.0 - LONG_COMMUTE_PENALTY * float(o[0]) / WALK_RANGE)
				var a := Assignment.new()
				a.housing = h
				a.job = job
				a.caste = caste
				a.workers = take
				a.distance = o[0]
				assignments.append(a)
				h.workers_assigned[caste] = int(h.workers_assigned.get(caste, 0)) + take
			job.workers_assigned[caste] = got
			worst = minf(worst, filled / want)
		job.staffing = worst


## Workers a building wants per caste, after module effects.
static func job_requirements(b: BuildingInstance) -> Dictionary:
	var out := {}
	if b.def.workers.is_empty() or b.def.is_housing():
		return out
	if b.def.is_module() and b.host == null:
		return out
	var mult := b.effect("workers")
	for caste in b.def.workers:
		out[caste] = maxi(1, int(round(int(b.def.workers[caste]) * mult)))
	return out


## Walking distance from a home to a workplace, or -1 if out of reach.
func _distance(h: BuildingInstance, job_tiles: Array[Vector2i]) -> int:
	var dist: Dictionary = _dist_cache.get(h.uid, {})
	var best := -1
	for t in job_tiles:
		if dist.has(t):
			var d := int(dist[t])
			if best < 0 or d < best:
				best = d
	return best
