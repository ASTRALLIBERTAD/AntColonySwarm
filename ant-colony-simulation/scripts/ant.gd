extends CharacterBody2D
class_name AntAgent

signal food_dropped(drop_data: Dictionary)

enum State { EXPLORE, EXPLOIT, RETURN }

var state: State = State.EXPLORE
var carrying_food: bool = false
var nest_ref: Node2D
var pheromone_map: PheromoneMap
var nest_pos: Vector2

var speed: float = 120.0
var rotation_speed: float = 4.0
var sensor_range: float = 70.0
var memory_size: int = 20

var q_table: Dictionary = {}
var learning_rate: float = 0.3
var discount: float = 0.85
var epsilon: float = 0.4
var epsilon_decay: float = 0.9995
var min_epsilon: float = 0.05

var local_memory: Array = []
var last_state_key: String = ""
var last_action: int = 0
var last_success_age: int = 0
var success_streak: int = 0
var failure_count: int = 0

var pheromone_strength: float = 10.0
var danger_memory: Array = []
var food_memory: Array = []

var curiosity: float = 0.5
var adaptability: float = 0.3
var energy: float = 100.0
var age: int = 0

var sensors: Array[RayCast2D] = []
const NUM_SENSORS: int = 6

@onready var sprite: Sprite2D = $Sprite2D
@onready var debug_label: Label = $DebugLabel

func _ready():
	add_to_group("ants")
	setup_sensors()
	randomize_parameters()

func setup_sensors():
	for i in range(NUM_SENSORS):
		var angle = i * TAU / NUM_SENSORS
		var ray = RayCast2D.new()
		ray.target_position = Vector2(sensor_range, 0).rotated(angle)
		ray.enabled = true
		ray.collision_mask = 2
		add_child(ray)
		sensors.append(ray)

func randomize_parameters():
	learning_rate = randf_range(0.1, 0.5)
	epsilon = randf_range(0.3, 0.6)
	curiosity = randf_range(0.2, 0.8)
	adaptability = randf_range(0.1, 0.5)
	pheromone_strength = randf_range(5.0, 15.0)

func initialize(nest_node: Node2D, pheromone_ref: PheromoneMap):
	nest_ref = nest_node
	nest_pos = nest_node.global_position
	pheromone_map = pheromone_ref

func inherit_knowledge(parent_q_table: Dictionary):
	for state in parent_q_table.keys():
		if not q_table.has(state):
			q_table[state] = parent_q_table[state].duplicate()
		else:
			for i in range(8):
				q_table[state][i] = (q_table[state][i] + parent_q_table[state][i]) / 2.0
	
	learning_rate = min(0.5, learning_rate * 1.2)
	
	epsilon = max(min_epsilon, epsilon * 0.7)
	
	print("  └─ Inherited ant: ε=%.3f (exploiting knowledge)" % epsilon)

func _physics_process(delta: float):
	age += 1
	energy -= delta * 0.3
	
	if energy <= 0:
		die()
		return
	
	epsilon = max(min_epsilon, epsilon * epsilon_decay)
	
	var perception = perceive_environment()
	var action = choose_action(perception)
	execute_action(action, delta)
	
	var reward = calculate_reward()
	learn(perception, action, reward)
	
	update_memory(perception)
	deposit_pheromones()
	
	move_and_slide()
	update_visuals()

func perceive_environment() -> Dictionary:
	var perception = {
		"obstacles": get_obstacle_distances(),
		"pheromones": sense_pheromones(),
		"food_scent": detect_food(),
		"nest_direction": get_nest_direction(),
		"energy": energy / 100.0,
		"carrying": 1.0 if carrying_food else 0.0,
		"danger_level": get_danger_proximity(),
		"time_since_success": min(age - last_success_age, 1000) / 1000.0
	}
	return perception

func get_obstacle_distances() -> Array:
	var distances = []
	for sensor in sensors:
		sensor.force_raycast_update()
		if sensor.is_colliding():
			var dist = global_position.distance_to(sensor.get_collision_point())
			distances.append(1.0 - (dist / sensor_range))
		else:
			distances.append(0.0)
	return distances

func sense_pheromones() -> Vector2:
	var grad = pheromone_map.get_pheromone_gradient(global_position)
	var strength = pheromone_map.get_pheromone(global_position)
	return grad * strength

func detect_food() -> float:
	var foods = get_tree().get_nodes_in_group("food")
	var closest_dist = sensor_range
	
	for food in foods:
		if not is_instance_valid(food) or food.depleted:
			continue
		var dist = global_position.distance_to(food.global_position)
		if dist < closest_dist:
			closest_dist = dist
			if dist < 30 and not carrying_food:
				attempt_pickup(food)
	
	return 1.0 - (closest_dist / sensor_range)

func get_nest_direction() -> Vector2:
	var to_nest = nest_pos - global_position
	return to_nest.normalized()

func get_danger_proximity() -> float:
	var min_danger_dist = 200.0
	for danger in danger_memory:
		if not danger.has("pos"):
			continue
		var danger_pos = dict_to_vector2(danger["pos"])
		var dist = global_position.distance_to(danger_pos)
		if dist < min_danger_dist:
			min_danger_dist = dist
	return 1.0 - (min_danger_dist / 200.0)

func attempt_pickup(food: Node2D) -> bool:
	if food.has_method("take_food") and food.take_food(1):
		carrying_food = true
		state = State.RETURN
		modulate = Color.ORANGE
		success_streak += 1
		last_success_age = age
		failure_count = 0
		add_to_food_memory(food.global_position)
		return true
	return false

func choose_action(perception: Dictionary) -> int:
	var state_key = encode_state(perception)
	
	if randf() < epsilon * (1.0 + curiosity):
		return randi() % 8
	
	if not q_table.has(state_key):
		q_table[state_key] = []
		for i in range(8):
			q_table[state_key].append(randf_range(-0.1, 0.1))
	
	var q_values = q_table[state_key]
	var max_q = q_values.max()
	var best_actions = []
	for i in range(q_values.size()):
		if q_values[i] >= max_q - 0.01:
			best_actions.append(i)
	
	return best_actions[randi() % best_actions.size()]

func encode_state(perception: Dictionary) -> String:
	var obstacles = perception["obstacles"]
	var phero = perception["pheromones"]
	var food = perception["food_scent"]
	var nest_dir = perception["nest_direction"]
	var danger = perception.get("danger_level", 0.0)
	var time_success = perception.get("time_since_success", 0.0)
	
	var obs_code = ""
	for obs in obstacles:
		obs_code += str(int(obs * 2))
	
	var phero_code = "%d_%d" % [int(phero.x * 3 + 3), int(phero.y * 3 + 3)]
	var food_code = int(food * 3)
	var nest_code = "%d_%d" % [int(nest_dir.x * 2 + 2), int(nest_dir.y * 2 + 2)]
	var carry_code = "1" if carrying_food else "0"
	var danger_code = int(danger * 3)
	var time_code = int(time_success * 3)
	
	return "%s_%s_%s_%s_%s_%s_%s" % [obs_code, phero_code, food_code, nest_code, carry_code, danger_code, time_code]

func execute_action(action: int, delta: float):
	var angle_offset = (action - 4) * PI / 4
	var desired_dir = Vector2.RIGHT.rotated(rotation + angle_offset)
	
	var perception = perceive_environment()
	var pheromone_influence = perception["pheromones"] * (1.0 - curiosity)
	
	if carrying_food:
		desired_dir = perception["nest_direction"]
	elif perception["food_scent"] > 0.5:
		var foods = get_tree().get_nodes_in_group("food")
		for food in foods:
			if is_instance_valid(food) and not food.depleted:
				var to_food = food.global_position - global_position
				if to_food.length() < sensor_range:
					desired_dir = to_food.normalized()
					break
	
	desired_dir = (desired_dir + pheromone_influence * 0.5).normalized()
	
	var target_angle = desired_dir.angle()
	rotation = lerp_angle(rotation, target_angle, rotation_speed * delta)
	
	velocity = Vector2.RIGHT.rotated(rotation) * speed

func calculate_reward() -> float:
	var reward = 0.0
	
	reward += 0.1
	
	if carrying_food:
		var dist_to_nest = global_position.distance_to(nest_pos)
		if dist_to_nest < 60:
			deliver_food()
			reward += 100.0
		else:
			reward += 1.0 / max(dist_to_nest, 1.0)
	
	var pheromone_strength = pheromone_map.get_pheromone(global_position)
	if not carrying_food and pheromone_strength > 1.0:
		reward += pheromone_strength * 0.1
	
	if get_slide_collision_count() > 0:
		reward -= 2.0
		add_to_danger_memory(global_position)
	
	if is_in_danger_zone():
		reward -= 5.0
	
	if energy < 30:
		reward -= 1.0
	
	return reward

func deliver_food():
	if not carrying_food:
		return
	
	carrying_food = false
	modulate = Color.WHITE
	state = State.EXPLORE
	
	if nest_ref and nest_ref.has_method("receive_food"):
		nest_ref.receive_food(1)
	
	energy = min(100.0, energy + 50.0)
	success_streak += 1
	last_success_age = age
	
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.3, 1.3), 0.1)
		tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.1)
	
	maybe_mutate()

func learn(perception: Dictionary, action: int, reward: float):
	var state_key = encode_state(perception)
	
	if not q_table.has(state_key):
		q_table[state_key] = []
		for i in range(8):
			q_table[state_key].append(0.0)
	
	var old_q = q_table[state_key][action]
	
	var max_future_q = 0.0
	if last_state_key != "":
		var future_perception = perceive_environment()
		var future_key = encode_state(future_perception)
		if q_table.has(future_key):
			max_future_q = q_table[future_key].max()
	
	var new_q = old_q + learning_rate * (reward + discount * max_future_q - old_q)
	q_table[state_key][action] = new_q
	
	last_state_key = state_key
	last_action = action
	
	if reward < -1.0:
		failure_count += 1
		if failure_count > 5:
			curiosity = min(0.9, curiosity + 0.1)
			failure_count = 0

func update_memory(perception: Dictionary):
	local_memory.append({
		"pos": global_position,
		"perception": perception,
		"time": age
	})
	
	if local_memory.size() > memory_size:
		local_memory.pop_front()

func add_to_food_memory(pos: Vector2):
	food_memory.append({"pos": pos, "time": age})
	if food_memory.size() > 10:
		food_memory.pop_front()

func add_to_danger_memory(pos: Vector2):
	danger_memory.append({"pos": pos, "time": age})
	if danger_memory.size() > 15:
		danger_memory.pop_front()
	pheromone_map.deposit_pheromone(pos, 15.0, "danger")

func is_in_danger_zone() -> bool:
	for danger in danger_memory:
		if not danger.has("pos"):
			continue
		
		var danger_pos = dict_to_vector2(danger["pos"])
		if danger_pos and global_position.distance_to(danger_pos) < 40:
			return true
	return false

func dict_to_vector2(value) -> Vector2:
	if value is Vector2:
		return value
	elif value is Dictionary:
		return Vector2(value.get("x", 0), value.get("y", 0))
	else:
		return Vector2.ZERO

func deposit_pheromones():
	if carrying_food:
		var strength = pheromone_strength * (1.0 + success_streak * 0.1)
		pheromone_map.deposit_pheromone(global_position, strength, "success")
	else:
		pheromone_map.deposit_pheromone(global_position, 0.5, "exploration")

func maybe_mutate():
	if randf() < adaptability:
		learning_rate *= randf_range(0.9, 1.1)
		epsilon *= randf_range(0.95, 1.05)
		curiosity *= randf_range(0.9, 1.1)
		pheromone_strength *= randf_range(0.95, 1.05)
		
		learning_rate = clamp(learning_rate, 0.05, 0.7)
		epsilon = clamp(epsilon, min_epsilon, 0.8)
		curiosity = clamp(curiosity, 0.1, 0.9)
		pheromone_strength = clamp(pheromone_strength, 3.0, 25.0)

func die():
	# Drop food if carrying
	if carrying_food:
		drop_food_on_death()
	
	# Leave death pheromone warning
	if pheromone_map:
		pheromone_map.deposit_pheromone(global_position, 20.0, "danger")
	
	# Visual death effect
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate:a", 0.0, 0.5)
		tween.tween_callback(queue_free)
	else:
		queue_free()

func drop_food_on_death():
	# Signal main to spawn food at death location
	var drop_data = {
		"position": global_position,
		"amount": 1
	}
	# This will be caught by main script
	emit_signal("food_dropped", drop_data)

func update_visuals():
	if debug_label:
		debug_label.text = "ε:%.2f Q:%d" % [epsilon, q_table.size()]
	
	if carrying_food:
		modulate = Color.ORANGE
	elif success_streak > 3:
		modulate = Color.YELLOW
	else:
		modulate = Color.WHITE

func _draw():
	if Engine.is_editor_hint():
		return
	
	draw_circle(Vector2.ZERO, sensor_range, Color(0, 1, 0, 0.05))
	
	for memory in local_memory:
		if not memory.has("pos"):
			continue
		
		var memory_pos = dict_to_vector2(memory["pos"])
		var local_pos = memory_pos - global_position
		if local_pos.length() < 200:
			draw_circle(local_pos, 2, Color(0.5, 0.5, 1, 0.3))

func _process(_delta):
	queue_redraw()
