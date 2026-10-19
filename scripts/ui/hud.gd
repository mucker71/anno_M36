class_name Hud
extends CanvasLayer
## Prototype HUD, built in code so it is easy to change while the design moves.
## Covers: build menu (with transport, module and district tools), stockpile
## per district or hive-wide, building and district inspection, the tithe bar
## and a message log. Production statistics, the in-game wiki and settings
## menus from the design doc are still to do.

const CATEGORIES := [
	[&"transport", "Transport"], [&"extraction", "Extract"], [&"industry", "Industry"],
	[&"module", "Modules"], [&"civic", "Civic"], [&"housing", "Housing"],
	[&"service", "Services"], [&"districts", "Districts"],
]
const TEXT := Color(0.86, 0.80, 0.66)
const TEXT_DIM := Color(0.55, 0.51, 0.44)
const BRASS := Color(0.62, 0.47, 0.20)
const GOOD := Color(0.55, 0.85, 0.45)
const BAD := Color(0.95, 0.45, 0.35)
const WARN := Color(0.95, 0.75, 0.25)

var world: World

var _top_tithe: Label
var _top_status: Label
var _build_list: VBoxContainer
var _category: StringName = &"transport"
var _category_buttons: Dictionary = {}
var _stock_labels: Dictionary = {}   # item id -> Label
var _stock_select: OptionButton
var _stock_view: int = -1            # -1 = hive total, else district id
var _inspect_panel: PanelContainer
var _inspect_title: Label
var _inspect_body: Label
var _recipe_select: OptionButton
var _recipe_ids: Array[StringName] = []
var _upgrade_button: Button
var _demolish_button: Button
var _hint: Label
var _log: VBoxContainer
var _selected: BuildingInstance
var _district: int = -1


func setup(p_world: World) -> void:
	world = p_world
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top_bar(root)
	_build_build_menu(root)
	_build_stockpile(root)
	_build_inspector(root)
	_build_hint_and_log(root)
	world.placement.selection_changed.connect(_on_selection_changed)
	world.placement.district_selected.connect(_on_district_selected)
	world.placement.mode_changed.connect(func(_m): refresh())
	world.message_posted.connect(post_message)
	world.districts.changed.connect(_on_districts_changed)
	_on_districts_changed()


func refresh() -> void:
	if world == null:
		return
	_refresh_top()
	_refresh_stockpile()
	_refresh_inspector()
	_refresh_hint()


func post_message(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_child(label)
	while _log.get_child_count() > 6:
		var old := _log.get_child(0)
		_log.remove_child(old)
		old.queue_free()
	var tween := label.create_tween()
	tween.tween_interval(10.0)
	tween.tween_property(label, "modulate:a", 0.0, 2.0)
	tween.tween_callback(label.queue_free)


# --- Layout -------------------------------------------------------------------

func _build_top_bar(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(panel)
	var row := VBoxContainer.new()
	panel.add_child(row)
	_top_tithe = Label.new()
	_top_tithe.add_theme_color_override("font_color", BRASS.lightened(0.3))
	row.add_child(_top_tithe)
	_top_status = Label.new()
	row.add_child(_top_status)


func _build_build_menu(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 64)
	panel.custom_minimum_size = Vector2(260, 440)
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var cats := GridContainer.new()
	cats.columns = 4
	box.add_child(cats)
	for c in CATEGORIES:
		var b := Button.new()
		b.text = c[1]
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 11)
		b.custom_minimum_size = Vector2(60, 0)
		b.pressed.connect(_show_category.bind(c[0]))
		cats.add_child(b)
		_category_buttons[c[0]] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_build_list = VBoxContainer.new()
	_build_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_build_list)
	_show_category(_category)


func _show_category(cat: StringName) -> void:
	_category = cat
	for key in _category_buttons:
		_category_buttons[key].button_pressed = key == cat
	for child in _build_list.get_children():
		_build_list.remove_child(child)
		child.queue_free()
	if cat == &"districts":
		_fill_district_tools()
		return
	if cat == &"transport":
		for net in [TransportGrid.Net.WALK, TransportGrid.Net.ROAD, TransportGrid.Net.RAIL]:
			var tip: String = {
				TransportGrid.Net.WALK: "People only. Workers walk to jobs and citizens to their depot.",
				TransportGrid.Net.ROAD: "Haulers move goods between buildings and the district depot. People can walk on roads too.",
				TransportGrid.Net.RAIL: "Freight trains between cargo stations, across districts. Can cross roads and walkways.",
			}[net]
			_add_tool("%s  (%s / tile)" % [TransportGrid.NET_NAMES[net], _cost_text(TransportGrid.COSTS[net])],
				tip + "\nClick and drag to lay a line.", world.placement.begin_network.bind(net))
		_add_tool("Bulldoze transport", "Drag a rectangle to clear walkways, roads and rail. Half the cost is refunded.",
			world.placement.begin_bulldoze)
	for def in Database.sorted_buildings():
		if def.category != cat or _is_upgrade_target(def):
			continue
		_add_tool(def.display_name, _building_tooltip(def), world.placement.begin_build.bind(def))


func _fill_district_tools() -> void:
	_add_tool("Charter a new district", "Up to %d districts. Each needs its own District Depot." % DistrictMap.MAX_DISTRICTS,
		_on_new_district)
	for d in world.districts.districts:
		var b := _add_tool("Paint %s" % d.name, "Drag a rectangle to add tiles to %s." % d.name,
			world.placement.begin_district_paint.bind(d.id))
		b.add_theme_color_override("font_color", d.colour.lightened(0.2))
	_add_tool("Erase district tiles", "Drag to remove tiles from any district. Tiles under buildings are kept.",
		world.placement.begin_district_paint.bind(-1))
	var note := Label.new()
	note.text = "Tab shows district borders. Click an empty tile to inspect its district."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", TEXT_DIM)
	_build_list.add_child(note)


func _add_tool(text: String, tooltip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = tooltip
	b.pressed.connect(action)
	_build_list.add_child(b)
	return b


func _build_stockpile(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -250
	panel.offset_right = -8
	panel.offset_top = 64
	panel.offset_bottom = 580
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_stock_select = OptionButton.new()
	_stock_select.item_selected.connect(_on_stock_view_selected)
	box.add_child(_stock_select)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 14)
	scroll.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(grid)
	var last_tier := -1
	for def in Database.sorted_items():
		if def.tier != last_tier:
			last_tier = def.tier
			var head := Label.new()
			head.text = ["Raw", "Refined", "Components", "Finished"][def.tier]
			head.add_theme_color_override("font_color", BRASS)
			grid.add_child(head)
			grid.add_child(Control.new())
		var name_label := Label.new()
		name_label.text = def.display_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.tooltip_text = def.description
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(name_label)
		var count := Label.new()
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(count)
		_stock_labels[def.id] = count


func _build_inspector(root: Control) -> void:
	_inspect_panel = PanelContainer.new()
	_inspect_panel.anchor_top = 1.0
	_inspect_panel.anchor_bottom = 1.0
	_inspect_panel.offset_left = 8
	_inspect_panel.offset_right = 400
	_inspect_panel.offset_top = -340
	_inspect_panel.offset_bottom = -8
	_inspect_panel.visible = false
	root.add_child(_inspect_panel)
	var box := VBoxContainer.new()
	_inspect_panel.add_child(box)
	_inspect_title = Label.new()
	_inspect_title.add_theme_color_override("font_color", BRASS.lightened(0.3))
	box.add_child(_inspect_title)
	_recipe_select = OptionButton.new()
	_recipe_select.item_selected.connect(_on_recipe_selected)
	box.add_child(_recipe_select)
	_inspect_body = Label.new()
	_inspect_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspect_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_inspect_body)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_upgrade_button = Button.new()
	_upgrade_button.text = "Upgrade (U)"
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	buttons.add_child(_upgrade_button)
	_demolish_button = Button.new()
	_demolish_button.text = "Demolish (Del)"
	_demolish_button.pressed.connect(_on_demolish_pressed)
	buttons.add_child(_demolish_button)


func _build_hint_and_log(root: Control) -> void:
	_hint = Label.new()
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -330
	_hint.offset_right = 330
	_hint.offset_top = -34
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)
	_log = VBoxContainer.new()
	_log.anchor_left = 1.0
	_log.anchor_right = 1.0
	_log.anchor_top = 1.0
	_log.anchor_bottom = 1.0
	_log.offset_left = -420
	_log.offset_right = -8
	_log.offset_top = -280
	_log.offset_bottom = -44
	_log.alignment = BoxContainer.ALIGNMENT_END
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_log)


# --- Refresh ------------------------------------------------------------------

func _refresh_top() -> void:
	var t := world.tithe
	var e := world.economy
	var parts := []
	for item in t.quota:
		parts.append("%s %d/%d" % [Database.item_name(item), e.district_amount(e.bastion_district, item), int(t.quota[item])])
	_top_tithe.text = "Imperial Tithe %d  ·  due in %s  ·  %s (in Bastion Ward)  ·  Favour %d" % [
		t.cycle, _clock(t.time_left), ",  ".join(parts), int(t.favour)]

	var pops := []
	for caste in Database.sorted_castes():
		var pop := int(e.population.get(caste.id, 0))
		var wanted := int(e.jobs.get(caste.id, 0))
		if pop > 0 or wanted > 0:
			pops.append("%s %d housed, %d/%d jobs" % [caste.display_name, pop,
				int(e.employed.get(caste.id, 0)), wanted])
	var speed_text := "PAUSED" if world.speed == 0.0 else "x%d" % int(world.speed)
	_top_status.text = "%s  ·  Morale %d%%  ·  Haulage %d/s (%d%% used)  ·  %d districts  ·  %s" % [
		"  ·  ".join(pops) if not pops.is_empty() else "No citizens housed",
		int(e.morale * 100.0), int(e.haul_capacity), int(e.haul_load * 100.0),
		world.districts.districts.size(), speed_text]


func _refresh_stockpile() -> void:
	var e := world.economy
	var d := e.district(_stock_view)
	for id in _stock_labels:
		var n := d.amount(id) if d else e.amount(id)
		var label: Label = _stock_labels[id]
		label.text = str(n)
		label.add_theme_color_override("font_color", TEXT if n > 0 else TEXT_DIM)


func _refresh_inspector() -> void:
	if _selected != null and not world.grid.buildings.has(_selected):
		_selected = null
	if _selected:
		_inspect_building(_selected)
	elif _district >= 0 and world.districts.get_district(_district):
		_inspect_district(world.districts.get_district(_district))
	else:
		_inspect_panel.visible = false


func _inspect_building(b: BuildingInstance) -> void:
	_inspect_panel.visible = true
	var d := b.def
	var dist := world.districts.get_district(b.district_id)
	_inspect_title.text = "%s  ·  %s" % [d.display_name, dist.name if dist else "no district"]
	var lines := []
	lines.append(b.status_text())
	if not d.is_housing() and not d.is_module() and not d.is_depot:
		lines.append("Road to depot: %s" % ("yes" if b.road_access else "NO - goods only move through direct links"))
	if d.is_housing():
		var caste := Database.caste(d.housing_caste)
		lines.append("Houses %d %s, %d employed" % [d.housing_capacity, caste.display_name if caste else "",
			int(b.workers_assigned.get(d.housing_caste, 0))])
		if dist:
			lines.append("District needs met %d%%, comforts %d%%" % [
				int(float(dist.basic_satisfaction.get(d.housing_caste, 0.0)) * 100.0),
				int(float(dist.comfort_satisfaction.get(d.housing_caste, 0.0)) * 100.0)])
		if d.upgrade_to != &"":
			var up := Database.building(d.upgrade_to)
			lines.append("Upgrade to %s (%d): %s" % [up.display_name, up.housing_capacity, _cost_text(d.upgrade_cost)])
	if d.is_module():
		lines.append("Attached to: %s" % (b.host.def.display_name if b.host else "nothing"))
		if not d.module_effects.is_empty():
			lines.append("Effects: " + _effects_text(d.module_effects))
		if not d.module_recipes.is_empty():
			var names := []
			for r in d.module_recipes:
				names.append(Database.recipe(r).display_name)
			lines.append("Unlocks: " + ", ".join(names))
		if not d.module_upkeep.is_empty():
			lines.append("Upkeep per minute: " + _amounts_text(d.module_upkeep, "-"))
	if b.recipe:
		var r := b.recipe
		lines.append("Speed %d%%  ·  Condition %d%%  ·  Cycle %d%%" % [
			int(b.last_speed * 100.0), int(b.condition), int(b.progress * 100.0)])
		lines.append("%s  →  %s  (%.1fs)" % [_amounts_text(r.inputs, "nothing"),
			_amounts_text(r.outputs, "service"), r.duration])
		if not b.input_buffer.is_empty():
			lines.append("In: " + _amounts_text(b.input_buffer, "-"))
		if not b.output_buffer.is_empty():
			lines.append("Out: " + _amounts_text(b.output_buffer, "-"))
		if not b.links_out.is_empty():
			var names := []
			for l in b.links_out:
				names.append(l.def.display_name)
			lines.append("Direct link to: " + ", ".join(names))
	if d.module_slots > 0:
		var mods := []
		for m in b.modules:
			mods.append(m.def.display_name + ("" if m.module_active else " (off)"))
		lines.append("Modules %d/%d: %s" % [b.modules.size(), d.module_slots, ", ".join(mods) if not mods.is_empty() else "none"])
	if b.deposit_cluster >= 0:
		var cl := world.deposits.get_cluster(b.deposit_cluster)
		if cl:
			lines.append("Deposit: %d %s left (%d%% coverage)" % [cl.remaining,
				Database.item_name(cl.item), int(b.deposit_coverage * 100.0)])
	var req := Labour.job_requirements(b)
	if not req.is_empty():
		var parts := []
		for c in req:
			parts.append("%d/%d %s" % [int(b.workers_assigned.get(c, 0)), int(req[c]), Database.caste(c).display_name])
		lines.append("Workers: %s (%d%% effective)" % [", ".join(parts), int(b.staffing * 100.0)])
	if d.service_kind != &"":
		lines.append("%s for %d citizens" % [String(d.service_kind).capitalize(), d.service_capacity])
	if d.is_station():
		lines.append("Freight capacity %d/s %s" % [int(d.station_capacity * b.staffing),
			"" if b.road_access else "(needs a road to the depot)"])
	_inspect_body.text = "\n".join(lines)
	_upgrade_button.visible = d.upgrade_to != &""
	_demolish_button.visible = true
	_demolish_button.disabled = d.category == &"core"


func _inspect_district(d: DistrictMap.District) -> void:
	_inspect_panel.visible = true
	_recipe_select.visible = false
	_upgrade_button.visible = false
	_demolish_button.visible = false
	_inspect_title.text = d.name
	_inspect_title.add_theme_color_override("font_color", d.colour.lightened(0.2))
	var lines := []
	lines.append("%d tiles  ·  %d depots  ·  %d stations" % [world.districts.cell_count(d.id), d.depots.size(), d.stations.size()])
	if d.depots.is_empty():
		lines.append("No depot: build a District Depot so this district can hold goods.")
	lines.append("Haulage %d/s, %d%% used" % [int(d.haul_capacity), int(d.haul_load * 100.0)])
	lines.append("Morale %d%%  ·  Fervour covers %d  ·  Order covers %d" % [int(d.morale * 100.0), d.fervour_coverage, d.order_coverage])
	for caste in Database.sorted_castes():
		var pop := int(d.population.get(caste.id, 0))
		var jobs := int(d.jobs.get(caste.id, 0))
		if pop == 0 and jobs == 0:
			continue
		lines.append("%s: %d housed (%d employed), %d jobs here. Needs %d%%, comforts %d%%" % [
			caste.display_name, pop, int(d.employed.get(caste.id, 0)), jobs,
			int(float(d.basic_satisfaction.get(caste.id, 0.0)) * 100.0),
			int(float(d.comfort_satisfaction.get(caste.id, 0.0)) * 100.0)])
	var links := []
	for l in world.economy.freight.links:
		if l.a == d.id or l.b == d.id:
			var other := world.districts.get_district(l.b if l.a == d.id else l.a)
			links.append("%s by %s (%d/s)" % [other.name, "rail" if l.rail else "road", int(l.capacity)])
	lines.append("Freight: " + (", ".join(links) if not links.is_empty() else "no links to other districts"))
	_inspect_body.text = "\n".join(lines)


func _refresh_hint() -> void:
	var p := world.placement
	var text := ""
	var colour := TEXT_DIM
	match p.mode:
		PlacementController.Mode.SELECT:
			text = "WASD pan · wheel zoom · Q/E rotate view · Tab districts · Space pause · 1/2/3 speed"
		PlacementController.Mode.BUILD:
			text = "%s  ·  %s  ·  R rotate · right-click cancel" % [p.build_def.display_name, _cost_text(p.build_def.build_cost)]
			colour = GOOD
			if not p.hover_check.is_empty() and not p.hover_check["ok"]:
				text = "%s  ·  %s" % [p.hover_check["reason"], text]
				colour = BAD
			elif not world.economy.can_afford(p.build_def.build_cost):
				text = "Cannot afford  ·  " + text
				colour = BAD
			elif p.build_def.is_module():
				var host: BuildingInstance = p.hover_check.get("host")
				if host:
					text = "Attaches to %s  ·  %s" % [host.def.display_name, text]
				else:
					text = "No host with a free slot here  ·  " + text
					colour = WARN
			elif p.hover_check.get("cluster", -1) >= 0:
				text = "Covers %d%% of deposit  ·  %s" % [int(p.hover_check["coverage"] * 100.0), text]
		PlacementController.Mode.NETWORK:
			var pv := p.drag_preview
			var n: int = pv.get("ok_tiles", []).size()
			text = "%s  ·  %d tiles  ·  %s  ·  drag to draw, right-click to stop" % [
				TransportGrid.NET_NAMES[p.network], n, _cost_text(pv.get("cost", {}))]
			colour = GOOD if pv.get("reason", "") == "" else (WARN if n > 0 else BAD)
			if pv.get("reason", "") != "":
				text = "%s  ·  %s" % [pv["reason"], text]
		PlacementController.Mode.BULLDOZE:
			text = "Bulldoze  ·  drag over transport to clear it  ·  right-click to stop"
			colour = WARN
		PlacementController.Mode.DISTRICT:
			var d := world.districts.get_district(p.paint_district)
			text = ("Painting %s" % d.name if d else "Erasing district tiles") + "  ·  drag a rectangle  ·  right-click to stop"
			colour = d.colour.lightened(0.2) if d else WARN
	_hint.text = text
	_hint.add_theme_color_override("font_color", colour)


func _on_selection_changed(inst: BuildingInstance) -> void:
	_selected = inst
	if inst:
		_district = -1
	_inspect_title.remove_theme_color_override("font_color")
	_inspect_title.add_theme_color_override("font_color", BRASS.lightened(0.3))
	_recipe_select.clear()
	_recipe_select.visible = false
	_recipe_ids.clear()
	if inst and not inst.def.needs_deposit:
		var available := inst.available_recipes()
		if available.size() > 1:
			_recipe_select.visible = true
			for i in available.size():
				var r := Database.recipe(available[i])
				_recipe_ids.append(available[i])
				_recipe_select.add_item(r.display_name, i)
				if r == inst.recipe:
					_recipe_select.select(i)
	refresh()


func _on_district_selected(id: int) -> void:
	_district = id
	_selected = null
	refresh()


func _on_districts_changed() -> void:
	var keep := _stock_view
	_stock_select.clear()
	_stock_select.add_item("Hive total", 0)
	for d in world.districts.districts:
		_stock_select.add_item(d.name, d.id + 1)
	_stock_select.select(keep + 1 if keep + 1 < _stock_select.item_count else 0)
	if _category == &"districts":
		_show_category(&"districts")


func _on_stock_view_selected(index: int) -> void:
	_stock_view = _stock_select.get_item_id(index) - 1
	refresh()


func _on_new_district() -> void:
	var id := world.new_district()
	if id >= 0:
		world.placement.begin_district_paint(id)


func _on_upgrade_pressed() -> void:
	if _selected:
		world.upgrade(_selected)


func _on_demolish_pressed() -> void:
	if _selected:
		world.demolish(_selected)


func _on_recipe_selected(index: int) -> void:
	if _selected and index < _recipe_ids.size():
		world.set_recipe(_selected, _recipe_ids[index])


# --- Text helpers -------------------------------------------------------------

func _building_tooltip(def: BuildingDef) -> String:
	var lines := [def.display_name]
	if def.description != "":
		lines.append(def.description)
	lines.append("Cost: " + _cost_text(def.build_cost))
	if not def.workers.is_empty():
		lines.append("Workers: " + _castes_text(def.workers))
	if def.is_housing():
		lines.append("Houses %d %s" % [def.housing_capacity, Database.caste(def.housing_caste).display_name])
	if def.module_slots > 0:
		lines.append("Module slots: %d" % def.module_slots)
	if def.is_module():
		var hosts := []
		for h in def.module_hosts:
			var hd := Database.building(h)
			hosts.append(hd.display_name if hd else String(h).capitalize())
		lines.append("Attaches to: " + ", ".join(hosts))
		if not def.module_effects.is_empty():
			lines.append("Effects: " + _effects_text(def.module_effects))
		if not def.module_upkeep.is_empty():
			lines.append("Upkeep per minute: " + _amounts_text(def.module_upkeep, "-"))
		for rid in def.module_recipes:
			var r := Database.recipe(rid)
			lines.append("Unlocks %s: %s → %s" % [r.display_name, _amounts_text(r.inputs, "nothing"),
				_amounts_text(r.outputs, "service")])
	for rid in def.recipes:
		var r := Database.recipe(rid)
		lines.append("%s: %s → %s" % [r.display_name, _amounts_text(r.inputs, "nothing"),
			_amounts_text(r.outputs, "service")])
	return "\n".join(lines)


func _effects_text(effects: Dictionary) -> String:
	var parts := []
	for k in effects:
		parts.append("%s x%s" % [String(k), str(snappedf(float(effects[k]), 0.01))])
	return ", ".join(parts)


func _is_upgrade_target(def: BuildingDef) -> bool:
	for other in Database.buildings.values():
		if other.upgrade_to == def.id:
			return true
	return false


func _amounts_text(d: Dictionary, empty: String) -> String:
	if d.is_empty():
		return empty
	var parts := []
	for item in d:
		var v = d[item]
		var n := str(snappedf(float(v), 0.1)) if v is float and fmod(float(v), 1.0) != 0.0 else str(int(v))
		parts.append("%s %s" % [n, Database.item_name(item)])
	return ", ".join(parts)


func _cost_text(d: Dictionary) -> String:
	return _amounts_text(d, "free")


func _castes_text(d: Dictionary) -> String:
	var parts := []
	for c in d:
		var caste := Database.caste(c)
		parts.append("%d %s" % [int(d[c]), caste.display_name if caste else String(c)])
	return ", ".join(parts)


func _clock(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%d:%02d" % [int(s / 60.0), s % 60]


func _make_theme() -> Theme:
	var theme := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.06, 0.05, 0.9)
	panel.border_color = BRASS.darkened(0.3)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(8)
	panel.set_corner_radius_all(2)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var button := StyleBoxFlat.new()
	button.bg_color = Color(0.14, 0.12, 0.10)
	button.border_color = BRASS.darkened(0.5)
	button.set_border_width_all(1)
	button.set_content_margin_all(5)
	var hover := button.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.18, 0.12)
	hover.border_color = BRASS
	theme.set_stylebox("normal", "Button", button)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", hover)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", BRASS.lightened(0.4))
	theme.set_color("font_pressed_color", "Button", BRASS.lightened(0.5))
	theme.set_default_font_size(14)
	return theme
