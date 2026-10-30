extends SceneTree

var failures: int = 0
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var script = load("res://scripts/save_system/save_store.gd")
	check(script != null, "SaveStore must exist")
	if script == null:
		quit(1)
		return
	var store = script.new("user://test_saves_%d" % Time.get_ticks_usec())
	var state = {"version":1,"day":1,"country_id":"RU","city_id":"ekb","companies":[],"bankrupt":false}
	check(not store.load_game("absent").ok, "Missing slot must report no save")
	check(store.save_game(state, "auto").ok, "Initial write must succeed")
	var loaded = store.load_game("auto")
	check(loaded.ok and loaded.state.day == 1, "Round-trip day")
	state.day = 9
	check(store.save_game(state, "auto").ok, "Second write")
	var main_path: String = store.path_for("auto")
	var f = FileAccess.open(main_path, FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	loaded = store.load_game("auto")
	check(loaded.ok and loaded.recovered and loaded.state.day == 1, "Recover previous valid save from backup")
	check(not store.save_game(state, "../escape").ok, "Reject unsafe slot names")
	check(not store.save_game({"day":-1}, "bad").ok, "Reject malformed state before overwriting")
	check(not store.save_game({"version":{},"day":[],"country_id":"RU","companies":[]},"bad_types").ok,"Reject invalid field types without crashing")
	check(store.write_record("settings", {"theme":"sage","dark":true}).ok, "Write settings")
	check(store.read_record("settings").data.theme == "sage", "Persist theme independently")
	var tampered = FileAccess.open(store.path_for("settings"), FileAccess.WRITE)
	tampered.store_string(JSON.stringify({"format_version":2,"payload":"{}","sha256":"fake"}))
	tampered.close()
	check(not store.read_record("settings").ok, "Reject checksum mismatch")
	var simulation = load("res://scripts/economy/simulation.gd").new()
	simulation.new_game("RU")
	var guarded = script.new("user://test_guarded_%d" % Time.get_ticks_usec())
	guarded.set("game_validator",Callable(simulation,"validate_state"))
	check(guarded.save_game(simulation.state,"auto").ok,"Write a fully validated simulation")
	var corrupt = simulation.state.duplicate(true)
	corrupt.companies[0].stock = -1
	check(not guarded.save_game(corrupt,"auto").ok,"Reject semantically invalid state before overwrite")
	# Emulate an old writer that produced a checksummed but inconsistent primary.
	guarded.save_game(simulation.state,"auto")
	guarded.write_record("auto",corrupt)
	var recovered = guarded.load_game("auto")
	check(recovered.ok and recovered.recovered,"Try backup after semantic validation rejects primary")
	if recovered.ok:
		check(simulation.validate_state(recovered.state).is_empty(),"Recovered state passes journal replay")
	print("SAVE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
