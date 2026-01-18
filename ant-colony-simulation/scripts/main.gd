extends Node2D

@onready var pheromone_map: PheromoneMap = $PheromoneMap
@onready var nest: Nest = $Nest
@onready var serial_bridge: SerialBridge = $SerialBridge
@onready var ui: Control = $UI
@onready var camera: Camera2D = $Camera2D

var ant_scene = preload("res://scenes/ant.tscn")
var food_scene = preload("res://scenes/food.tscn")

@export var initial_ant_count: int = 30
@export var initial_food_sources: int = 8  
@export var food_respawn_distance: float = 150.0  
@export var enable_evolution: bool = true
@export var generation_duration: float = 60.0
@export var min_fitness_for_elite: float = 100.0

@export var tournament_size: int = 3
@export var elite_percentage: float = 0.20  

@export var auto_spawn_food: bool = true
@export var spawn_food_threshold: int = 5  
@export var max_food_sources: int = 12

var ants: Array[AntAgent] = []
var food_sources: Array = []
var current_generation: int = 0
var generation_timer: float = 0.0
var best_ant: AntAgent = null
var best_fitness: float = 0.0
var total_food_collected: int = 0
var simulation_time: float = 0.0

func _ready():
	print("╔═══════════════════════════════════════════════╗")
	print("║  ANT COLONY - PERSISTENT FOOD + TOURNAMENT   ║")
	print("╚═══════════════════════════════════════════════╝")
	
	setup_world()
	spawn_colony()
	spawn_food_sources()
	connect_signals()
	
	print("\n✓ Simulation ready!")
	print("  Ants: ", ants.size())
	print("  Food sources: ", food_sources.size())
	print("  Tournament size: ", tournament_size)
	print("  Elite percentage: %.0f%%" % (elite_percentage * 100))
	print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

func setup_world():
	var viewport_size = get_viewport_rect().size
	nest.global_position = viewport_size / 2
	
	if camera:
		camera.global_position = viewport_size / 2

func spawn_colony():
	for i in range(initial_ant_count):
		spawn_ant()

func spawn_ant(position: Vector2 = Vector2.ZERO, parent_data: Dictionary = {}) -> AntAgent:
	var ant = ant_scene.instantiate() as AntAgent
	
	if position == Vector2.ZERO:
		position = nest.get_position_for_ant()
	
	ant.global_position = position
	ant.initialize(nest, pheromone_map)
	
	if parent_data.size() > 0:
		ant.import_brain_data(parent_data)
	
	add_child(ant)
	ants.append(ant)
	
	return ant

func spawn_food_sources():
	var viewport_size = get_viewport_rect().size
	
	var distances = [200, 250, 300, 350, 400, 450]
	
	for i in range(initial_food_sources):
		spawn_food_source_close()

func spawn_food_source_close():
	var food = food_scene.instantiate() as FoodSource

	var angle = randf() * TAU
	var distance = randf_range(120, 200) 
	
	var pos = nest.global_position + Vector2(distance, 0).rotated(angle)
	
	food.global_position = pos
	food.food_amount = 100  
	food.max_amount = 100
	food.auto_respawn = true 
	food.respawn_time = 15.0
	food.is_infinite = false
	
	add_child(food)
	food_sources.append(food)
	food.food_depleted.connect(_on_food_depleted)
	
	print("  Food spawned at distance %.0f" % nest.global_position.distance_to(pos))

func spawn_food_source(distance: float = 0.0):
	var viewport_size = get_viewport_rect().size
	var food = food_scene.instantiate() as FoodSource

	var pos: Vector2
	
	if distance > 0:
		var angle = randf() * TAU
		pos = nest.global_position + Vector2(distance, 0).rotated(angle)
	else:
		var attempts = 0
		while attempts < 50:
			pos = Vector2(
				randf_range(150, viewport_size.x - 150),
				randf_range(150, viewport_size.y - 150)
			)
			if pos.distance_to(nest.global_position) > 200:
				break
			attempts += 1

	pos.x = clamp(pos.x, 100, viewport_size.x - 100)
	pos.y = clamp(pos.y, 100, viewport_size.y - 100)
	
	food.global_position = pos
	food.food_amount = randi_range(40, 80) 
	food.max_amount = food.food_amount
	food.auto_respawn = false  
	food.is_infinite = false
	
	add_child(food)
	food_sources.append(food)
	food.food_depleted.connect(_on_food_depleted)

func spawn_food_at_mouse():
	var mouse_pos = get_viewport().get_mouse_position()
	var food = food_scene.instantiate() as FoodSource
	food.global_position = mouse_pos
	food.food_amount = 50
	food.max_amount = 50
	food.auto_respawn = false
	add_child(food)
	food_sources.append(food)
	food.food_depleted.connect(_on_food_depleted)
	print("✓ Manual food spawned at mouse position")

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
	
	update_statistics()
	
	if enable_evolution:
		generation_timer += delta
		if generation_timer >= generation_duration:
			evolve_population()
			generation_timer = 0.0

func check_and_spawn_food():
	var active_food = 0
	for food in food_sources:
		if is_instance_valid(food) and not food.depleted:
			active_food += 1
	
	if active_food <= spawn_food_threshold:
		print("⚠ Only %d food, spawning more..." % active_food)
		for i in range(3): 
			spawn_food_source_close()

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
		var active_food = 0
		for food in food_sources:
			if is_instance_valid(food) and not food.depleted:
				active_food += 1
		
		ui.update_statistics({
			"generation": current_generation,
			"ants": ants.size(),
			"food_collected": total_food_collected,
			"active_food": active_food,
			"total_food": food_sources.size(),
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
		if food > 0:
			ants_with_food += 1
		max_food = max(max_food, food)
	
	fitness_data.sort_custom(func(a, b): return a["fitness"] > b["fitness"])
	
	var avg_fitness = total_fitness / fitness_data.size() if fitness_data.size() > 0 else 0.0
	var avg_food = float(total_food) / float(fitness_data.size()) if fitness_data.size() > 0 else 0.0
	
	print("\n  📊 COLONY PERFORMANCE:")
	print("    Total Food Collected: %d" % total_food)
	print("    Average Food per Ant: %.2f" % avg_food)
	print("    Max Food (single ant): %d" % max_food)
	print("    Success Rate: %d/%d (%.1f%%)" % [
		ants_with_food, 
		ants.size(), 
		(ants_with_food * 100.0 / ants.size())
	])
	
	print("\n  💪 FITNESS METRICS:")
	print("    Average Fitness: %.1f" % avg_fitness)
	print("    Best Fitness: %.1f" % fitness_data[0]["fitness"] if fitness_data.size() > 0 else 0)
	print("    Worst Fitness: %.1f" % fitness_data[-1]["fitness"] if fitness_data.size() > 0 else 0)
	print("    Fitness Range: %.1f" % ((fitness_data[0]["fitness"] - fitness_data[-1]["fitness"]) if fitness_data.size() > 0 else 0))
	
	print("\n  🏆 TOP 3 ANTS:")
	for i in range(min(3, fitness_data.size())):
		var data = fitness_data[i]
		print("    #%d: Fitness=%.1f, Food=%d, Dist=%.0f, Collisions=%d, Stuck=%d" % [
			i + 1,
			data["fitness"],
			data["food"],
			data["distance"],
			data["collisions"],
			data["stuck"]
		])
	
	print("\n  💀 WORST 3 ANTS (Being Eliminated):")
	var worst_start = max(0, fitness_data.size() - 3)
	for i in range(worst_start, fitness_data.size()):
		var data = fitness_data[i]
		print("    #%d: Fitness=%.1f, Food=%d, Collisions=%d, Stuck=%d, Failed=%d" % [
			fitness_data.size() - i,
			data["fitness"],
			data["food"],
			data["collisions"],
			data["stuck"],
			data["failed"]
		])
	
	var active_food = 0
	var total_food_remaining = 0
	for food in food_sources:
		if is_instance_valid(food):
			if not food.depleted:
				active_food += 1
				total_food_remaining += food.food_amount
	
	print("\n  🍎 FOOD SOURCES:")
	print("    Active: %d/%d" % [active_food, food_sources.size()])
	print("    Total Food Remaining: %d units" % total_food_remaining)
	
	var elite_count = max(int(ants.size() * elite_percentage), 3)
	var elite_ants = []

	for i in range(elite_count):
		if i < fitness_data.size():
			elite_ants.append(fitness_data[i]["ant"])
	
	print("\n  🎖️ ELITE SELECTION:")
	print("    Elite count: %d (top %.0f%%)" % [elite_count, elite_percentage * 100])
	
	if elite_ants.size() > 0:
		print("    Elite fitness range: %.1f to %.1f" % [
			fitness_data[0]["fitness"],
			fitness_data[min(elite_count - 1, fitness_data.size() - 1)]["fitness"]
		])
		print("    Elite food range: %d to %d" % [
			fitness_data[0]["food"],
			fitness_data[min(elite_count - 1, fitness_data.size() - 1)]["food"]
		])

	print("\n  🎲 TOURNAMENT SELECTION:")
	print("    Tournament size: %d" % tournament_size)
	print("    Creating %d offspring..." % (ants.size() - elite_count))
	
	var offspring_created = 0
	
	for i in range(elite_count, ants.size()):
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
		
		reset_ant(child_ant)
		
		offspring_created += 1
	
	print("    ✓ Created %d offspring via tournament" % offspring_created)
	
	print("\n  ✅ Generation %d evolution complete!" % current_generation)
	print("═".repeat(70) + "\n")

	var qualified_elite = []
	for i in range(fitness_data.size()):
		if fitness_data[i]["food"] > 0:  
			qualified_elite.append(fitness_data[i]["ant"])
			if qualified_elite.size() >= elite_count:
				break
	
	if qualified_elite.size() < 3:
		print("  ⚠ WARNING: Only %d ants collected food!" % qualified_elite.size())
		for i in range(min(elite_count, fitness_data.size())):
			if not fitness_data[i]["ant"] in qualified_elite:
				qualified_elite.append(fitness_data[i]["ant"])
	
	elite_ants = qualified_elite
	
	print("\n  🎖️ ELITE SELECTION:")
	print("    Elite count: %d (from %d that collected food)" % [elite_ants.size(), ants_with_food])

func tournament_select(fitness_data: Array) -> AntAgent:
	"""
	Tournament Selection:
	1. Pick N random ants (tournament_size)
	2. Return the best one from that group
	This maintains diversity better than pure elitism
	"""
	
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
	"""
	Uniform crossover - randomly inherit each trait from either parent
	"""
	var traits = {}
	
	traits["food_detection_range"] = parent1.food_detection_range if randf() > 0.5 else parent2.food_detection_range
	traits["pheromone_follow_strength"] = parent1.pheromone_follow_strength if randf() > 0.5 else parent2.pheromone_follow_strength
	traits["pheromone_deposit_rate"] = parent1.pheromone_deposit_rate if randf() > 0.5 else parent2.pheromone_deposit_rate
	traits["exploration_randomness"] = parent1.exploration_randomness if randf() > 0.5 else parent2.exploration_randomness
	traits["max_speed"] = parent1.max_speed if randf() > 0.5 else parent2.max_speed
	traits["turn_speed"] = parent1.turn_speed if randf() > 0.5 else parent2.turn_speed
	
	return traits

func mutate_traits(traits: Dictionary) -> Dictionary:
	"""
	Mutation: Random changes to traits
	"""
	var mutation_rate = 0.25 
	var mutation_strength = 0.15  
	
	for trait_name in traits.keys():
		if randf() < mutation_rate:
			var current_value = traits[trait_name]
			var mutation = randf_range(-mutation_strength, mutation_strength) * current_value
			traits[trait_name] = current_value + mutation
			
			match trait_name:
				"food_detection_range":
					traits[trait_name] = clamp(traits[trait_name], 50.0, 150.0)
				"pheromone_follow_strength":
					traits[trait_name] = clamp(traits[trait_name], 0.5, 5.0)
				"pheromone_deposit_rate":
					traits[trait_name] = clamp(traits[trait_name], 1.0, 15.0)
				"exploration_randomness":
					traits[trait_name] = clamp(traits[trait_name], 0.1, 1.0)
				"max_speed":
					traits[trait_name] = clamp(traits[trait_name], 100.0, 250.0)
				"turn_speed":
					traits[trait_name] = clamp(traits[trait_name], 3.0, 10.0)
	
	return traits

func reset_ant(ant: AntAgent):
	"""Reset ant to starting state"""
	ant.food_collected = 0
	ant.successful_returns = 0
	ant.distance_traveled = 0.0
	ant.time_alive = 0.0
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


func _on_food_delivered(amount: int, total: int):
	total_food_collected += amount

func _on_food_depleted(food_source: FoodSource):
	print("⚠ Food source depleted, %d sources remaining" % count_active_food())

func count_active_food() -> int:
	var count = 0
	for food in food_sources:
		if is_instance_valid(food) and not food.depleted:
			count += 1
	return count


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
	
	pheromone_map.clear_all_pheromones()
	nest.food_storage = 0
	nest.update_visual()
	
	spawn_colony()
	spawn_food_sources()
	
	print("✓ Reset complete\n")
