class_name CrowdSystem
extends Node3D
## Visual crowds driven by the simulation, not by randomness.
##
##  * Worker gangs: one per slice of each Labour assignment. A gang walks the
##    real shortest route from its housing block to its workplace on the
##    people network, works a shift out of sight, then walks home. Shifts are
##    staggered so the streets never empty at once. Gang members keep together
##    with small boid rules (cohesion to a slot behind the leader, separation
##    from each other) and are coloured by caste.
##  * Haulers: trucks shuttle on roads between a district depot and buildings
##    that have recently moved goods, more trucks for busier buildings.
##  * Trains and road freight: one convoy per active freight link, following
##    that link's actual rail or road path.
##
## Nothing here feeds back into the simulation.

const SHIFT_LENGTH := 40.0      ## seconds of game time per work cycle (compressed for readability)
const WALK_SPEED := 1.2         ## tiles per second
const TRUCK_SPEED := 4.0
const TRAIN_SPEED := 7.0
const WORKERS_PER_GANG := 25
const MAX_GANGS := 260
const FIGURES_PER_GANG := 3
const MAX_TRUCKS := 160
const MAX_TRAIN_CARS := 60
const REBUILD_INTERVAL := 1.0

class Mover:
	var path: Array[Vector3] = []
	var length: float = 0.0
	var offset: float = 0.0       # phase offset, seconds
	var colour: Color = Color.WHITE
	var figures: Array = []       # gangs: [{ "off": Vector2, "vel": Vector2 }]

var world: World
var _walkers := MultiMeshInstance3D.new()
var _trucks := MultiMeshInstance3D.new()
var _trains := MultiMeshInstance3D.new()
var _gangs: Dictionary = {}    # key -> Mover
var _haulers: Array[Mover] = []
var _convoys: Array = []       # [Mover, is_rail]
var _path_cache: Dictionary = {}
var _cache_version := -1
var _rebuild_timer := 0.0


func setup(p_world: World) -> void:
	world = p_world
	_walkers.multimesh = _make_multimesh(_capsule(), MAX_GANGS * FIGURES_PER_GANG)
	_trucks.multimesh = _make_multimesh(_box(Vector3(0.34, 0.26, 0.52)), MAX_TRUCKS)
	_trains.multimesh = _make_multimesh(_box(Vector3(0.44, 0.38, 0.82)), MAX_TRAIN_CARS)
	for mm in [_walkers, _trucks, _trains]:
		mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mm)


func _process(delta: float) -> void:
	if world == null:
		return
	_rebuild_timer -= delta
	if _rebuild_timer <= 0.0:
		_rebuild_timer = REBUILD_INTERVAL
		_rebuild()
	var t := world.economy.time
	_draw_gangs(t, delta)
	_draw_shuttles(_trucks.multimesh, _haulers, t, TRUCK_SPEED, 1, 0.13)
	var trains: Array[Mover] = []
	var trucks_extra: Array[Mover] = []
	for c in _convoys:
		if c[1]:
			trains.append(c[0])
		else:
			trucks_extra.append(c[0])
	_draw_shuttles(_trains.multimesh, trains, t, TRAIN_SPEED, 3, 0.3)
	if not trucks_extra.is_empty():
		_draw_shuttles(_trucks.multimesh, trucks_extra, t, TRUCK_SPEED, 2, 0.13, _trucks.multimesh.visible_instance_count)


## Gang count actually walking (for tests and the HUD).
func active_gangs() -> int:
	return _gangs.size()


# --- Rebuilding from the simulation -------------------------------------------

func _rebuild() -> void:
	var grid := world.grid
	if _cache_version != grid.topology_version:
		_cache_version = grid.topology_version
		_path_cache.clear()
	var t := grid.transport

	# Gangs from labour assignments.
	var keep := {}
	for a in world.economy.labour.assignments:
		var key_base := "%d>%d|%s" % [a.housing.uid, a.job.uid, a.caste]
		var path := _cached_path("p" + key_base, TransportGrid.Graph.PEOPLE, a.housing.cells, a.job.cells)
		if path.size() < 2:
			continue
		var count := clampi(ceili(a.workers / float(WORKERS_PER_GANG)), 1, 6)
		for i in count:
			if keep.size() >= MAX_GANGS:
				break
			var key := "%s#%d" % [key_base, i]
			keep[key] = true
			var g: Mover = _gangs.get(key)
			if g == null:
				g = Mover.new()
				# Gangs from one assignment set out at even intervals through the shift.
				var base := float(abs(key_base.hash()) % 997) / 997.0 * SHIFT_LENGTH
				g.offset = base + SHIFT_LENGTH * float(i) / count
				var caste := Database.caste(a.caste)
				g.colour = caste.colour.lightened(0.55) if caste else Color.WHITE
				for f in FIGURES_PER_GANG:
					g.figures.append({"off": Vector2(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1)), "vel": Vector2.ZERO})
				_gangs[key] = g
			_set_path(g, path, 0.26)
	for key in _gangs.keys():
		if not keep.has(key):
			_gangs.erase(key)

	# Haulers between depots and busy buildings.
	_haulers.clear()
	for b in grid.buildings:
		if b.hauled_recent < 1.0 or not b.road_access or b.def.is_depot:
			continue
		var d := world.economy.district(b.district_id)
		if d == null or d.depots.is_empty():
			continue
		var depot: BuildingInstance = d.depots[0]
		var path := _cached_path("h%d>%d" % [depot.uid, b.uid], TransportGrid.Graph.ROAD, depot.cells, b.cells)
		if path.size() < 2:
			continue
		var n := clampi(int(b.hauled_recent / 8.0) + 1, 1, 3)
		for i in n:
			if _haulers.size() >= MAX_TRUCKS:
				break
			var m := Mover.new()
			m.colour = b.def.colour.lightened(0.3)
			_set_path(m, path, 0.13)
			m.offset = (float(i) / n) * 2.0 * m.length / TRUCK_SPEED + float(b.uid % 7)
			_haulers.append(m)

	# Convoys on freight links.
	_convoys.clear()
	for l in world.economy.freight.links:
		if l.flow_recent < 1.0 or l.path.size() < 2:
			continue
		var m := Mover.new()
		m.colour = Color(0.55, 0.5, 0.45) if l.rail else Color(0.7, 0.6, 0.4)
		_set_path(m, l.path, 0.3 if l.rail else 0.13)
		m.offset = float((l.a * 13 + l.b * 7) % 11)
		_convoys.append([m, l.rail])


func _cached_path(key: String, graph: int, from_cells: Array, to_cells: Array) -> Array[Vector2i]:
	if _path_cache.has(key):
		return _path_cache[key]
	var t := world.grid.transport
	var path := t.find_path(graph, t.touching(from_cells, graph), t.touching(to_cells, graph))
	_path_cache[key] = path
	return path


func _set_path(m: Mover, tiles: Array[Vector2i], y: float) -> void:
	if m.path.size() == tiles.size() and not m.path.is_empty() \
			and m.path[0] == _centre(tiles[0], y) and m.path[-1] == _centre(tiles[-1], y):
		return
	m.path.clear()
	for c in tiles:
		m.path.append(_centre(c, y))
	m.length = float(tiles.size() - 1)


static func _centre(c: Vector2i, y: float) -> Vector3:
	return Vector3(c.x + 0.5, y, c.y + 0.5)


# --- Drawing ------------------------------------------------------------------

## Position and heading along a path at distance s (in tiles).
static func sample(path: Array[Vector3], s: float) -> Array:
	var n := path.size()
	if n == 0:
		return [Vector3.ZERO, Vector3.FORWARD]
	if n == 1:
		return [path[0], Vector3.FORWARD]
	s = clampf(s, 0.0, n - 1.0)
	var i := mini(int(floor(s)), n - 2)
	var f := s - i
	var a := path[i]
	var b := path[i + 1]
	return [a.lerp(b, f), (b - a).normalized()]


func _draw_gangs(t: float, delta: float) -> void:
	var mm := _walkers.multimesh
	var idx := 0
	for g: Mover in _gangs.values():
		var walk := g.length / WALK_SPEED
		var stay := maxf(3.0, (SHIFT_LENGTH - 2.0 * walk) / 2.0)
		var cycle := 2.0 * walk + 2.0 * stay
		var phase := fmod(t + g.offset, cycle)
		var s := -1.0
		var forward := true
		if phase < walk:
			s = phase * WALK_SPEED
		elif phase >= walk + stay and phase < 2.0 * walk + stay:
			s = g.length - (phase - walk - stay) * WALK_SPEED
			forward = false
		if s < 0.0:
			continue   # at work or at home: out of sight
		var sample_res := sample(g.path, s)
		var pos: Vector3 = sample_res[0]
		var dir: Vector3 = sample_res[1] if forward else -sample_res[1]
		var fwd := Vector2(dir.x, dir.z)
		var side := Vector2(-fwd.y, fwd.x)
		_step_boids(g, fwd, side, delta)
		for f in g.figures:
			if idx >= mm.instance_count:
				break
			var off: Vector2 = f["off"]
			var p := pos + Vector3(off.x, 0.0, off.y)
			var basis := Basis.looking_at(Vector3(dir.x, 0, dir.z) if dir.length() > 0.01 else Vector3.FORWARD)
			mm.set_instance_transform(idx, Transform3D(basis, p))
			mm.set_instance_color(idx, g.colour)
			idx += 1
	mm.visible_instance_count = idx


## Cohesion toward a slot trailing the leader, separation from neighbours,
## damped velocity, and a cap so the gang stays on the path's width.
func _step_boids(g: Mover, fwd: Vector2, side: Vector2, delta: float) -> void:
	var dt := minf(delta, 0.05)
	var figs := g.figures
	for i in figs.size():
		var f: Dictionary = figs[i]
		var off: Vector2 = f["off"]
		var vel: Vector2 = f["vel"]
		var slot := -fwd * 0.22 * i + side * (0.12 if i % 2 == 1 else -0.06 * i)
		var steer := (slot - off) * 6.0
		for j in figs.size():
			if j == i:
				continue
			var other: Vector2 = figs[j]["off"]
			var away := off - other
			var d := away.length()
			if d < 0.16 and d > 0.0001:
				steer += away / d * (0.16 - d) * 40.0
		vel = (vel + steer * dt) * 0.85
		off += vel * dt
		if off.length() > 0.45:
			off = off.normalized() * 0.45
		f["off"] = off
		f["vel"] = vel


func _draw_shuttles(mm: MultiMesh, movers: Array, t: float, speed: float, cars: int,
		y: float, start: int = 0) -> void:
	var idx := start
	for m: Mover in movers:
		if m.length <= 0.0:
			continue
		var trip := m.length / speed
		var phase := fmod(t + m.offset, 2.0 * trip)
		var forward := phase < trip
		var head := phase * speed if forward else m.length - (phase - trip) * speed
		for c in cars:
			if idx >= mm.instance_count:
				break
			var s := head - c * 0.9 if forward else head + c * 0.9
			var res := sample(m.path, s)
			var dir: Vector3 = res[1] if forward else -res[1]
			var basis := Basis.looking_at(dir if dir.length() > 0.01 else Vector3.FORWARD)
			mm.set_instance_transform(idx, Transform3D(basis, res[0]))
			mm.set_instance_color(idx, m.colour)
			idx += 1
	mm.visible_instance_count = idx


static func _make_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	return mm


static func _capsule() -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = 0.11
	m.height = 0.5
	m.radial_segments = 6
	m.rings = 2
	var mat := _instance_colour_material()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # read clearly against the ground
	m.material = mat
	return m


static func _box(size: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	m.material = _instance_colour_material()
	return m


static func _instance_colour_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	return mat
