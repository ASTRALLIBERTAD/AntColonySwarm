extends Node2D

const SaveLoadSystem = preload("res://scripts/save_load_system.gd")

@onready var pheromone_map: PheromoneMap = $PheromoneMap
@onready var nest: Nest = $Nest
@onready var ui: Control = $UI
@onready var camera: Camera2D = $Camera2D

var ant_scene = preload("res://scenes/ant.tscn")
var food_scene = preload("res://scenes/food.tscn")
var obstacle_scene = preload("res://scenes/obstacle.tscn")

@export var initial_ant_count: int = 40
@export var max_ant_count: int = 60
@export var ant_spawn_rate: float = 15.0
@export var food_spawn_interval: float = 20.0
@export var spawn_obstacles: bool = true
@export var obstacle_count: int = 8

var ants: Array = []
var food_sources: Array = []
var obstacles: Array = []
var simulation_time: float = 0.0
var next_spawn_time: float = 0.0
var next_food_spawn: float = 0.0
var total_food_collected: int = 0
var total_deaths: int = 0
var death_positions: Array = []  # Track where deaths occur
var inherited_knowledge: Array = []  # Q-tables from dead ants

var world_bounds: Rect2
var spawn_zones: Array = []

func _ready():
	check_input_actions()
	setup_world()
	setup_spawn_zones()
	if spawn_obstacles:
		spawn_initial_obstacles()
	spawn_initial_ants()
	spawn_initial_food()
	connect_signals()

func check_input_actions():
	var required_actions = [
		"toggle_pheromone_view",
		"spawn_food",
		"reset_simulation",
		"quick_save",
		"quick_load",
		"save_menu"
	]
	
	var missing_actions = []
	for action in required_actions:
		if not InputMap.has_action(action):
			missing_actions.append(action)
	
	if missing_actions.size() > 0:
		print("\n⚠ WARNING: Missing input actions!")
		print("Please add these in Project Settings → Input Map:")
		for action in missing_actions:
			match action:
				"quick_save":
					print("  - %s → S key" % action)
				"quick_load":
					print("  - %s → L key" % action)
				"save_menu":
					print("  - %s → M key" % action)
				_:
					print("  - %s" % action)
		print("\nSave/Load won't work until these are added!\n")
	else:
		print("✓ All input actions configured correctly")

func setup_world():
	var viewport_size = get_viewport_rect().size
	world_bounds = Rect2(50, 50, viewport_size.x - 100, viewport_size.y - 100)
	nest.global_position = viewport_size / 2
	
	if camera:
		camera.global_position = viewport_size / 2

func setup_spawn_zones():
	var center = nest.global_position
	var radius_ranges = [
		{"min": 200, "max": 350},
		{"min": 350, "max": 500},
		{"min": 500, "max": 650}
	]
	
	for range_data in radius_ranges:
		for i in range(8):
			var angle = i * TAU / 8 + randf_range(-0.2, 0.2)
			var distance = randf_range(range_data["min"], range_data["max"])
			var pos = center + Vector2(distance, 0).rotated(angle)
			
			pos.x = clamp(pos.x, world_bounds.position.x, world_bounds.end.x)
			pos.y = clamp(pos.y, world_bounds.position.y, world_bounds.end.y)
			
			spawn_zones.append(pos)

func spawn_initial_obstacles():
	var center = nest.global_position
	
	for i in range(obstacle_count):
		var angle = randf() * TAU
		var distance = randf_range(150, 500)
		var pos = center + Vector2(distance, 0).rotated(angle)
		
		pos.x = clamp(pos.x, world_bounds.position.x + 50, world_bounds.end.x - 50)
		pos.y = clamp(pos.y, world_bounds.position.y + 50, world_bounds.end.y - 50)
		
		spawn_obstacle_at(pos)

func spawn_obstacle_at(pos: Vector2, size: Vector2 = Vector2(100, 100)):
	var obstacle = obstacle_scene.instantiate() as StaticBody2D
	obstacle.global_position = pos
	
	var collision_shape = obstacle.get_node("CollisionShape2D")
	if collision_shape and collision_shape.shape:
		collision_shape.shape.size = size
	
	var sprite = obstacle.get_node("Sprite2D")
	if sprite and sprite.texture:
		sprite.texture.size = size
	
	add_child(obstacle)
	obstacles.append(obstacle)

func spawn_initial_ants():
	for i in range(initial_ant_count):
		spawn_ant()

func spawn_ant():
	if ants.size() >= max_ant_count:
		return
	
	var ant = ant_scene.instantiate() as AntAgent
	var spawn_offset = Vector2(randf_range(-40, 40), randf_range(-40, 40))
	ant.global_position = nest.global_position + spawn_offset
	ant.initialize(nest, pheromone_map)
	
	# Inherit knowledge from a dead ant (70% chance)
	if inherited_knowledge.size() > 0 and randf() < 0.7:
		var knowledge = inherited_knowledge[randi() % inherited_knowledge.size()]
		ant.inherit_knowledge(knowledge["q_table"])
		print("🧬 New ant inherits %d Q-table entries from ancestor" % knowledge["q_table"].size())
	
	add_child(ant)
	ants.append(ant)
	
	ant.tree_exiting.connect(func(): on_ant_died(ant))
	ant.food_dropped.connect(on_food_dropped)

func on_ant_died(ant: AntAgent):
	total_deaths += 1
	death_positions.append({
		"pos": ant.global_position,
		"time": simulation_time,
		"carrying_food": ant.carrying_food
	})
	
	# Store Q-table for inheritance (keep best 10)
	if ant.q_table.size() > 0:
		var knowledge = {
			"q_table": ant.q_table.duplicate(true),
			"success_streak": ant.success_streak,
			"quality_score": ant.q_table.size() * (1 + ant.success_streak * 0.1)
		}
		inherited_knowledge.append(knowledge)
		
		# Keep only top 10 Q-tables by quality
		inherited_knowledge.sort_custom(func(a, b): return a["quality_score"] > b["quality_score"])
		if inherited_knowledge.size() > 10:
			inherited_knowledge.resize(10)
		
		print("📚 Knowledge stored: Q-table size %d, streak %d (Total knowledge banks: %d)" % [
			ant.q_table.size(),
			ant.success_streak,
			inherited_knowledge.size()
		])
	
	# Keep only last 50 death positions
	if death_positions.size() > 50:
		death_positions.pop_front()
	
	print("💀 Ant died at (%.0f, %.0f) - Total deaths: %d" % [
		ant.global_position.x, 
		ant.global_position.y, 
		total_deaths
	])
	
	if ant in ants:
		ants.erase(ant)

func on_food_dropped(drop_data: Dictionary):
	# Spawn food where ant died
	var food = food_scene.instantiate() as FoodSource
	food.global_position = drop_data["position"]
	food.food_amount = drop_data.get("amount", 1)
	food.max_amount = drop_data.get("amount", 1)
	add_child(food)
	food.food_depleted.connect(func(f): on_food_depleted(f))
	food_sources.append(food)
	
	print("🍖 Food dropped at death site")

func spawn_initial_food():
	for zone_pos in spawn_zones:
		if randf() < 0.6:
			spawn_food_at(zone_pos)

func spawn_food_at(pos: Vector2):
	var food = food_scene.instantiate() as FoodSource
	food.global_position = pos
	food.food_amount = randi_range(60, 100)
	food.max_amount = food.food_amount
	food.auto_respawn = false
	food.is_infinite = false
	
	add_child(food)
	food_sources.append(food)
	food.food_depleted.connect(func(f): on_food_depleted(f))

func on_food_depleted(food: FoodSource):
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(food):
		food.queue_free()
	if food in food_sources:
		food_sources.erase(food)

func connect_signals():
	nest.food_delivered.connect(on_food_delivered)

func _input(event: InputEvent):
	if InputMap.has_action("toggle_pheromone_view") and event.is_action_pressed("toggle_pheromone_view"):
		pheromone_map.show_pheromones = !pheromone_map.show_pheromones
		print("Pheromones: ", "ON" if pheromone_map.show_pheromones else "OFF")
	
	elif InputMap.has_action("spawn_food") and event.is_action_pressed("spawn_food"):
		spawn_food_at_mouse()
	
	elif InputMap.has_action("reset_simulation") and event.is_action_pressed("reset_simulation"):
		reset_simulation()
	
	elif InputMap.has_action("quick_save") and event.is_action_pressed("quick_save"):
		print("S key pressed - saving...")
		quick_save()
	
	elif InputMap.has_action("quick_load") and event.is_action_pressed("quick_load"):
		print("L key pressed - loading...")
		quick_load()
	
	elif InputMap.has_action("save_menu") and event.is_action_pressed("save_menu"):
		print("M key pressed - listing saves...")
		show_save_menu()
	
	elif event is InputEventKey and event.pressed and event.keycode == KEY_O:
		spawn_obstacle_at_mouse()
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			spawn_food_at_mouse()

func spawn_obstacle_at_mouse():
	var mouse_pos = get_viewport().get_mouse_position()
	spawn_obstacle_at(mouse_pos)
	print("✓ Obstacle spawned at mouse")

func quick_save():
	print("Attempting to save...")
	var save_name = "quicksave"
	if SaveLoadSystem.save_simulation(self, save_name):
		print("✓ Quick saved!")
	else:
		print("✗ Save failed!")

func quick_load():
	print("Attempting to load...")
	var save_name = "quicksave"
	if SaveLoadSystem.load_simulation(self, save_name):
		print("✓ Quick loaded!")
	else:
		print("✗ Load failed - trying to recover from backup...")
		if SaveLoadSystem.recover_from_backup(save_name):
			if SaveLoadSystem.load_simulation(self, save_name):
				print("✓ Recovered and loaded from backup!")
			else:
				print("✗ Backup also corrupted")
		else:
			print("✗ No quicksave or backup found")

func save_with_name(save_name: String):
	if SaveLoadSystem.save_simulation(self, save_name):
		print("✓ Saved as: " + save_name)

func load_from_name(save_name: String):
	if SaveLoadSystem.load_simulation(self, save_name):
		print("✓ Loaded: " + save_name)
	else:
		print("✗ Failed to load: " + save_name)

func show_save_menu():
	var saves = SaveLoadSystem.list_saves()
	print("\n=== AVAILABLE SAVES ===")
	for save_name in saves:
		var info = SaveLoadSystem.get_save_info(save_name)
		print("  %s - Time: %.1fs, Ants: %d, Food: %d" % [
			save_name,
			info.get("simulation_time", 0.0),
			info.get("ant_count", 0),
			info.get("total_food_collected", 0)
		])
	print("========================\n")

func spawn_food_at_mouse():
	var mouse_pos = get_viewport().get_mouse_position()
	spawn_food_at(mouse_pos)

func _process(delta: float):
	simulation_time += delta
	
	if simulation_time >= next_spawn_time:
		consider_spawning_ant()
		next_spawn_time = simulation_time + ant_spawn_rate
	
	if simulation_time >= next_food_spawn:
		consider_spawning_food()
		next_food_spawn = simulation_time + food_spawn_interval
	
	cleanup_dead_ants()
	update_statistics()

func consider_spawning_ant():
	var active_ants = count_active_ants()
	var food_collected = nest.food_storage
	
	if active_ants < max_ant_count:
		if food_collected > active_ants * 2:
			spawn_ant()

func consider_spawning_food():
	var active_food = count_active_food()
	
	if active_food < 8:
		var random_zone = spawn_zones[randi() % spawn_zones.size()]
		var offset = Vector2(randf_range(-80, 80), randf_range(-80, 80))
		spawn_food_at(random_zone + offset)

func count_active_ants() -> int:
	var count = 0
	for ant in ants:
		if is_instance_valid(ant):
			count += 1
	return count

func count_active_food() -> int:
	var count = 0
	for food in food_sources:
		if is_instance_valid(food) and not food.depleted:
			count += 1
	return count

func cleanup_dead_ants():
	var to_remove = []
	for ant in ants:
		if not is_instance_valid(ant):
			to_remove.append(ant)
	
	for ant in to_remove:
		ants.erase(ant)

func update_statistics():
	if ui:
		var active_ants = count_active_ants()
		var active_food = count_active_food()
		
		var avg_epsilon = 0.0
		var avg_q_size = 0.0
		for ant in ants:
			if is_instance_valid(ant):
				avg_epsilon += ant.epsilon
				avg_q_size += ant.q_table.size()
		if active_ants > 0:
			avg_epsilon /= active_ants
			avg_q_size /= active_ants
		
		ui.update_statistics({
			"ants": active_ants,
			"food_collected": total_food_collected,
			"active_food": active_food,
			"total_food": food_sources.size(),
			"simulation_time": simulation_time,
			"pheromone_total": pheromone_map.get_total_pheromone(),
			"avg_epsilon": avg_epsilon,
			"avg_q_size": avg_q_size,
			"total_deaths": total_deaths
		})

func on_food_delivered(amount: int, _total: int):
	total_food_collected += amount

func reset_simulation():
	for ant in ants:
		if is_instance_valid(ant):
			ant.queue_free()
	ants.clear()
	
	for food in food_sources:
		if is_instance_valid(food):
			food.queue_free()
	food_sources.clear()
	
	for obstacle in obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	obstacles.clear()
	
	total_food_collected = 0
	simulation_time = 0.0
	next_spawn_time = 0.0
	next_food_spawn = 0.0
	
	pheromone_map.clear_all_pheromones()
	nest.food_storage = 0
	nest.update_visual()
	
	if spawn_obstacles:
		spawn_initial_obstacles()
	spawn_initial_ants()
	spawn_initial_food()
