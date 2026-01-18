extends CharacterBody2D
class_name AntAgent

enum State {
	WANDERING,
	GOING_TO_FOOD,
	CARRYING_FOOD,
	GOING_TO_NEST
}

var current_state: State = State.WANDERING
var has_food: bool = false
var target_food: Node2D = null
var target_position: Vector2 = Vector2.ZERO

var nest: Node2D
var pheromone_map: PheromoneMap
var nest_position: Vector2

@export var follow_other_ants: bool = true
@export var ant_attraction_strength: float = 0.5
@export var ant_detection_range: float = 150.0
@export var communication_range: float = 300.0

@export var max_speed: float = 150.0
@export var turn_speed: float = 5.0
@export var wander_radius: float = 300.0

@export var food_detection_range: float = 80.0
@export var nest_detection_range: float = 60.0
@export var pheromone_follow_strength: float = 2.0
@export var pheromone_deposit_rate: float = 10.0
@export var exploration_randomness: float = 0.4

var sensors: Array[RayCast2D] = []
const NUM_SENSORS: int = 8

var food_collected: int = 0
var successful_returns: int = 0
var time_alive: float = 0.0
var distance_traveled: float = 0.0
var last_position: Vector2

var collision_count: int = 0
var stuck_timer: float = 0.0
var last_stuck_position: Vector2 = Vector2.ZERO
var times_stuck: int = 0
var failed_food_attempts: int = 0
var exploration_coverage: float = 0.0
var visited_positions: Array = []
var revisit_count: int = 0
var position_history: Array = []
var history_check_interval: float = 0.0

var found_food_signal: bool = false
var signal_timer: float = 0.0
var signal_duration: float = 5.0
var food_location: Vector2 = Vector2.ZERO

@export var enable_sector_search: bool = true
@export var enable_grid_search: bool = true
var assigned_sector: int = 0
var sector_bias_strength: float = 1.5

var current_target_tile: Vector2i = Vector2i(-1, -1)
var tile_search_radius: float = 80.0
var time_in_current_tile: float = 0.0
var tile_search_duration: float = 5.0

var search_tile_size: float = 100.0
var search_target_tile: Vector2i = Vector2i.ZERO
var tiles_searched: int = 0
var current_search_strategy: int = 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var debug_label: Label = $DebugLabel

func _ready():
	last_position = global_position
	last_stuck_position = global_position
	setup_sensors()
	setup_debug_label()
	add_to_group("ants")
	
	await get_tree().process_frame
	var all_ants = get_tree().get_nodes_in_group("ants")
	assigned_sector = (all_ants.find(self)) % 8

func setup_sensors():
	for i in range(NUM_SENSORS):
		var angle = i * TAU / NUM_SENSORS
		var ray = RayCast2D.new()
		ray.target_position = Vector2(60, 0).rotated(angle)
		ray.enabled = true
		ray.collision_mask = 2
		add_child(ray)
		sensors.append(ray)

func setup_debug_label():
	if not debug_label:
		debug_label = Label.new()
		add_child(debug_label)
		debug_label.position = Vector2(-30, -40)
		debug_label.add_theme_font_size_override("font_size", 10)

func initialize(nest_ref: Node2D, pheromone_ref: PheromoneMap):
	nest = nest_ref
	nest_position = nest.global_position
	pheromone_map = pheromone_ref

func _physics_process(delta: float):
	time_alive += delta
	history_check_interval += delta
	time_in_current_tile += delta
	
	if found_food_signal:
		signal_timer += delta
		if signal_timer >= signal_duration:
			found_food_signal = false
			signal_timer = 0.0
	
	var movement = global_position.distance_to(last_position)
	distance_traveled += movement
	
	track_exploration()
	detect_circling()
	
	if movement < 1.0:
		stuck_timer += delta
		if stuck_timer > 3.0:
			times_stuck += 1
			stuck_timer = 0.0
			var escape_direction = Vector2.from_angle(randf() * TAU)
			velocity = escape_direction * max_speed * 0.5
	else:
		stuck_timer = 0.0
	
	last_position = global_position
	
	if get_slide_collision_count() > 0:
		collision_count += 1
	
	if not has_food:
		var nearby_food = find_closest_food()
		if nearby_food:
			target_food = nearby_food
			current_state = State.GOING_TO_FOOD
	
	match current_state:
		State.WANDERING:
			wander_behavior(delta)
		State.GOING_TO_FOOD:
			go_to_food_behavior(delta)
		State.CARRYING_FOOD:
			go_to_nest_behavior(delta)
		State.GOING_TO_NEST:
			go_to_nest_behavior(delta)
	
	move_and_slide()
	update_visuals()

func track_exploration():
	var grid_size = 100.0
	var grid_pos = Vector2i(int(global_position.x / grid_size), int(global_position.y / grid_size))
	
	if not visited_positions.has(grid_pos):
		visited_positions.append(grid_pos)
		exploration_coverage = visited_positions.size()

func detect_circling():
	if history_check_interval < 2.0:
		return
	
	history_check_interval = 0.0
	
	position_history.append(global_position)
	
	if position_history.size() > 10:
		position_history.pop_front()
	
	if position_history.size() >= 6:
		var current_pos = global_position
		var avg_distance_from_history = 0.0
		
		for pos in position_history:
			avg_distance_from_history += current_pos.distance_to(pos)
		
		avg_distance_from_history /= position_history.size()
		
		if avg_distance_from_history < 150.0:
			revisit_count += 1

func find_closest_food() -> Node2D:
	var food_sources = get_tree().get_nodes_in_group("food")
	var closest_food: Node2D = null
	var closest_distance: float = food_detection_range
	
	for food in food_sources:
		if not is_instance_valid(food):
			continue
		
		if food.depleted:
			continue
		
		if food.food_amount <= 0:
			continue
		
		var distance = global_position.distance_to(food.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_food = food
	
	return closest_food

func try_pickup_food() -> bool:
	if not target_food or not is_instance_valid(target_food):
		failed_food_attempts += 1
		return false
	
	var distance = global_position.distance_to(target_food.global_position)
	
	if distance < 30:
		if target_food.has_method("take_food"):
			var success = target_food.take_food(1)
			if success:
				has_food = true
				current_state = State.CARRYING_FOOD
				modulate = Color.ORANGE
				
				pheromone_deposit_rate = min(pheromone_deposit_rate * 1.05, 20.0)
				
				broadcast_food_found(target_food.global_position)
				
				return true
			else:
				failed_food_attempts += 1
				return false
	
	return false

func wander_behavior(delta: float):
	var food = find_closest_food()
	if food:
		if try_pickup_food():
			return
	
	var food_signal_direction = check_nearby_food_signals()
	
	if food_signal_direction != Vector2.ZERO:
		var target_angle = food_signal_direction.angle()
		rotation = lerp_angle(rotation, target_angle, turn_speed * delta * 2.0)
		velocity = Vector2.RIGHT.rotated(rotation) * max_speed * 1.2
		return
	
	var pheromone_direction = pheromone_map.get_pheromone_gradient(global_position)
	var pheromone_strength = pheromone_map.get_pheromone(global_position)
	
	if pheromone_strength > 0.5:
		var forward = Vector2.RIGHT.rotated(rotation)
		var desired_direction = (forward + pheromone_direction * pheromone_follow_strength).normalized()
		var target_angle = desired_direction.angle()
		rotation = lerp_angle(rotation, target_angle, turn_speed * delta)
		velocity = Vector2.RIGHT.rotated(rotation) * max_speed
		return
	
	var grid_tile_direction = get_grid_tile_target()
	var sector_direction = get_sector_direction()
	var swarm_pull = get_swarm_cohesion()
	var forward = Vector2.RIGHT.rotated(rotation)
	
	var random = Vector2.from_angle(randf() * TAU) * exploration_randomness
	
	var away_from_nest = Vector2.ZERO
	var dist_to_nest = global_position.distance_to(nest_position)
	if dist_to_nest < 200 and randf() < 0.3:
		away_from_nest = (global_position - nest_position).normalized() * 0.5
	
	var obstacle_avoid = get_obstacle_avoidance()
	
	var desired_direction = (
		forward + 
		random +
		grid_tile_direction * 3.0 +
		sector_direction * sector_bias_strength +
		swarm_pull * 1.0 +
		away_from_nest +
		obstacle_avoid
	).normalized()
	
	var target_angle = desired_direction.angle()
	rotation = lerp_angle(rotation, target_angle, turn_speed * delta)
	velocity = Vector2.RIGHT.rotated(rotation) * max_speed

func go_to_food_behavior(delta: float):
	if not target_food or not is_instance_valid(target_food):
		current_state = State.WANDERING
		return
	
	if target_food.depleted:
		failed_food_attempts += 1
		target_food = null
		current_state = State.WANDERING
		return
	
	if try_pickup_food():
		return
	
	var to_food = target_food.global_position - global_position
	var desired_direction = to_food.normalized()
	var obstacle_avoid = get_obstacle_avoidance()
	
	desired_direction = (desired_direction * 3.0 + obstacle_avoid).normalized()
	
	var target_angle = desired_direction.angle()
	rotation = lerp_angle(rotation, target_angle, turn_speed * delta * 1.5)
	
	velocity = Vector2.RIGHT.rotated(rotation) * max_speed * 1.3

func go_to_nest_behavior(delta: float):
	pheromone_map.deposit_pheromone(global_position, pheromone_deposit_rate * delta * 60.0)
	
	var distance_to_nest = global_position.distance_to(nest_position)
	
	if distance_to_nest < nest_detection_range:
		deliver_food()
		return
	
	var to_nest = nest_position - global_position
	var desired_direction = to_nest.normalized()
	var obstacle_avoid = get_obstacle_avoidance()
	
	desired_direction = (desired_direction * 3.0 + obstacle_avoid).normalized()
	
	var target_angle = desired_direction.angle()
	rotation = lerp_angle(rotation, target_angle, turn_speed * delta * 2.0)
	
	velocity = Vector2.RIGHT.rotated(rotation) * max_speed * 1.5

func deliver_food():
	if not has_food:
		return
	
	has_food = false
	food_collected += 1
	successful_returns += 1
	
	if nest and nest.has_method("receive_food"):
		nest.receive_food(1)
	
	current_state = State.WANDERING
	target_food = null
	modulate = Color.WHITE
	
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.5, 1.5), 0.1)
		tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.1)

func get_obstacle_avoidance() -> Vector2:
	var avoidance = Vector2.ZERO
	
	for i in range(NUM_SENSORS):
		var ray = sensors[i]
		ray.force_raycast_update()
		
		if ray.is_colliding():
			var collision_point = ray.get_collision_point()
			var distance = global_position.distance_to(collision_point)
			var strength = 1.0 - (distance / 60.0)
			
			var away_direction = (global_position - collision_point).normalized()
			avoidance += away_direction * strength * 2.0
	
	return avoidance

func get_swarm_cohesion() -> Vector2:
	if not follow_other_ants:
		return Vector2.ZERO
	
	var nearby_ants = get_tree().get_nodes_in_group("ants")
	var cohesion = Vector2.ZERO
	var count = 0
	
	for ant in nearby_ants:
		if ant == self or not is_instance_valid(ant):
			continue
		
		var distance = global_position.distance_to(ant.global_position)
		
		if distance < ant_detection_range:
			var to_ant = ant.global_position - global_position
			
			if ant.has_food:
				cohesion += to_ant.normalized() * 2.0
			else:
				cohesion += to_ant.normalized()
			count += 1
	
	if count > 0:
		return (cohesion / count).normalized() * ant_attraction_strength
	
	return Vector2.ZERO

func broadcast_food_found(location: Vector2):
	found_food_signal = true
	food_location = location
	signal_timer = 0.0

func check_nearby_food_signals() -> Vector2:
	if has_food or current_state == State.GOING_TO_FOOD:
		return Vector2.ZERO
	
	var nearby_ants = get_tree().get_nodes_in_group("ants")
	var closest_signal_location = Vector2.ZERO
	var closest_distance = 999999.0
	
	for ant in nearby_ants:
		if ant == self or not is_instance_valid(ant):
			continue
		
		if not ant.found_food_signal:
			continue
		
		var distance_to_ant = global_position.distance_to(ant.global_position)
		
		if distance_to_ant < communication_range:
			var distance_to_food = global_position.distance_to(ant.food_location)
			if distance_to_food < closest_distance:
				closest_distance = distance_to_food
				closest_signal_location = ant.food_location
	
	if closest_signal_location != Vector2.ZERO:
		return (closest_signal_location - global_position).normalized()
	
	return Vector2.ZERO

func get_sector_direction() -> Vector2:
	if not enable_sector_search:
		return Vector2.ZERO
	
	var sector_angle = assigned_sector * (TAU / 8.0)
	return Vector2.from_angle(sector_angle)

func get_grid_tile_target() -> Vector2:
	if not enable_grid_search:
		return Vector2.ZERO
	
	if time_in_current_tile >= tile_search_duration or current_target_tile == Vector2i(-1, -1):
		current_target_tile = get_next_unsearched_tile()
		time_in_current_tile = 0.0
		
		if current_target_tile != Vector2i(-1, -1):
			var main = get_node("/root/Node2D")
			if main and main.has_method("mark_tile_being_searched"):
				main.mark_tile_being_searched(current_target_tile)
	
	if current_target_tile != Vector2i(-1, -1):
		var tile_center = tile_to_world(current_target_tile)
		var to_tile = tile_center - global_position
		
		if to_tile.length() < tile_search_radius:
			return Vector2.ZERO
		
		return to_tile.normalized()
	
	return Vector2.ZERO

func get_next_unsearched_tile() -> Vector2i:
	var main = get_node("/root/Node2D")
	if not main or not main.has_method("get_unsearched_tile"):
		return Vector2i(-1, -1)
	
	return main.get_unsearched_tile(global_position, assigned_sector)

func tile_to_world(tile: Vector2i) -> Vector2:
	var tile_size = 150.0
	return Vector2(tile.x * tile_size + tile_size / 2, tile.y * tile_size + tile_size / 2)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	var tile_size = 150.0
	return Vector2i(int(world_pos.x / tile_size), int(world_pos.y / tile_size))

func get_fitness() -> float:
	var fitness = 0.0
	
	fitness += food_collected * 15000.0
	
	if food_collected > 0:
		var efficiency = food_collected / max(distance_traveled, 1.0)
		fitness += efficiency * 8000.0
		
		var time_per_food = time_alive / food_collected
		if time_per_food < 30.0:
			fitness += (30.0 - time_per_food) * 100.0
	
	fitness += successful_returns * 3000.0
	
	fitness += exploration_coverage * 50.0
	
	fitness -= collision_count * 10.0
	if collision_count > 100:
		fitness -= 500.0
	
	fitness -= times_stuck * 200.0
	
	fitness -= failed_food_attempts * 100.0
	
	fitness -= revisit_count * 150.0
	if revisit_count > 10:
		fitness -= 1000.0
	
	if food_collected == 0:
		if time_alive > 60.0:
			fitness -= 1500.0
		if time_alive > 90.0:
			fitness -= 3000.0
		
		if revisit_count > 15:
			fitness -= 2000.0
	
	var survival_bonus = min(time_alive, 120.0) * 0.5
	fitness += survival_bonus
	
	if not has_food:
		var dist_to_nest = global_position.distance_to(nest_position)
		if dist_to_nest < 100:
			fitness += 100.0
	
	if food_collected >= 2:
		fitness += pow(food_collected, 1.5) * 1000.0
	
	return max(0.0, fitness)

func export_brain_data() -> Dictionary:
	return {
		"fitness": get_fitness(),
		"food_collected": food_collected,
		"successful_returns": successful_returns,
		"distance_traveled": distance_traveled,
		"time_alive": time_alive,
		"collisions": collision_count,
		"times_stuck": times_stuck,
		"failed_attempts": failed_food_attempts,
		"exploration_coverage": exploration_coverage,
		"revisit_count": revisit_count,
		"traits": {
			"food_detection_range": food_detection_range,
			"pheromone_follow_strength": pheromone_follow_strength,
			"pheromone_deposit_rate": pheromone_deposit_rate,
			"exploration_randomness": exploration_randomness,
			"max_speed": max_speed,
			"turn_speed": turn_speed
		}
	}

func import_brain_data(data: Dictionary):
	if data.has("traits"):
		var traits = data["traits"]
		food_detection_range = traits.get("food_detection_range", food_detection_range)
		pheromone_follow_strength = traits.get("pheromone_follow_strength", pheromone_follow_strength)
		pheromone_deposit_rate = traits.get("pheromone_deposit_rate", pheromone_deposit_rate)
		exploration_randomness = traits.get("exploration_randomness", exploration_randomness)
		max_speed = traits.get("max_speed", max_speed)
		turn_speed = traits.get("turn_speed", turn_speed)

func update_visuals():
	if debug_label:
		var sector_names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
		var sector_name = sector_names[assigned_sector]
		
		match current_state:
			State.WANDERING:
				debug_label.text = "S%s" % sector_name
			State.GOING_TO_FOOD:
				debug_label.text = "→Food"
			State.CARRYING_FOOD, State.GOING_TO_NEST:
				debug_label.text = "→Nest"
		
		if found_food_signal:
			debug_label.text += " 📡"
		
		debug_label.text += "\nF:%d T:%d" % [food_collected, current_target_tile.x if current_target_tile.x >= 0 else 0]

	if has_food:
		modulate = Color.ORANGE
	elif found_food_signal:
		modulate = Color.CYAN
	else:
		match current_state:
			State.WANDERING:
				modulate = Color.WHITE
			State.GOING_TO_FOOD:
				modulate = Color.YELLOW

func _draw():
	if Engine.is_editor_hint():
		return

	draw_circle(Vector2.ZERO, food_detection_range, Color(0, 1, 0, 0.05))

	var nearby_ants = get_tree().get_nodes_in_group("ants")
	for ant in nearby_ants:
		if ant == self or not is_instance_valid(ant):
			continue
		
		var distance = global_position.distance_to(ant.global_position)
		if distance < ant_detection_range:
			var to_ant = ant.global_position - global_position
			var color = Color(0, 0.5, 1, 0.2) if ant.has_food else Color(1, 1, 1, 0.1)
			draw_line(Vector2.ZERO, to_ant, color, 1.0)

	if target_food and is_instance_valid(target_food):
		var to_food = target_food.global_position - global_position
		draw_line(Vector2.ZERO, to_food, Color.GREEN, 2.0)
	
	if has_food:
		var to_nest = nest_position - global_position
		draw_line(Vector2.ZERO, to_nest, Color.ORANGE, 2.0)
	
	if found_food_signal:
		draw_circle(Vector2.ZERO, communication_range, Color(0, 1, 1, 0.1))
		for ant in nearby_ants:
			if ant == self or not is_instance_valid(ant):
				continue
			var distance = global_position.distance_to(ant.global_position)
			if distance < communication_range and not ant.has_food:
				var to_ant = ant.global_position - global_position
				draw_line(Vector2.ZERO, to_ant, Color.CYAN, 2.0)

func _process(_delta):
	queue_redraw()
