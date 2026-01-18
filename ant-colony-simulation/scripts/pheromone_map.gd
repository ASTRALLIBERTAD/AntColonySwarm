extends Node2D
class_name PheromoneMap

@export var grid_size: Vector2i = Vector2i(192, 108)  
@export var cell_size: float = 10.0

@export var evaporation_rate: float = 0.002
@export var diffusion_rate: float = 0.05
@export var max_pheromone: float = 100.0

@export var show_pheromones: bool = true
@export var pheromone_color: Color = Color(0, 1, 0, 0.8)

var pheromone_grid: Array = []
var pheromone_texture: Image
var pheromone_sprite: Sprite2D

var update_counter: int = 0
var update_frequency: int = 2 

signal pheromone_deposited(position: Vector2, amount: float)

func _ready():
	initialize_grid()
	setup_visualization()

func initialize_grid():
	pheromone_grid.clear()
	for x in range(grid_size.x):
		var column = []
		for y in range(grid_size.y):
			column.append(0.0)
		pheromone_grid.append(column)
	
	print("Pheromone grid initialized: ", grid_size)

func setup_visualization():
	# Create sprite for pheromone visualization
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
		evaporate_and_diffuse()
		
		if show_pheromones:
			update_visualization()

func evaporate_and_diffuse():
	# Create temporary grid for diffusion calculations
	var new_grid = []
	for x in range(grid_size.x):
		var column = []
		for y in range(grid_size.y):
			column.append(0.0)
		new_grid.append(column)
	
	# Process each cell
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var current = pheromone_grid[x][y]
			
			# Evaporation
			current *= (1.0 - evaporation_rate)
			
			if current < 0.01:
				current = 0.0  # Complete evaporation
			
			# Diffusion to neighbors
			if current > 0.1:
				var diffusion_amount = current * diffusion_rate
				var neighbors = get_valid_neighbors(x, y)
				var amount_per_neighbor = diffusion_amount / neighbors.size()
				
				for neighbor in neighbors:
					new_grid[neighbor.x][neighbor.y] += amount_per_neighbor
				
				current -= diffusion_amount
			
			new_grid[x][y] += current
	
	# Apply new grid
	pheromone_grid = new_grid

func get_valid_neighbors(x: int, y: int) -> Array:
	var neighbors = []
	var directions = [
		Vector2i(x - 1, y), Vector2i(x + 1, y),
		Vector2i(x, y - 1), Vector2i(x, y + 1)
	]
	
	for dir in directions:
		if is_valid_grid_position(dir):
			neighbors.append(dir)
	
	return neighbors

func deposit_pheromone(world_pos: Vector2, amount: float):
	var grid_pos = world_to_grid(world_pos)
	
	if is_valid_grid_position(grid_pos):
		pheromone_grid[grid_pos.x][grid_pos.y] = min(
			pheromone_grid[grid_pos.x][grid_pos.y] + amount,
			max_pheromone
		)
		pheromone_deposited.emit(world_pos, amount)

func get_pheromone(world_pos: Vector2) -> float:
	var grid_pos = world_to_grid(world_pos)
	
	if is_valid_grid_position(grid_pos):
		return pheromone_grid[grid_pos.x][grid_pos.y]
	return 0.0

func get_pheromone_gradient(world_pos: Vector2) -> Vector2:
	# Returns direction of strongest pheromone (for ant to follow)
	var grid_pos = world_to_grid(world_pos)
	var max_pheromone_value = 0.0
	var best_direction = Vector2.ZERO
	
	# Check 8 surrounding cells
	var directions = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0),                   Vector2i(1, 0),
		Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1)
	]
	
	for direction in directions:
		var check_pos = grid_pos + direction
		
		if is_valid_grid_position(check_pos):
			var pheromone_value = pheromone_grid[check_pos.x][check_pos.y]
			
			if pheromone_value > max_pheromone_value:
				max_pheromone_value = pheromone_value
				best_direction = Vector2(direction.x, direction.y).normalized()
	
	return best_direction

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(world_pos.x / cell_size),
		int(world_pos.y / cell_size)
	)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * cell_size + cell_size / 2, 
				   grid_pos.y * cell_size + cell_size / 2)

func is_valid_grid_position(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_size.x and \
		   grid_pos.y >= 0 and grid_pos.y < grid_size.y

func update_visualization():
	# Update texture to show pheromones
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var intensity = pheromone_grid[x][y] / max_pheromone
			var color = Color(0, intensity, 0, intensity * 0.8)  # Green with alpha
			pheromone_texture.set_pixel(x, y, color)
	
	pheromone_sprite.texture.update(pheromone_texture)

func clear_all_pheromones():
	initialize_grid()
	update_visualization()

func get_total_pheromone() -> float:
	var total = 0.0
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			total += pheromone_grid[x][y]
	return total
