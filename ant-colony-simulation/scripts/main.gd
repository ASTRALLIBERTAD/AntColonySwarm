extends Node2D

@onready var pheromone_map: PheromoneMap = $PheromoneMap
@onready var nest: Nest = $Nest
@onready var serial_bridge: SerialBridge = $SerialBridge
@onready var ui: Control = $UI
@onready var camera: Camera2D = $Camera2D

var ant_scene = preload("res://scenes/ant.tscn")
var food_scene = preload("res://scenes/food.tscn")

@export var initial_ant_count: int = 30
@export var initial_food_sources: int = 12
@export var food_spawn_radius_min: float = 150.0
@export var food_spawn_radius_max: float = 450.0
@export var enable_evolution: bool = true
@export var generation_duration: float = 90.0

@export var tournament_size: int = 3
@export var elite_percentage: float = 0.20

@export var auto_spawn_food: bool = true
@export var spawn_food_threshold: int = 4
@export var max_food_sources: int = 15
@export var food_per_source_min: int = 60
@export var food_per_source_max: int = 120

var ants: Array[AntAgent] = []
var food_sources: Array = []
var current_generation: int = 0
var generation_timer: float = 0.0
var best_ant: AntAgent = null
var best_fitness: float = 0.0
var total_food_collected: int = 0
var simulation_time: float = 0.0

var searched_tiles: Dictionary = {}
var tiles_being_searched: Dictionary = {}
var tile_size: float = 150.0
var tile_timeout: float = 10.0

var tile_search_duration: float = 30.0

func _ready():
	print("╔═══════════════════════════════════════════════╗")
	print("║  IMPROVED ANT COLONY - NO RESPAWN TRAINING   ║")
	print("╚═══════════════════════════════════════════════╝")
	
	setup_world()
	spawn_colony()
	spawn_food_sources()
	connect_signals()
	
	print("\n✓ Simulation ready!")
	print("  Ants: ", ants.size())
	print("  Food sources: ", food_sources.size())
	print("  Food per source: %d-%d units" % [food_per_source_min, food_per_source_max])
	print("  Tournament size: ", tournament_size)
	print("  Elite percentage: %.0f%%" % (elite_percentage * 100))
	print("  Generation duration: %.0fs" % generation_duration)
	print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

func setup_world():
	var viewport_size = get_viewport_rect().size
	nest.global_position = viewport_size / 2
	
	if camera:
		camera.global_position = viewport_size / 2

func spawn_colony():
	for i in range(initial_ant_count):
		spawn_ant()

func spawn_ant(spawn_position: Vector2 = Vector2.ZERO, parent_data: Dictionary = {}) -> AntAgent:
	var ant = ant_scene.instantiate() as AntAgent
	
	var final_position = spawn_position
	if spawn_position == Vector2.ZERO:
		final_position = nest.get_position_for_ant()
	
	ant.global_position = final_position
	ant.initialize(nest, pheromone_map)
	
	if parent_data.size() > 0:
		ant.import_brain_data(parent_data)
	
	add_child(ant)
	ants.append(ant)
	
	return ant

func spawn_food_sources():
	var viewport_size = get_viewport_rect().size
	
	print("\n  🍎 Spawning initial food sources:")
	
	var distance_ranges = [
		{"min": 150, "max": 250, "count": 4},
		{"min": 250, "max": 350, "count": 4},
		{"min": 350, "max": 500, "count": 4}
	]
	
	for range_info in distance_ranges:
		for i in range(range_info.count):
			spawn_food_at_distance(range_info.min, range_info.max)

func spawn_food_at_distance(min_dist: float, max_dist: float):
	var food = food_scene.instantiate() as FoodSource
	
	var angle = randf() * TAU
	var distance = randf_range(min_dist, max_dist)
	var pos = nest.global_position + Vector2(distance, 0).rotated(angle)
	
	var viewport_size = get_viewport_rect().size
	pos.x = clamp(pos.x, 100, viewport_size.x - 100)
	pos.y = clamp(pos.y, 100, viewport_size.y - 100)
	
	food.global_position = pos
	food.food_amount = randi_range(food_per_source_min, food_per_source_max)
	food.max_amount = food.food_amount
	food.auto_respawn = false
	food.is_infinite = false
	
	add_child(food)
	food_sources.append(food)
	food.food_depleted.connect(_on_food_depleted)
	
	print("    Food at distance %.0f: %d units" % [distance, food.food_amount])

func spawn_food_at_mouse():
	var mouse_pos = get_viewport().get_mouse_position()
	var food = food_scene.instantiate() as FoodSource
	food.global_position = mouse_pos
	food.food_amount = 75
	food.max_amount = 75
	food.auto_respawn = false
	add_child(food)
	food_sources.append(food)
	food.food_depleted.connect(_on_food_depleted)
	print("✓ Manual food spawned at mouse position (75 units)")

func connect_signals():
	nest.food_delivered.connect(_on_food_delivered)

func _input(event: InputEvent):
	if event.is_action_pressed("toggle_pheromone_view"):
		pheromone_map.show_pheromones = !pheromone_map.show_pheromones
		print("[P] Pheromones: ", "ON" if pheromone_map.show_pheromones else "OFF")
	
	elif event.is_action_pressed("export_best"):
		export_best_ant()
	
	elif event.is_action_pressed("send_to_arduino"):
		send_to_arduino()
	
	elif event.is_action_pressed("reset_simulation"):
		reset_simulation()
	
	elif event.is_action_pressed("spawn_food"):
		spawn_food_at_mouse()
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			spawn_food_at_mouse()

func _process(delta: float):
	simulation_time += delta
	
	if auto_spawn_food:
		check_and_spawn_food()
	
	cleanup_tile_claims()
	
	update_statistics()
	
	if enable_evolution:
		generation_timer += delta
		if generation_timer >= generation_duration:
			evolve_population()
			generation_timer = 0.0

func cleanup_tile_claims():
	var tiles_to_remove = []
	for tile in tiles_being_searched.keys():
		var time_since_claimed = simulation_time - tiles_being_searched[tile]
		if time_since_claimed > tile_timeout:
			tiles_to_remove.append(tile)
	
	for tile in tiles_to_remove:
		tiles_being_searched.erase(tile)

func check_and_spawn_food():
	var active_food = count_active_food()
	
	if active_food <= spawn_food_threshold and food_sources.size() < max_food_sources:
		var to_spawn = min(3, max_food_sources - food_sources.size())
		print("⚠ Only %d food sources active, spawning %d more..." % [active_food, to_spawn])
		
		for i in range(to_spawn):
			var distance = randf_range(food_spawn_radius_min, food_spawn_radius_max)
			spawn_food_at_distance(distance - 50, distance + 50)

func count_active_food() -> int:
	var count = 0
	for food in food_sources:
		if is_instance_valid(food) and not food.depleted:
			count += 1
	return count

func update_statistics():
	best_fitness = 0.0
	
	for ant in ants:
		if not is_instance_valid(ant):
			continue
		
		var fitness = ant.get_fitness()
		if fitness > best_fitness:
			best_fitness = fitness
			best_ant = ant
	
	if ui:
		var active_food = count_active_food()
		var total_food_remaining = 0
		for food in food_sources:
			if is_instance_valid(food) and not food.depleted:
				total_food_remaining += food.food_amount
		
		ui.update_statistics({
			"generation": current_generation,
			"ants": ants.size(),
			"food_collected": total_food_collected,
			"active_food": active_food,
			"total_food": food_sources.size(),
			"food_remaining": total_food_remaining,
			"simulation_time": simulation_time,
			"best_fitness": best_fitness,
			"pheromone_total": pheromone_map.get_total_pheromone(),
			"arduino_connected": false
		})

func evolve_population():
	current_generation += 1
	
	print("\n" + "═".repeat(70))
	print("║ GENERATION %d COMPLETE" % current_generation)
	print("═".repeat(70))
	
	var fitness_data = []
	var total_fitness = 0.0
	var total_food = 0
	var ants_with_food = 0
	var max_food = 0
	var total_distance = 0.0
	
	for ant in ants:
		if not is_instance_valid(ant):
			continue
		
		var fitness = ant.get_fitness()
		var food = ant.food_collected
		
		fitness_data.append({
			"ant": ant,
			"fitness": fitness,
			"food": food,
			"distance": ant.distance_traveled,
			"time": ant.time_alive,
			"collisions": ant.collision_count,
			"stuck": ant.times_stuck,
			"failed": ant.failed_food_attempts
		})
		
		total_fitness += fitness
		total_food += food
		total_distance += ant.distance_traveled
		if food > 0:
			ants_with_food += 1
		max_food = max(max_food, food)
	
	fitness_data.sort_custom(func(a, b): return a["fitness"] > b["fitness"])
	
	var avg_fitness = total_fitness / fitness_data.size() if fitness_data.size() > 0 else 0.0
	var avg_food = float(total_food) / float(fitness_data.size()) if fitness_data.size() > 0 else 0.0
	var avg_distance = total_distance / fitness_data.size() if fitness_data.size() > 0 else 0.0
	
	print("\n  📊 COLONY PERFORMANCE:")
	print("    Total Food Collected: %d" % total_food)
	print("    Average Food per Ant: %.2f" % avg_food)
	print("    Max Food (single ant): %d" % max_food)
	print("    Success Rate: %d/%d (%.1f%%)" % [
		ants_with_food, 
		ants.size(), 
		(ants_with_food * 100.0 / ants.size()) if ants.size() > 0 else 0
	])
	print("    Average Distance: %.0f units" % avg_distance)
	
	print("\n  💪 FITNESS METRICS:")
	print("    Average Fitness: %.1f" % avg_fitness)
	print("    Best Fitness: %.1f" % (fitness_data[0]["fitness"] if fitness_data.size() > 0 else 0))
	print("    Worst Fitness: %.1f" % (fitness_data[-1]["fitness"] if fitness_data.size() > 0 else 0))
	print("    Fitness Range: %.1f" % ((fitness_data[0]["fitness"] - fitness_data[-1]["fitness"]) if fitness_data.size() > 0 else 0))
	
	print("\n  🏆 TOP 3 ANTS:")
	for i in range(min(3, fitness_data.size())):
		var data = fitness_data[i]
		print("    #%d: Fitness=%.1f, Food=%d, Dist=%.0f, Circles=%d" % [
			i + 1,
			data["fitness"],
			data["food"],
			data["distance"],
			data["ant"].revisit_count
		])
	
	var active_food = count_active_food()
	var total_food_remaining = 0
	for food in food_sources:
		if is_instance_valid(food) and not food.depleted:
			total_food_remaining += food.food_amount
	
	print("\n  🍎 FOOD SOURCES:")
	print("    Active: %d/%d" % [active_food, food_sources.size()])
	print("    Total Food Remaining: %d units" % total_food_remaining)
	print("    Depleted This Gen: %d" % (food_sources.size() - active_food))
	
	var elite_count = max(int(ants.size() * elite_percentage), 3)
	var elite_ants = []
	
	for i in range(min(elite_count, fitness_data.size())):
		if fitness_data[i]["food"] > 0:
			elite_ants.append(fitness_data[i]["ant"])
	
	if elite_ants.size() < 3:
		print("  ⚠ WARNING: Only %d ants collected food - filling elite with best performers" % elite_ants.size())
		for i in range(min(elite_count, fitness_data.size())):
			if not fitness_data[i]["ant"] in elite_ants:
				elite_ants.append(fitness_data[i]["ant"])
			if elite_ants.size() >= elite_count:
				break
	
	print("\n  🎖️ ELITE SELECTION:")
	print("    Elite count: %d (top %.0f%%)" % [elite_ants.size(), elite_percentage * 100])
	print("    All collected food: %s" % ("✓" if elite_ants.size() == ants_with_food else "✗"))
	
	print("\n  🎲 TOURNAMENT SELECTION:")
	print("    Tournament size: %d" % tournament_size)
	print("    Creating %d offspring..." % (ants.size() - elite_ants.size()))
	
	var offspring_created = 0
	
	for i in range(elite_ants.size(), ants.size()):
		if i >= ants.size():
			break
		
		var child_ant = ants[i]
		if not is_instance_valid(child_ant):
			continue
		
		var parent1 = tournament_select(fitness_data)
		var parent2 = tournament_select(fitness_data)
		
		var child_traits = crossover_traits(parent1, parent2)
		child_traits = mutate_traits(child_traits)
		
		child_ant.import_brain_data({"traits": child_traits})
		
		if child_ant.enable_neural_learning:
			crossover_neural_network(parent1, parent2, child_ant)
			if child_ant.brain:
				child_ant.brain.mutate(0.1, 0.15)
		
		reset_ant(child_ant)
		
		offspring_created += 1
	
	for ant in elite_ants:
		reset_ant(ant)
	
	print("    ✓ Created %d offspring via tournament" % offspring_created)
	print("    ✓ Reset %d elite ants" % elite_ants.size())
	
	print("\n  ✅ Generation %d evolution complete!" % current_generation)
	print("═".repeat(70) + "\n")

func get_unsearched_tile(ant_position: Vector2, sector: int) -> Vector2i:
	var viewport_size = get_viewport_rect().size
	var max_tile_x = int(viewport_size.x / tile_size)
	var max_tile_y = int(viewport_size.y / tile_size)
	
	var sector_tiles = get_sector_tiles(sector, max_tile_x, max_tile_y)
	
	var closest_unsearched = Vector2i(-1, -1)
	var closest_distance = 999999.0
	
	for tile in sector_tiles:
		if searched_tiles.has(tile):
			var time_since_search = simulation_time - searched_tiles[tile]
			if time_since_search < 30.0:
				continue
		
		if tiles_being_searched.has(tile):
			var time_since_claimed = simulation_time - tiles_being_searched[tile]
			if time_since_claimed < tile_timeout:
				continue
		
		var tile_world = tile_to_world_pos(tile)
		var distance = ant_position.distance_to(tile_world)
		
		if distance < closest_distance:
			closest_distance = distance
			closest_unsearched = tile
	
	return closest_unsearched

func get_sector_tiles(sector: int, max_x: int, max_y: int) -> Array:
	var tiles = []
	var center_x = max_x / 2
	var center_y = max_y / 2
	
	var sector_angles = {
		0: [0, 45],      # N
		1: [45, 90],     # NE
		2: [90, 135],    # E
		3: [135, 180],   # SE
		4: [180, 225],   # S
		5: [225, 270],   # SW
		6: [270, 315],   # W
		7: [315, 360]    # NW
	}
	
	var angle_range = sector_angles.get(sector, [0, 45])
	var min_angle = angle_range[0]
	var max_angle = angle_range[1]
	
	for x in range(max_x):
		for y in range(max_y):
			var tile = Vector2i(x, y)
			var tile_world = tile_to_world_pos(tile)
			var to_tile = tile_world - nest.global_position
			var angle = rad_to_deg(to_tile.angle())
			if angle < 0:
				angle += 360
			
			if angle >= min_angle and angle < max_angle:
				tiles.append(tile)
	
	return tiles

func tile_to_world_pos(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * tile_size + tile_size / 2, tile.y * tile_size + tile_size / 2)

func mark_tile_being_searched(tile: Vector2i):
	tiles_being_searched[tile] = simulation_time

func mark_tile_searched(tile: Vector2i):
	searched_tiles[tile] = simulation_time
	if tiles_being_searched.has(tile):
		tiles_being_searched.erase(tile)

func tournament_select(fitness_data: Array) -> AntAgent:
	var tournament_contestants = []
	
	for i in range(tournament_size):
		var random_index = randi() % fitness_data.size()
		tournament_contestants.append(fitness_data[random_index])
	
	var winner = tournament_contestants[0]
	for contestant in tournament_contestants:
		if contestant.fitness > winner.fitness:
			winner = contestant
	
	return winner.ant

func crossover_traits(parent1: AntAgent, parent2: AntAgent) -> Dictionary:
	var traits = {}
	
	traits["food_detection_range"] = parent1.food_detection_range if randf() > 0.5 else parent2.food_detection_range
	traits["pheromone_follow_strength"] = parent1.pheromone_follow_strength if randf() > 0.5 else parent2.pheromone_follow_strength
	traits["pheromone_deposit_rate"] = parent1.pheromone_deposit_rate if randf() > 0.5 else parent2.pheromone_deposit_rate
	traits["exploration_randomness"] = parent1.exploration_randomness if randf() > 0.5 else parent2.exploration_randomness
	traits["max_speed"] = parent1.max_speed if randf() > 0.5 else parent2.max_speed
	traits["turn_speed"] = parent1.turn_speed if randf() > 0.5 else parent2.turn_speed
	traits["scout_tendency"] = (parent1.scout_tendency + parent2.scout_tendency) / 2.0
	traits["forager_efficiency"] = (parent1.forager_efficiency + parent2.forager_efficiency) / 2.0
	
	return traits

func crossover_neural_network(parent1: AntAgent, parent2: AntAgent, child: AntAgent):
	if not parent1 or not parent2 or not child:
		return
	if not is_instance_valid(parent1) or not is_instance_valid(parent2) or not is_instance_valid(child):
		return
	if not parent1.brain or not parent2.brain or not child.brain:
		return
	
	var parent_brain = parent1.brain if randf() > 0.5 else parent2.brain
	
	for i in range(min(parent_brain.input_size, child.brain.input_size)):
		for j in range(min(parent_brain.hidden_size, child.brain.hidden_size)):
			if randf() > 0.5:
				child.brain.weights_input_hidden[i][j] = parent1.brain.weights_input_hidden[i][j]
			else:
				child.brain.weights_input_hidden[i][j] = parent2.brain.weights_input_hidden[i][j]
	
	for i in range(min(parent_brain.hidden_size, child.brain.hidden_size)):
		for j in range(min(parent_brain.output_size, child.brain.output_size)):
			if randf() > 0.5:
				child.brain.weights_hidden_output[i][j] = parent1.brain.weights_hidden_output[i][j]
			else:
				child.brain.weights_hidden_output[i][j] = parent2.brain.weights_hidden_output[i][j]
	
	for i in range(min(parent_brain.hidden_size, child.brain.hidden_size)):
		child.brain.bias_hidden[i] = parent1.brain.bias_hidden[i] if randf() > 0.5 else parent2.brain.bias_hidden[i]
	
	for i in range(min(parent_brain.output_size, child.brain.output_size)):
		child.brain.bias_output[i] = parent1.brain.bias_output[i] if randf() > 0.5 else parent2.brain.bias_output[i]

func mutate_traits(traits: Dictionary) -> Dictionary:
	var mutation_rate = 0.3
	var mutation_strength = 0.2
	
	for trait_name in traits.keys():
		if randf() < mutation_rate:
			var current_value = traits[trait_name]
			var mutation = randf_range(-mutation_strength, mutation_strength) * current_value
			traits[trait_name] = current_value + mutation
			
			match trait_name:
				"food_detection_range":
					traits[trait_name] = clamp(traits[trait_name], 50.0, 200.0)
				"pheromone_follow_strength":
					traits[trait_name] = clamp(traits[trait_name], 0.5, 5.0)
				"pheromone_deposit_rate":
					traits[trait_name] = clamp(traits[trait_name], 1.0, 20.0)
				"exploration_randomness":
					traits[trait_name] = clamp(traits[trait_name], 0.1, 1.5)
				"max_speed":
					traits[trait_name] = clamp(traits[trait_name], 100.0, 250.0)
				"turn_speed":
					traits[trait_name] = clamp(traits[trait_name], 2.0, 10.0)
				"scout_tendency":
					traits[trait_name] = clamp(traits[trait_name], 0.0, 1.0)
				"forager_efficiency":
					traits[trait_name] = clamp(traits[trait_name], 0.0, 1.0)
	
	return traits

func reset_ant(ant: AntAgent):
	ant.food_collected = 0
	ant.successful_returns = 0
	ant.distance_traveled = 0.0
	ant.time_alive = 0.0
	ant.collision_count = 0
	ant.times_stuck = 0
	ant.failed_food_attempts = 0
	ant.visited_positions.clear()
	ant.exploration_coverage = 0.0
	ant.revisit_count = 0
	ant.position_history.clear()
	ant.history_check_interval = 0.0
	ant.found_food_signal = false
	ant.signal_timer = 0.0
	ant.food_location = Vector2.ZERO
	ant.current_target_tile = Vector2i(-1, -1)
	ant.time_in_current_tile = 0.0
	ant.last_state.clear()
	ant.last_action.clear()
	ant.cumulative_reward = 0.0
	ant.learning_step_counter = 0
	ant.food_sources_discovered = 0
	ant.unique_food_sources.clear()
	ant.discovery_bonus_earned = 0
	ant.global_position = nest.get_position_for_ant()
	ant.current_state = AntAgent.State.WANDERING
	ant.has_food = false
	ant.target_food = null
	ant.modulate = Color.WHITE

func export_best_ant():
	if not best_ant or not is_instance_valid(best_ant):
		print("✗ No valid ant to export!")
		return
	
	var brain_data = best_ant.export_brain_data()
	
	var file = FileAccess.open("user://best_ant_gen%d.json" % current_generation, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(brain_data, "\t"))
		file.close()
		print("\n✓ Exported Gen %d Best Ant (Fitness: %.1f, Food: %d)\n" % [
			current_generation,
			best_fitness,
			best_ant.food_collected
		])

func send_to_arduino():
	print("✗ Arduino integration disabled for debugging")

func _on_food_delivered(amount: int, _total: int):
	total_food_collected += amount

func _on_food_depleted(food_source: FoodSource):
	var active = count_active_food()
	print("⚠ Food depleted at (%.0f, %.0f) - %d active sources remaining" % [
		food_source.global_position.x,
		food_source.global_position.y,
		active
	])

func reset_simulation():
	print("\n⟲ Resetting simulation...")
	
	for ant in ants:
		if is_instance_valid(ant):
			ant.queue_free()
	ants.clear()
	
	for food in food_sources:
		if is_instance_valid(food):
			food.queue_free()
	food_sources.clear()
	
	total_food_collected = 0
	simulation_time = 0.0
	current_generation = 0
	generation_timer = 0.0
	best_fitness = 0.0
	best_ant = null
	
	searched_tiles.clear()
	tiles_being_searched.clear()
	
	pheromone_map.clear_all_pheromones()
	nest.food_storage = 0
	nest.update_visual()
	
	spawn_colony()
	spawn_food_sources()
	
	print("✓ Reset complete\n")
