extends Node3D
## Native, deterministic city diorama. Static details are instanced by material;
## financial state is supplied by the simulation, never computed by this scene.

signal plot_selected(plot_id: int)

const PLOT_SIDE := 6.2
const MAP_LIMIT := 17.5
const DEFAULT_ZOOM := 47.0
const DEFAULT_YAW := 0.72
const CAMERA_PITCH := 0.79

var selected_plot: int = -1
var input_enabled := true
var camera_zoom_target := DEFAULT_ZOOM
var camera_yaw_target := DEFAULT_YAW
var camera_target := Vector3.ZERO

var _camera: Camera3D
var _camera_yaw := DEFAULT_YAW
var _camera_zoom := DEFAULT_ZOOM
var _camera_center := Vector3.ZERO
var _selection: Node3D
var _businesses: Node3D
var _plots: Node3D
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _tree_transforms: Array[Transform3D] = []
var _cars: Array[Dictionary] = []
var _touches: Dictionary = {}
var _touch_generations: Dictionary = {}
var _mouse_generations: Dictionary = {}
var _gesture_serial := 0
var _touch_start := Vector2.ZERO
var _touch_moved := false
var _had_multitouch := false
var _mouse_down := false
var _mouse_rotate := false
var _mouse_start := Vector2.ZERO
var _mouse_moved := false
var _pan_velocity := Vector3.ZERO
var _elapsed := 0.0

func _ready() -> void:
	_make_materials()
	_make_environment()
	_build_roads_and_land()
	_build_plots()
	_build_neighborhood()
	_flush_batches()
	_make_selection()
	_businesses = Node3D.new()
	_businesses.name = "Businesses"
	add_child(_businesses)
	_build_cars()
	_camera = Camera3D.new()
	_camera.name = "CityCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.size = DEFAULT_ZOOM
	_camera.near = 0.1
	_camera.far = 160.0
	_camera.current = true
	add_child(_camera)
	_update_camera(1.0)

func _make_materials() -> void:
	var palette := {
		"ground": "c5d4b6", "grass": "9cb995", "grass_dark": "7f9d7f",
		"asphalt": "65717a", "paving": "d9ddd7", "line": "e6e8da",
		"cream": "ede5d2", "rose": "ce9e8e", "blue": "93aeb8",
		"sage": "99b5a4", "roof": "596a6b", "roof_light": "87958e",
		"glass": "527783", "glass_light": "b5d0ce", "white": "f4f1e7",
		"yellow": "efc66e", "brick": "b47f68", "dark": "42555c",
		"wood": "9c8066", "water": "85b6c2", "water_light": "b6d2d1",
		"leaf": "6d9c7d", "leaf_light": "8eaf80", "player": "e8bf68",
		"ai": "769da8", "border": "b7c5b2", "flower": "d5b7a7",
		"residential": "d1d8bb", "retail": "d8d2bd", "industrial": "c7d0cb",
		"business": "c3d1cf"
	}
	for key in palette:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(palette[key])
		mat.roughness = 0.85
		_materials[key] = mat
	var selection_material := StandardMaterial3D.new()
	selection_material.albedo_color = Color("ffe2a0")
	selection_material.emission_enabled = true
	selection_material.emission = Color("efc56a")
	selection_material.emission_energy_multiplier = 0.32
	_materials["selection"] = selection_material

func _make_environment() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("dce6e4")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e1e7ed")
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-51.0, -34.0, 0.0)
	sun.light_color = Color("fff1d5")
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.08
	add_child(sun)

func _build_roads_and_land() -> void:
	# Finite raised island, embankment and river. No unbounded empty world.
	_box(Vector3(0, -0.65, -1), Vector3(47, 1.1, 48), "border")
	_box(Vector3(-1.7, -0.04, -1), Vector3(43.5, 0.2, 47), "ground")
	_box(Vector3(22.1, 0.04, -1), Vector3(3.8, 0.18, 47.5), "water")
	_box(Vector3(19.95, 0.16, -1), Vector3(0.5, 0.34, 47.5), "paving")
	for k in range(15):
		_box(Vector3(22.0 + (k % 2) * 0.6, 0.145, -22.0 + k * 3.0), Vector3(1.0, 0.015, 0.045), "water_light")
	for coordinate in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		_box(Vector3(coordinate, 0.04, 0), Vector3(2.25, 0.15, 35.0), "paving")
		_box(Vector3(0, 0.045, coordinate), Vector3(35.0, 0.15, 2.25), "paving")
		_box(Vector3(coordinate, 0.13, 0), Vector3(1.65, 0.025, 35.0), "asphalt")
		_box(Vector3(0, 0.135, coordinate), Vector3(35.0, 0.025, 1.65), "asphalt")
		for mark in range(-17, 18):
			if abs(mark) % 8 <= 1:
				continue
			_box(Vector3(coordinate, 0.155, float(mark)), Vector3(0.055, 0.012, 0.43), "line")
			_box(Vector3(float(mark), 0.16, coordinate), Vector3(0.43, 0.012, 0.055), "line")
	# Human-scale zebra crossings and street lamps at the four central junctions.
	for x in [-8.0, 0.0, 8.0]:
		for z in [-8.0, 0.0, 8.0]:
			for stripe in range(5):
				_box(Vector3(x - 0.57 + stripe * 0.28, 0.17, z + 1.32), Vector3(0.15, 0.018, 0.5), "white")
			_box(Vector3(x + 1.18, 1.18, z - 1.18), Vector3(0.07, 2.05, 0.07), "dark")
			_box(Vector3(x + 1.04, 2.2, z - 1.18), Vector3(0.42, 0.09, 0.18), "cream")
	# A fence makes the playable boundary unmistakable without blocking the view.
	for side in [-1.0, 1.0]:
		_box(Vector3(0, 0.34, side * 17.85), Vector3(36.0, 0.12, 0.1), "white")
		_box(Vector3(side * 17.85, 0.34, 0), Vector3(0.1, 0.12, 36.0), "white")
		for n in range(-18, 19, 2):
			_box(Vector3(float(n), 0.24, side * 17.85), Vector3(0.1, 0.55, 0.1), "white")
			_box(Vector3(side * 17.85, 0.24, float(n)), Vector3(0.1, 0.55, 0.1), "white")

func _build_plots() -> void:
	_plots = Node3D.new()
	_plots.name = "Plots"
	add_child(_plots)
	var districts := ["business", "retail", "residential", "industrial"]
	for id in range(16):
		var position_3d := _plot_position(id)
		var body := StaticBody3D.new()
		body.name = "Plot%d" % id
		body.position = position_3d
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("plot_id", id)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(PLOT_SIDE, 0.3, PLOT_SIDE)
		collision.shape = shape
		collision.position.y = 0.1
		body.add_child(collision)
		_plots.add_child(body)
		_box(position_3d + Vector3(0, 0.075, 0), Vector3(6.1, 0.15, 6.1), districts[int(id / 4)])
		_box(position_3d + Vector3(0, 0.16, 0), Vector3(4.8, 0.06, 4.8), "paving")
		# The small cadastral plaque remains visible in front of any enterprise.
		_box(position_3d + Vector3(0, 0.23, 2.66), Vector3(1.05, 0.16, 0.46), "cream")
		var number := Label3D.new()
		number.text = "%02d" % (id + 1)
		number.font_size = 42
		number.pixel_size = 0.012
		number.modulate = Color("3e5556")
		number.outline_size = 0
		number.position = position_3d + Vector3(0, 0.325, 2.67)
		number.rotation_degrees.x = -90.0
		add_child(number)
		_tree(position_3d + Vector3(-2.6, 0.18, -2.5), 0.83)
		if id % 3 == 0:
			_tree(position_3d + Vector3(2.55, 0.18, -2.5), 0.72)

func _build_neighborhood() -> void:
	# Skyline outside the playable plots makes every district immediately legible.
	var skyline := [3.8, 5.4, 7.7, 4.9, 8.6, 6.1, 4.2, 3.4]
	for i in range(8):
		var center := Vector3(-20.0 + i * 5.3, 0.12, -21.2)
		_static_tower(center, Vector3(3.2, skyline[i], 3.3), ["cream", "blue", "sage", "rose"][i % 4])
	for i in range(6):
		var center := Vector3(-21.0, 0.12, -13.0 + i * 5.5)
		if i < 3:
			_static_tower(center, Vector3(2.7, 3.8 + i * 0.8, 3.0), "cream" if i % 2 == 0 else "rose")
		else:
			_tree(center + Vector3(-0.6, 0, 0), 1.2)
			_tree(center + Vector3(0.7, 0, 1.4), 1.0)
	# South park: curved-looking planted pockets, seating and a little fountain.
	_box(Vector3(0, 0.1, 21), Vector3(34, 0.16, 5.3), "grass")
	_box(Vector3(0, 0.2, 20), Vector3(34, 0.08, 0.85), "paving")
	for i in range(11):
		var x := -16.0 + i * 3.2
		_tree(Vector3(x, 0.2, 22.1), 1.0 if i % 2 else 1.15)
		if i % 2 == 0:
			_box(Vector3(x, 0.51, 20.9), Vector3(1.15, 0.12, 0.35), "wood")
			_box(Vector3(x, 0.72, 21.07), Vector3(1.15, 0.36, 0.09), "wood")
			_box(Vector3(x - 0.37, 0.34, 20.9), Vector3(0.09, 0.3, 0.3), "dark")
			_box(Vector3(x + 0.37, 0.34, 20.9), Vector3(0.09, 0.3, 0.3), "dark")
	# Embankment avenue with flower planters.
	_box(Vector3(18.85, 0.15, 0), Vector3(1.2, 0.14, 35), "paving")
	for z in range(-14, 16, 4):
		_box(Vector3(19, 0.38, z), Vector3(0.52, 0.35, 0.7), "cream")
		_box(Vector3(19, 0.6, z), Vector3(0.55, 0.18, 0.7), "flower")

func _static_tower(center: Vector3, dimensions: Vector3, palette: String) -> void:
	_box(center + Vector3(0, dimensions.y / 2, 0), dimensions, palette)
	_box(center + Vector3(0, dimensions.y + 0.08, 0), Vector3(dimensions.x + 0.12, 0.2, dimensions.z + 0.12), "roof")
	_box(center + Vector3(0.4, dimensions.y + 0.36, 0.2), Vector3(0.9, 0.4, 0.8), "roof_light")
	for floor_index in range(1, int(dimensions.y)):
		for column in range(3):
			var x := -dimensions.x * 0.31 + column * dimensions.x * 0.31
			_box(center + Vector3(x, float(floor_index) + 0.12, dimensions.z / 2 + 0.014), Vector3(0.46, 0.52, 0.03), "glass")
			_box(center + Vector3(dimensions.x / 2 + 0.014, float(floor_index) + 0.12, x), Vector3(0.03, 0.52, 0.46), "glass_light")

func _tree(base: Vector3, size_factor: float) -> void:
	_box(base + Vector3(0, 0.63 * size_factor, 0), Vector3(0.14, 1.25, 0.14) * size_factor, "wood")
	var transform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size_factor), base + Vector3(0, 1.7 * size_factor, 0))
	_tree_transforms.append(transform)

func _box(center: Vector3, dimensions: Vector3, palette: String) -> void:
	if not _batches.has(palette):
		_batches[palette] = []
	_batches[palette].append(Transform3D(Basis.IDENTITY.scaled(dimensions), center))

func _flush_batches() -> void:
	var batch_root := Node3D.new()
	batch_root.name = "StaticCity"
	add_child(batch_root)
	for palette in _batches:
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		_create_multimesh(mesh, _batches[palette], _materials[palette], batch_root)
	var tree_mesh := CylinderMesh.new()
	tree_mesh.top_radius = 0.18
	tree_mesh.bottom_radius = 0.85
	tree_mesh.height = 2.0
	tree_mesh.radial_segments = 6
	_create_multimesh(tree_mesh, _tree_transforms, _materials["leaf"], batch_root)
	_batches.clear()

func _create_multimesh(mesh: Mesh, transforms: Array, material: Material, parent: Node3D) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index in range(transforms.size()):
		multi.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.material_override = material
	parent.add_child(node)

func _make_selection() -> void:
	_selection = Node3D.new()
	_selection.name = "Selection"
	_selection.visible = false
	add_child(_selection)
	for side in [-1.0, 1.0]:
		_dynamic_box(_selection, Vector3(0, 0.32, side * 3.05), Vector3(6.2, 0.11, 0.11), "selection")
		_dynamic_box(_selection, Vector3(side * 3.05, 0.32, 0), Vector3(0.11, 0.11, 6.2), "selection")
	for x in [-3.05, 3.05]:
		for z in [-3.05, 3.05]:
			_dynamic_box(_selection, Vector3(x, 0.57, z), Vector3(0.15, 0.55, 0.15), "selection")

func sync_state(companies: Array, properties: Array = []) -> void:
	if not is_instance_valid(_businesses):
		return
	for child in _businesses.get_children():
		_businesses.remove_child(child)
		child.queue_free()
	var occupied: Dictionary = {}
	for company in companies:
		if not company is Dictionary:
			continue
		var plot_id := int(company.get("plot_id", -1))
		if plot_id < 0 or plot_id >= 16 or occupied.has(plot_id):
			continue
		if company.get("status", "active") == "closed":
			continue
		occupied[plot_id] = true
		_build_business(company, plot_id)
	# Unoccupied purchased properties carry a yellow ownership marker.
	for property in properties:
		var plot_id := int(property.get("plot_id", -1)) if property is Dictionary else int(property)
		if plot_id < 0 or plot_id >= 16 or occupied.has(plot_id):
			continue
		var marker := Node3D.new()
		marker.name = "Property%d" % plot_id
		marker.position = _plot_position(plot_id)
		_businesses.add_child(marker)
		_dynamic_box(marker, Vector3(0, 0.27, 0), Vector3(4.65, 0.16, 4.65), "player")
		_dynamic_box(marker, Vector3(0, 1.0, 0), Vector3(0.08, 1.5, 0.08), "dark")
		_dynamic_box(marker, Vector3(0.38, 1.5, 0), Vector3(0.75, 0.5, 0.04), "player")

func _build_business(company: Dictionary, plot_id: int) -> void:
	var building := Node3D.new()
	building.name = "Business%d" % plot_id
	building.position = _plot_position(plot_id)
	building.set_meta("company_id", str(company.get("id", "")))
	_businesses.add_child(building)
	var is_player := str(company.get("owner", "ai")) == "player"
	var accent := "player" if is_player else "ai"
	var kind := str(company.get("type", "shop"))
	var body := StaticBody3D.new()
	body.name = "BuildingCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("plot_id", plot_id)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.8, 4.4, 3.6) if kind == "studio" else (Vector3(3.6, 2.1, 3.0) if kind == "cafe" else Vector3(4.45, 2.25, 3.9))
	collision.shape = shape
	collision.position = Vector3(0, 2.35, -0.15) if kind == "studio" else (Vector3(-0.45, 1.21, -0.4) if kind == "cafe" else Vector3(0, 1.3, -0.2))
	body.add_child(collision)
	building.add_child(body)
	if kind == "studio":
		_dynamic_box(building, Vector3(0, 2.35, -0.15), Vector3(3.8, 4.4, 3.6), "cream")
		_dynamic_box(building, Vector3(0, 4.63, -0.15), Vector3(4.05, 0.22, 3.85), accent)
		_dynamic_box(building, Vector3(0.65, 4.95, -0.6), Vector3(1.2, 0.5, 0.8), "roof_light")
		for level in range(3):
			_dynamic_box(building, Vector3(0, 1.1 + level * 1.22, 1.67), Vector3(3.25, 0.76, 0.05), "glass")
			_dynamic_box(building, Vector3(1.925, 1.1 + level * 1.22, -0.15), Vector3(0.05, 0.76, 2.95), "glass_light")
			for mullion in [-1.0, 0.0, 1.0]:
				_dynamic_box(building, Vector3(mullion, 1.1 + level * 1.22, 1.71), Vector3(0.055, 0.78, 0.05), "cream")
	elif kind == "cafe":
		_dynamic_box(building, Vector3(-0.45, 1.21, -0.4), Vector3(3.6, 2.1, 3.0), "rose")
		_dynamic_box(building, Vector3(-0.45, 2.35, -0.4), Vector3(3.95, 0.22, 3.35), "roof")
		_dynamic_box(building, Vector3(-0.45, 1.3, 1.13), Vector3(3.0, 1.3, 0.05), "glass")
		_dynamic_box(building, Vector3(-0.45, 2.02, 1.5), Vector3(3.8, 0.13, 0.9), accent)
		for stripe in range(6):
			_dynamic_box(building, Vector3(-1.95 + stripe * 0.6, 2.1, 1.5), Vector3(0.28, 0.03, 0.9), "cream")
		for terrace_z in [-0.55, 1.05]:
			_dynamic_box(building, Vector3(2.0, 0.86, terrace_z), Vector3(0.85, 0.1, 0.85), "wood")
			_dynamic_box(building, Vector3(2.0, 0.52, terrace_z), Vector3(0.1, 0.7, 0.1), "dark")
			_dynamic_box(building, Vector3(2.0, 1.7, terrace_z), Vector3(0.05, 1.8, 0.05), "wood")
			_dynamic_box(building, Vector3(2.0, 2.42, terrace_z), Vector3(1.35, 0.08, 1.35), "cream")
		_dynamic_box(building, Vector3(-0.7, 2.75, -0.3), Vector3(0.4, 0.8, 0.4), "brick")
	else:
		_dynamic_box(building, Vector3(0, 1.3, -0.2), Vector3(4.45, 2.25, 3.9), "cream")
		_dynamic_box(building, Vector3(0, 2.53, -0.2), Vector3(4.75, 0.24, 4.15), "roof")
		_dynamic_box(building, Vector3(0, 2.18, 1.81), Vector3(4.5, 0.47, 0.18), accent)
		_dynamic_box(building, Vector3(-1.0, 1.19, 1.77), Vector3(1.65, 1.3, 0.06), "glass_light")
		_dynamic_box(building, Vector3(0.55, 1.09, 1.8), Vector3(0.85, 1.8, 0.08), "glass")
		_dynamic_box(building, Vector3(1.6, 1.19, 1.77), Vector3(0.75, 1.3, 0.06), "glass_light")
		_dynamic_box(building, Vector3(-1.0, 2.9, -0.8), Vector3(1.1, 0.5, 0.85), "roof_light")
		_dynamic_box(building, Vector3(1.4, 2.74, -0.9), Vector3(0.8, 0.25, 0.8), "roof_light")
	# Colored freestanding pylon is readable even when viewing a rear facade.
	_dynamic_box(building, Vector3(-2.55, 0.88, 2.25), Vector3(0.08, 1.5, 0.08), "dark")
	_dynamic_box(building, Vector3(-2.55, 1.6, 2.25), Vector3(0.7, 0.6, 0.12), accent)
	var label := Label3D.new()
	label.text = str(company.get("name", {"cafe": "КАФЕ", "shop": "МАРКЕТ", "studio": "IT-СТУДИЯ"}.get(kind, "БИЗНЕС")))
	if label.text.length() > 22:
		label.text = label.text.substr(0, 20) + "…"
	label.font_size = 38
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("293f43")
	label.outline_size = 7
	label.outline_modulate = Color("f4f0e6")
	label.position = Vector3(0, 5.35 if kind == "studio" else 3.38, -0.1)
	building.add_child(label)

func _dynamic_box(parent: Node3D, center: Vector3, dimensions: Vector3, palette: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = center
	node.material_override = _materials[palette]
	parent.add_child(node)
	return node

func _build_cars() -> void:
	var car_root := Node3D.new()
	car_root.name = "Traffic"
	add_child(car_root)
	for i in range(6):
		var car := Node3D.new()
		car_root.add_child(car)
		_dynamic_box(car, Vector3(0, 0.4, 0), Vector3(0.6, 0.3, 1.05), ["cream", "rose", "blue", "yellow"][i % 4])
		_dynamic_box(car, Vector3(0, 0.62, -0.05), Vector3(0.48, 0.22, 0.55), "glass")
		_dynamic_box(car, Vector3(0, 0.25, 0), Vector3(0.63, 0.16, 0.7), "dark")
		_cars.append({"node": car, "phase": i * 18.5, "speed": 1.0 + (i % 3) * 0.25})

func _process(delta: float) -> void:
	_elapsed += delta
	if _touches.is_empty() and not _mouse_down:
		camera_target += _pan_velocity * delta
		_pan_velocity = _pan_velocity.lerp(Vector3.ZERO, 1.0 - exp(-delta * 6.0))
	camera_target.x = clampf(camera_target.x, -MAP_LIMIT, MAP_LIMIT)
	camera_target.z = clampf(camera_target.z, -MAP_LIMIT, MAP_LIMIT)
	_update_camera(1.0 - exp(-delta * 11.0))
	if is_instance_valid(_selection) and _selection.visible:
		_selection.position.y = sin(_elapsed * 3.0) * 0.025
	for vehicle in _cars:
		var progress := fmod(float(vehicle["phase"]) + _elapsed * float(vehicle["speed"]), 128.0)
		var node: Node3D = vehicle["node"]
		if progress < 32.0:
			node.position = Vector3(-15.62, 0, -16.0 + progress)
			node.rotation.y = 0
		elif progress < 64.0:
			node.position = Vector3(-16.0 + progress - 32.0, 0, 15.62)
			node.rotation.y = PI / 2
		elif progress < 96.0:
			node.position = Vector3(15.62, 0, 16.0 - progress + 64.0)
			node.rotation.y = PI
		else:
			node.position = Vector3(16.0 - progress + 96.0, 0, -15.62)
			node.rotation.y = -PI / 2

func _update_camera(weight: float) -> void:
	if not is_instance_valid(_camera):
		return
	_camera_center = _camera_center.lerp(camera_target, weight)
	_camera_yaw = lerp_angle(_camera_yaw, camera_yaw_target, weight)
	_camera_zoom = lerpf(_camera_zoom, camera_zoom_target, weight)
	_camera.size = _camera_zoom
	var direction := Vector3(sin(_camera_yaw) * cos(CAMERA_PITCH), sin(CAMERA_PITCH), cos(_camera_yaw) * cos(CAMERA_PITCH))
	_camera.position = _camera_center + direction * 57.0
	_camera.look_at(_camera_center, Vector3.UP)

func focus_plot(plot_id: int) -> void:
	if plot_id < 0 or plot_id >= 16:
		return
	selected_plot = plot_id
	_selection.position = _plot_position(plot_id)
	_selection.visible = true
	camera_target = _plot_position(plot_id) * 0.4

func set_camera_action(action: String) -> void:
	match action:
		"zoom_in":
			camera_zoom_target = clampf(camera_zoom_target * 0.85, 20.0, 70.0)
		"zoom_out":
			camera_zoom_target = clampf(camera_zoom_target / 0.85, 20.0, 70.0)
		"rotate_left":
			camera_yaw_target -= PI / 8.0
		"rotate_right":
			camera_yaw_target += PI / 8.0
		"reset":
			camera_zoom_target = DEFAULT_ZOOM
			camera_yaw_target = DEFAULT_YAW
			camera_target = Vector3.ZERO
			_pan_velocity = Vector3.ZERO

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		_touches.clear()
		_mouse_down = false
		_mouse_rotate = false
		_pan_velocity = Vector3.ZERO

func _plot_position(plot_id: int) -> Vector3:
	return Vector3(-12.0 + (plot_id % 4) * 8.0, 0.0, -12.0 + int(plot_id / 4) * 8.0)

func _input(event: InputEvent) -> void:
	# GUI controls may consume a release after a drag begins on the map. Cleanup
	# after GUI dispatch; unhandled releases still get their normal tap handling.
	# Generation guards preserve a new gesture that starts during the same frame.
	if event is InputEventScreenTouch:
		if event.pressed:
			_gesture_serial += 1
			_touch_generations[event.index] = _gesture_serial
		else:
			_release_touch.call_deferred(event.index, int(_touch_generations.get(event.index, -1)))
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if event.pressed:
			_gesture_serial += 1
			_mouse_generations[event.button_index] = _gesture_serial
		else:
			_release_mouse.call_deferred(event.button_index, int(_mouse_generations.get(event.button_index, -1)))

func _release_touch(index: int, generation: int) -> void:
	if int(_touch_generations.get(index, -1)) == generation:
		_touches.erase(index)
		_touch_generations.erase(index)

func _release_mouse(button: int, generation: int) -> void:
	if int(_mouse_generations.get(button, -1)) == generation:
		if button == MOUSE_BUTTON_LEFT:
			_mouse_down = false
		else:
			_mouse_rotate = false
		_mouse_generations.erase(button)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not is_instance_valid(_camera):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touches.is_empty():
				_touch_start = event.position
				_touch_moved = false
				_had_multitouch = false
				_pan_velocity = Vector3.ZERO
			_touches[event.index] = event.position
			if _touches.size() > 1:
				_had_multitouch = true
		else:
			if _touches.has(event.index) and _touches.size() == 1 and not _touch_moved and not _had_multitouch:
				_pick(event.position)
			_touches.erase(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		if event.position.distance_to(_touch_start) > 12.0:
			_touch_moved = true
		if _touches.size() >= 2:
			var ids := _touches.keys()
			var first: Vector2 = _touches[ids[0]]
			var second: Vector2 = _touches[ids[1]]
			var before := second - first
			_touches[event.index] = event.position
			var after: Vector2 = _touches[ids[1]] - _touches[ids[0]]
			if before.length() > 12.0 and after.length() > 12.0:
				camera_zoom_target = clampf(camera_zoom_target * before.length() / after.length(), 20.0, 70.0)
				camera_yaw_target -= before.angle_to(after)
			_pan_screen(event.relative * 0.5, false)
		else:
			_touches[event.index] = event.position
			_pan_screen(event.relative, true)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		# Android may synthesize mouse events from touch; avoid processing twice.
		if not _touches.is_empty() or event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			set_camera_action("zoom_in")
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			set_camera_action("zoom_out")
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_mouse_down = event.pressed
			if event.pressed:
				_mouse_start = event.position
				_mouse_moved = false
				_pan_velocity = Vector3.ZERO
			elif not _mouse_moved:
				_pick(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_rotate = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _mouse_rotate:
			camera_yaw_target -= event.relative.x * 0.008
		elif _mouse_down:
			if event.position.distance_to(_mouse_start) > 8.0:
				_mouse_moved = true
			if _mouse_moved:
				_pan_screen(event.relative, true)
	elif event is InputEventMagnifyGesture:
		camera_zoom_target = clampf(camera_zoom_target / maxf(event.factor, 0.1), 20.0, 70.0)
	elif event is InputEventPanGesture:
		_pan_screen(event.delta * 12.0, false)

func _pan_screen(relative: Vector2, inertia: bool) -> void:
	var height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var factor := camera_zoom_target / height
	var right := Vector3(cos(_camera_yaw), 0, -sin(_camera_yaw))
	var screen_down := Vector3(sin(_camera_yaw), 0, cos(_camera_yaw))
	var motion := -right * relative.x * factor - screen_down * relative.y * factor / sin(CAMERA_PITCH)
	camera_target += motion
	if inertia:
		_pan_velocity = motion * 15.0

func _pick(screen_position: Vector2) -> void:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 150.0, 1)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.has("collider") and result["collider"].has_meta("plot_id"):
		var plot_id := int(result["collider"].get_meta("plot_id"))
		focus_plot(plot_id)
		plot_selected.emit(plot_id)
