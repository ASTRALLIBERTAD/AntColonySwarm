extends Node
class_name SaveLoadSystem

const SAVE_DIR = "user://swarm_saves/"
const SAVE_EXTENSION = ".swarm"

static func vector2_to_dict(vec: Vector2) -> Dictionary:
	return {"x": vec.x, "y": vec.y}

static func dict_to_vector2(dict: Dictionary) -> Vector2:
	return Vector2(dict.get("x", 0), dict.get("y", 0))

static func convert_memory_positions(memory_array: Array) -> Array:
	var converted = []
	for entry in memory_array:
		if entry is Dictionary and entry.has("pos"):
			var converted_entry = entry.duplicate()
			if entry["pos"] is Dictionary:
				converted_entry["pos"] = dict_to_vector2(entry["pos"])
			converted.append(converted_entry)
		else:
			converted.append(entry)
	return converted

static func ensure_save_directory():
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)

static func save_simulation(main_node: Node2D, save_name: String) -> bool:
	ensure_save_directory()
	
	var save_data = {
		"version": "1.0",
		"timestamp": Time.get_datetime_string_from_system(),
		"simulation_time": main_node.simulation_time,
		"total_food_collected": main_node.total_food_collected,
		"ants": [],
		"pheromones": {},
		"nest": {}
	}
	
	# Safely serialize ants
	for ant in main_node.ants:
		if not is_instance_valid(ant):
			continue
		var ant_data = serialize_ant(ant)
		if ant_data:
			save_data["ants"].append(ant_data)
	
	# Serialize pheromones and nest
	save_data["pheromones"] = serialize_pheromones(main_node.pheromone_map)
	save_data["nest"] = serialize_nest(main_node.nest)
	
	# Convert to JSON string
	var json_string = JSON.stringify(save_data, "\t")
	
	# Validate JSON before saving
	var test_json = JSON.new()
	if test_json.parse(json_string) != OK:
		push_error("Generated invalid JSON - save aborted")
		return false
	
	var save_path = SAVE_DIR + save_name + SAVE_EXTENSION
	
	# Backup existing file if it exists
	if FileAccess.file_exists(save_path):
		var backup_path = save_path + ".backup"
		DirAccess.copy_absolute(save_path, backup_path)
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open save file for writing: " + save_path)
		return false
	
	file.store_string(json_string)
	file.close()
	
	# Verify the file was written correctly
	var verify_file = FileAccess.open(save_path, FileAccess.READ)
	if not verify_file:
		push_error("Failed to verify saved file")
		return false
	
	var verify_string = verify_file.get_as_text()
	verify_file.close()
	
	if verify_string.length() == 0:
		push_error("Saved file is empty - corruption detected")
		return false
	
	print("✓ Simulation saved to: " + save_path)
	print("  - Ants: %d" % save_data["ants"].size())
	print("  - Time: %.1fs" % save_data["simulation_time"])
	
	return true

static func load_simulation(main_node: Node2D, save_name: String) -> bool:
	var save_path = SAVE_DIR + save_name + SAVE_EXTENSION
	
	if not FileAccess.file_exists(save_path):
		push_error("Save file not found: " + save_path)
		return false
	
	var file = FileAccess.open(save_path, FileAccess.READ)
	if not file:
		push_error("Failed to open save file: " + save_path)
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	# Check if file is empty
	if json_string.length() == 0:
		push_error("Save file is empty")
		return false
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("Failed to parse save file - JSON error at line " + str(json.get_error_line()) + ": " + json.get_error_message())
		print("First 200 characters of file:")
		print(json_string.substr(0, 200))
		return false
	
	var save_data = json.data
	
	if typeof(save_data) != TYPE_DICTIONARY:
		push_error("Invalid save data format - expected dictionary, got: " + str(typeof(save_data)))
		return false
	
	# Validate required fields
	if not save_data.has("ants"):
		push_error("Save data missing 'ants' field")
		return false
	
	if not save_data.has("pheromones"):
		push_error("Save data missing 'pheromones' field")
		return false
	
	clear_simulation(main_node)
	
	main_node.simulation_time = save_data.get("simulation_time", 0.0)
	main_node.total_food_collected = save_data.get("total_food_collected", 0)
	
	var ants_loaded = 0
	for ant_data in save_data.get("ants", []):
		var ant = deserialize_ant(main_node, ant_data)
		if ant:
			main_node.ants.append(ant)
			ants_loaded += 1
	
	if save_data.has("pheromones"):
		deserialize_pheromones(main_node.pheromone_map, save_data["pheromones"])
	
	if save_data.has("nest"):
		deserialize_nest(main_node.nest, save_data["nest"])
	
	print("✓ Simulation loaded from: " + save_path)
	print("  - Ants: %d" % ants_loaded)
	print("  - Time: %.1fs" % main_node.simulation_time)
	
	return true

static func serialize_ant(ant: AntAgent) -> Dictionary:
	return {
		"position": {"x": ant.global_position.x, "y": ant.global_position.y},
		"rotation": ant.rotation,
		"state": ant.state,
		"carrying_food": ant.carrying_food,
		"energy": ant.energy,
		"age": ant.age,
		"q_table": ant.q_table.duplicate(true),
		"parameters": {
			"speed": ant.speed,
			"rotation_speed": ant.rotation_speed,
			"sensor_range": ant.sensor_range,
			"learning_rate": ant.learning_rate,
			"discount": ant.discount,
			"epsilon": ant.epsilon,
			"epsilon_decay": ant.epsilon_decay,
			"min_epsilon": ant.min_epsilon,
			"curiosity": ant.curiosity,
			"adaptability": ant.adaptability,
			"pheromone_strength": ant.pheromone_strength
		},
		"memory": {
			"success_streak": ant.success_streak,
			"failure_count": ant.failure_count,
			"last_success_age": ant.last_success_age,
			"local_memory": ant.local_memory.duplicate(true),
			"food_memory": ant.food_memory.duplicate(true),
			"danger_memory": ant.danger_memory.duplicate(true)
		}
	}

static func deserialize_ant(main_node: Node2D, data: Dictionary) -> AntAgent:
	var ant = main_node.ant_scene.instantiate() as AntAgent
	
	ant.global_position = Vector2(data["position"]["x"], data["position"]["y"])
	ant.rotation = data.get("rotation", 0.0)
	ant.state = data.get("state", 0)
	ant.carrying_food = data.get("carrying_food", false)
	ant.energy = data.get("energy", 100.0)
	ant.age = data.get("age", 0)
	
	if data.has("q_table"):
		ant.q_table = data["q_table"].duplicate(true)
	
	if data.has("parameters"):
		var params = data["parameters"]
		ant.speed = params.get("speed", 120.0)
		ant.rotation_speed = params.get("rotation_speed", 4.0)
		ant.sensor_range = params.get("sensor_range", 70.0)
		ant.learning_rate = params.get("learning_rate", 0.3)
		ant.discount = params.get("discount", 0.85)
		ant.epsilon = params.get("epsilon", 0.4)
		ant.epsilon_decay = params.get("epsilon_decay", 0.9995)
		ant.min_epsilon = params.get("min_epsilon", 0.05)
		ant.curiosity = params.get("curiosity", 0.5)
		ant.adaptability = params.get("adaptability", 0.3)
		ant.pheromone_strength = params.get("pheromone_strength", 10.0)
	
	if data.has("memory"):
		var mem = data["memory"]
		ant.success_streak = mem.get("success_streak", 0)
		ant.failure_count = mem.get("failure_count", 0)
		ant.last_success_age = mem.get("last_success_age", 0)
		ant.local_memory = convert_memory_positions(mem.get("local_memory", []))
		ant.food_memory = convert_memory_positions(mem.get("food_memory", []))
		ant.danger_memory = convert_memory_positions(mem.get("danger_memory", []))
	
	ant.initialize(main_node.nest, main_node.pheromone_map)
	main_node.add_child(ant)
	ant.tree_exiting.connect(func(): main_node.on_ant_died(ant))
	
	return ant

static func serialize_food(food: FoodSource) -> Dictionary:
	return {
		"position": {"x": food.global_position.x, "y": food.global_position.y},
		"food_amount": food.food_amount,
		"max_amount": food.max_amount,
		"depleted": food.depleted,
		"auto_respawn": food.auto_respawn,
		"is_infinite": food.is_infinite
	}

static func deserialize_food(main_node: Node2D, data: Dictionary) -> FoodSource:
	var food = main_node.food_scene.instantiate() as FoodSource
	
	food.global_position = Vector2(data["position"]["x"], data["position"]["y"])
	food.food_amount = data.get("food_amount", 100)
	food.max_amount = data.get("max_amount", 100)
	food.depleted = data.get("depleted", false)
	food.auto_respawn = data.get("auto_respawn", false)
	food.is_infinite = data.get("is_infinite", false)
	
	main_node.add_child(food)
	food.food_depleted.connect(main_node.on_food_depleted.bind(food))
	
	return food

static func serialize_pheromones(pheromone_map: PheromoneMap) -> Dictionary:
	var compressed_success = []
	var compressed_danger = []
	var compressed_exploration = []
	
	for x in range(pheromone_map.grid_size.x):
		for y in range(pheromone_map.grid_size.y):
			var success_val = pheromone_map.success_grid[x][y]
			var danger_val = pheromone_map.danger_grid[x][y]
			var explore_val = pheromone_map.exploration_grid[x][y]
			
			if success_val > 0.1:
				compressed_success.append({"x": x, "y": y, "v": success_val})
			if danger_val > 0.1:
				compressed_danger.append({"x": x, "y": y, "v": danger_val})
			if explore_val > 0.1:
				compressed_exploration.append({"x": x, "y": y, "v": explore_val})
	
	return {
		"grid_size": {"x": pheromone_map.grid_size.x, "y": pheromone_map.grid_size.y},
		"success": compressed_success,
		"danger": compressed_danger,
		"exploration": compressed_exploration
	}

static func deserialize_pheromones(pheromone_map: PheromoneMap, data: Dictionary):
	pheromone_map.clear_all_pheromones()
	
	for entry in data.get("success", []):
		var x = entry["x"]
		var y = entry["y"]
		var v = entry["v"]
		if x < pheromone_map.grid_size.x and y < pheromone_map.grid_size.y:
			pheromone_map.success_grid[x][y] = v
	
	for entry in data.get("danger", []):
		var x = entry["x"]
		var y = entry["y"]
		var v = entry["v"]
		if x < pheromone_map.grid_size.x and y < pheromone_map.grid_size.y:
			pheromone_map.danger_grid[x][y] = v
	
	for entry in data.get("exploration", []):
		var x = entry["x"]
		var y = entry["y"]
		var v = entry["v"]
		if x < pheromone_map.grid_size.x and y < pheromone_map.grid_size.y:
			pheromone_map.exploration_grid[x][y] = v
	
	pheromone_map.update_visualization()

static func serialize_nest(nest: Nest) -> Dictionary:
	return {
		"position": {"x": nest.global_position.x, "y": nest.global_position.y},
		"food_storage": nest.food_storage
	}

static func deserialize_nest(nest: Nest, data: Dictionary):
	nest.food_storage = data.get("food_storage", 0)
	nest.update_visual()

static func clear_simulation(main_node: Node2D):
	for ant in main_node.ants:
		if is_instance_valid(ant):
			ant.queue_free()
	main_node.ants.clear()
	
	for food in main_node.food_sources:
		if is_instance_valid(food):
			food.queue_free()
	main_node.food_sources.clear()
	
	main_node.pheromone_map.clear_all_pheromones()
	main_node.nest.food_storage = 0
	main_node.nest.update_visual()

static func list_saves() -> Array:
	ensure_save_directory()
	var saves = []
	var dir = DirAccess.open(SAVE_DIR)
	
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(SAVE_EXTENSION):
				var save_name = file_name.trim_suffix(SAVE_EXTENSION)
				saves.append(save_name)
			file_name = dir.get_next()
		
		dir.list_dir_end()
	
	return saves

static func delete_save(save_name: String) -> bool:
	var save_path = SAVE_DIR + save_name + SAVE_EXTENSION
	
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
		print("✓ Deleted save: " + save_name)
		return true
	
	return false

static func recover_from_backup(save_name: String) -> bool:
	var save_path = SAVE_DIR + save_name + SAVE_EXTENSION
	var backup_path = save_path + ".backup"
	
	if not FileAccess.file_exists(backup_path):
		push_error("No backup found for: " + save_name)
		return false
	
	# Copy backup to main file
	DirAccess.copy_absolute(backup_path, save_path)
	print("✓ Recovered save from backup: " + save_name)
	return true

static func get_save_info(save_name: String) -> Dictionary:
	var save_path = SAVE_DIR + save_name + SAVE_EXTENSION
	
	if not FileAccess.file_exists(save_path):
		return {}
	
	var file = FileAccess.open(save_path, FileAccess.READ)
	if not file:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return {}
	
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	
	return {
		"timestamp": data.get("timestamp", "Unknown"),
		"simulation_time": data.get("simulation_time", 0.0),
		"total_food_collected": data.get("total_food_collected", 0),
		"ant_count": data.get("ants", []).size()
	}
