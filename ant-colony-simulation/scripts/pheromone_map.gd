extends Node2D
class_name PheromoneMap

@export var grid_size: Vector2i = Vector2i(192, 108)
@export var cell_size: float = 10.0
@export var evaporation_rate: float = 0.003
@export var diffusion_rate: float = 0.08
@export var max_pheromone: float = 100.0
@export var show_pheromones: bool = true

var success_grid: Array = []
var danger_grid: Array = []
var exploration_grid: Array = []

var pheromone_texture: Image
var pheromone_sprite: Sprite2D

var update_counter: int = 0
var update_frequency: int = 1

func _ready():
	initialize_grids()
	setup_visualization()

func initialize_grids():
	success_grid = create_empty_grid()
	danger_grid = create_empty_grid()
	exploration_grid = create_empty_grid()

func create_empty_grid() -> Array:
	var grid = []
	for x in range(grid_size.x):
		var column = []
		for y in range(grid_size.y):
			column.append(0.0)
		grid.append(column)
	return grid

func setup_visualization():
	pheromone_texture = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_RGBA8)
	pheromone_sprite = Sprite2D.new()
	pheromone_sprite.texture = ImageTexture.create_from_image(pheromone_texture)
	pheromone_sprite.centered = false
	pheromone_sprite.scale = Vector2(cell_size, cell_size)
	add_child(pheromone_sprite)

func _process(_delta: float):
	update_counter += 1
	
	if update_counter >= update_frequency:
		update_counter = 0
		update_pheromones()
		update_visualization()

func update_pheromones():
	success_grid = process_grid(success_grid)
	danger_grid = process_grid(danger_grid)
	exploration_grid = process_grid(exploration_grid)

func process_grid(grid: Array) -> Array:
	var new_grid = create_empty_grid()
	
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var current = grid[x][y]
			
			current *= (1.0 - evaporation_rate)
			
			if current < 0.01:
				current = 0.0
			
			if current > 0.1:
				var diffusion_amount = current * diffusion_rate
				var neighbors = get_valid_neighbors(x, y)
				var amount_per_neighbor = diffusion_amount / neighbors.size()
				
				for neighbor in neighbors:
					new_grid[neighbor.x][neighbor.y] += amount_per_neighbor
				
				current -= diffusion_amount
			
			new_grid[x][y] += current
	
	return new_grid

func get_valid_neighbors(x: int, y: int) -> Array:
	var neighbors = []
	var directions = [
		Vector2i(x-1, y), Vector2i(x+1, y),
		Vector2i(x, y-1), Vector2i(x, y+1),
		Vector2i(x-1, y-1), Vector2i(x+1, y-1),
		Vector2i(x-1, y+1), Vector2i(x+1, y+1)
	]
	
	for dir in directions:
		if is_valid_grid_position(dir):
			neighbors.append(dir)
	
	return neighbors

func deposit_pheromone(world_pos: Vector2, amount: float, type: String = "success"):
	var grid_pos = world_to_grid(world_pos)
	
	if not is_valid_grid_position(grid_pos):
		return
	
	var grid = success_grid
	if type == "danger":
		grid = danger_grid
	elif type == "exploration":
		grid = exploration_grid
	
	grid[grid_pos.x][grid_pos.y] = min(
		grid[grid_pos.x][grid_pos.y] + amount,
		max_pheromone
	)

func get_pheromone(world_pos: Vector2, type: String = "success") -> float:
	var grid_pos = world_to_grid(world_pos)
	
	if not is_valid_grid_position(grid_pos):
		return 0.0
	
	var grid = success_grid
	if type == "danger":
		grid = danger_grid
	elif type == "exploration":
		grid = exploration_grid
	
	return grid[grid_pos.x][grid_pos.y]

func get_pheromone_gradient(world_pos: Vector2) -> Vector2:
	var grid_pos = world_to_grid(world_pos)
	var max_value = 0.0
	var best_dir = Vector2.ZERO
	
	var directions = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0),                   Vector2i(1, 0),
		Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1)
	]
	
	for direction in directions:
		var check_pos = grid_pos + direction
		
		if is_valid_grid_position(check_pos):
			var success_val = success_grid[check_pos.x][check_pos.y]
			var danger_val = danger_grid[check_pos.x][check_pos.y]
			var explore_val = exploration_grid[check_pos.x][check_pos.y]
			
			var total_val = success_val - danger_val * 0.5 + explore_val * 0.2
			
			if total_val > max_value:
				max_value = total_val
				best_dir = Vector2(direction.x, direction.y).normalized()
	
	return best_dir

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(world_pos.x / cell_size),
		int(world_pos.y / cell_size)
	)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * cell_size + cell_size / 2,
		grid_pos.y * cell_size + cell_size / 2
	)

func is_valid_grid_position(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_size.x and \
		   grid_pos.y >= 0 and grid_pos.y < grid_size.y

func update_visualization():
	if not show_pheromones:
		for x in range(grid_size.x):
			for y in range(grid_size.y):
				pheromone_texture.set_pixel(x, y, Color(0, 0, 0, 0))
		pheromone_sprite.texture.update(pheromone_texture)
		return
	
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var success = success_grid[x][y] / max_pheromone
			var danger = danger_grid[x][y] / max_pheromone
			var explore = exploration_grid[x][y] / max_pheromone
			
			var r = danger * 2.0
			var g = success * 1.5
			var b = explore * 2.5
			
			var total_intensity = success + danger + explore
			var alpha = min(total_intensity, 1.0) * 0.8
			
			var color = Color(r, g, b, alpha)
			pheromone_texture.set_pixel(x, y, color)
	
	pheromone_sprite.texture.update(pheromone_texture)

func clear_all_pheromones():
	success_grid = create_empty_grid()
	danger_grid = create_empty_grid()
	exploration_grid = create_empty_grid()
	update_visualization()

func get_total_pheromone() -> float:
	var total = 0.0
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			total += success_grid[x][y] + danger_grid[x][y] + exploration_grid[x][y]
	return total
