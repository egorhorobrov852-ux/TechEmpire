extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var packed = load("res://scenes/city/city.tscn")
	check(packed != null, "Native city scene exists")
	if packed == null:
		quit(1)
		return
	var city = packed.instantiate()
	root.add_child(city)
	await process_frame
	check(city is Node3D, "City is a native 3D scene")
	check(city.get_node_or_null("CityCamera") is Camera3D, "3D camera exists")
	check(city.get_node("Plots").get_child_count() == 16, "Exactly sixteen playable plots")
	for id in range(16):
		var plot = city.get_node("Plots/Plot%d" % id)
		var expected = Vector3(-12.0 + (id % 4) * 8.0, 0.0, -12.0 + int(id / 4) * 8.0)
		check(plot.position.is_equal_approx(expected), "Plot %d coordinates" % id)
		check(plot is StaticBody3D and plot.get_child(0) is CollisionShape3D, "Plot %d is selectable by ray" % id)
		check(plot.get_child(0).shape.size.y <= 0.5, "Empty plot %d has no invisible tall collision volume" % id)
	city.sync_state([
		{"id": "p1", "owner": "player", "type": "cafe", "plot_id": 1, "name": "Кофейня"},
		{"id": "c1", "owner": "ai", "type": "shop", "plot_id": 6, "name": "Конкурент"},
		{"id": "p2", "owner": "player", "type": "studio", "plot_id": 11, "name": "Студия"}
	])
	check(city.get_node("Businesses").get_child_count() == 3, "Businesses appear on map")
	check(city.get_node("StaticCity").get_child_count() <= 32, "Static details use material batches")
	var selection_events: Array = []
	city.plot_selected.connect(func(plot_id): selection_events.append(plot_id))
	await physics_frame
	var camera: Camera3D = city.get_node("CityCamera")
	var empty_plot_screen := camera.unproject_position(Vector3(12, 0.25, 12))
	city._pick(empty_plot_screen)
	check(city.selected_plot == 15, "Physics ray selects the visible ground plot")
	check(selection_events == [15], "A user ray selection emits exactly one selection event")
	city._pick(camera.unproject_position(Vector3(12, 4.4, 4)))
	check(city.selected_plot == 11, "Physics ray selects an occupied building")
	selection_events.clear()
	city.focus_plot(11)
	check(city.selected_plot == 11, "Focus selects the requested plot")
	check(selection_events.is_empty(), "Programmatic focus never reemits user selection")
	check(city.get_node("Selection").visible, "Selected plot highlighted")
	city.focus_plot(50)
	check(city.selected_plot == 11, "Out of bounds focus rejected")
	for i in range(100):
		city.set_camera_action("zoom_in")
	check(city.camera_zoom_target >= 18.0, "Zoom in bounded")
	for i in range(100):
		city.set_camera_action("zoom_out")
	check(city.camera_zoom_target <= 75.0, "Zoom out bounded")
	city.set_camera_action("rotate_left")
	city.set_camera_action("reset")
	check(is_equal_approx(city.camera_zoom_target, 47.0), "Camera reset restores zoom")
	city.set_input_enabled(false)
	check(not city.input_enabled, "UI modal can lock camera input")
	city.set_input_enabled(true)
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = Vector2(100, 100)
	city._unhandled_input(press)
	check(city._touches.has(0), "Touch starts a camera gesture")
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = Vector2(110, 100)
	if city.has_method("_input"):
		city._input(release)
	await process_frame
	check(city._touches.is_empty(), "Touch released over UI cannot leave a stuck camera gesture")
	var first := InputEventScreenTouch.new()
	first.index = 0
	first.pressed = true
	first.position = Vector2(100, 100)
	city._unhandled_input(first)
	var second := InputEventScreenTouch.new()
	second.index = 1
	second.pressed = true
	second.position = Vector2(200, 100)
	city._unhandled_input(second)
	var pinch := InputEventScreenDrag.new()
	pinch.index = 1
	pinch.position = Vector2(300, 100)
	pinch.relative = Vector2(100, 0)
	city._unhandled_input(pinch)
	check(city.camera_zoom_target < 47.0, "Two-finger spread zooms into the city")
	var rotate := InputEventScreenDrag.new()
	rotate.index = 1
	rotate.position = Vector2(200, 200)
	rotate.relative = Vector2(-100, 100)
	var initial_angle: float = city.camera_yaw_target
	city._unhandled_input(rotate)
	check(not is_equal_approx(city.camera_yaw_target, initial_angle), "Two-finger rotation turns camera")
	city.set_input_enabled(false)
	city.set_input_enabled(true)
	city.sync_state([])
	check(city.get_node("Businesses").get_child_count() == 0, "Closed businesses removed from map")
	city.queue_free()
	await process_frame
	print("CITY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
