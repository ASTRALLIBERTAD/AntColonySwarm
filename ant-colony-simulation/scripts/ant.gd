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
var wasted_pheromone_following: int = 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var debug_label: Label = $DebugLabel

func _ready():
	last_position = global_position
	last_stuck_position = global_position
	setup_sensors()
	setup_debug_label()
	add_to_group("ants")

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
	
	var movement = global_position.distance_to(last_position)
	distance_traveled += movement
	
	if movement < 1.0:  
		stuck_timer += delta
		if stuck_timer > 3.0:  
			times_stuck += 1
			stuck_timer = 0.0
			print("[ANT] Got stuck! Total stuck events: %d" % times_stuck)
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
				
				pheromone_deposit_rate = min(pheromone_deposit_rate * 1.05, 15.0)
				
				print("[ANT] ✓ Picked up food! Total: %d" % (food_collected + 1))
				return true
			else:
				failed_food_attempts += 1
				print("[ANT] ✗ Failed to get food (depleted)")
				return false
	
	return false

func wander_behavior(delta: float):
	# Check for food
	var food = find_closest_food()
	if food:
		try_pickup_food()
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
	
	var swarm_pull = get_swarm_cohesion()
	
	var forward = Vector2.RIGHT.rotated(rotation)
	var random = Vector2.from_angle(randf() * TAU) * exploration_randomness
	var obstacle_avoid = get_obstacle_avoidance()
	
	var desired_direction = (
		forward + 
		random + 
		swarm_pull * 2.0 +  
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
		print("[ANT] ✗ Target food depleted")
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
	
	print("[ANT] ✓ Delivered food! Total: %d" % food_collected)
	
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

func get_fitness() -> float:
	var fitness = 0.0
	
	fitness += food_collected * 10000.0  
	
	if food_collected > 0:
		var efficiency = food_collected / max(distance_traveled, 1.0)
		fitness += efficiency * 5000.0
	
	fitness += successful_returns * 2000.0
	
	fitness -= collision_count * 10.0
	if collision_count > 50:
		fitness -= 500.0  
	
	fitness -= times_stuck * 200.0
	
	fitness -= failed_food_attempts * 150.0
	
	if food_collected == 0:
		if time_alive > 60.0:
			fitness -= 1000.0  
		if time_alive > 90.0:
			fitness -= 2000.0  
	
	if distance_traveled > 5000.0 and food_collected == 0:
		fitness -= 1500.0
	
	if food_collected > 0:
		var time_per_food = time_alive / food_collected
		if time_per_food > 40.0:  
			fitness -= (time_per_food - 40.0) * 10.0
	
	var survival_bonus = min(time_alive, 120.0) * 0.1  
	fitness += survival_bonus
	
	if not has_food:
		var dist_to_nest = global_position.distance_to(nest_position)
		if dist_to_nest < 100:
			fitness += 50.0
	
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
		match current_state:
			State.WANDERING:
				debug_label.text = "Search"
			State.GOING_TO_FOOD:
				debug_label.text = "→Food"
			State.CARRYING_FOOD, State.GOING_TO_NEST:
				debug_label.text = "→Nest"
		
		debug_label.text += "\nF:%d C:%d" % [food_collected, collision_count]

	if has_food:
		modulate = Color.ORANGE
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
func get_swarm_cohesion() -> Vector2:
	"""Move toward nearby ants for swarm behavior"""
	if not follow_other_ants:
		return Vector2.ZERO
	
	var nearby_ants = get_tree().get_nodes_in_group("ants")
	var cohesion = Vector2.ZERO
	var count = 0
	
	for ant in nearby_ants:
		if ant == self or not is_instance_valid(ant):
			continue
		
		var distance = global_position.distance_to(ant.global_position)
		
		# Follow ants that have food or are nearby
		if distance < ant_detection_range:
			var to_ant = ant.global_position - global_position
			
			# Stronger attraction to ants with food
			if ant.has_food:
				cohesion += to_ant.normalized() * 2.0
			else:
				cohesion += to_ant.normalized()
			count += 1
	
	if count > 0:
		return (cohesion / count).normalized() * ant_attraction_strength
	
	return Vector2.ZERO

func _process(_delta):
	queue_redraw()
