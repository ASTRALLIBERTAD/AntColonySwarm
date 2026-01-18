extends Area2D
class_name Nest

@export var food_storage: int = 0
@export var max_capacity: int = 1000

@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = $Label
@onready var collection_particles: CPUParticles2D = $CollectionParticles

signal food_delivered(amount: int, total: int)

func _ready():
	add_to_group("nests")
	update_visual()

func receive_food(amount: int):
	food_storage = min(food_storage + amount, max_capacity)
	update_visual()
	if collection_particles:
		collection_particles.emitting = true
	
	food_delivered.emit(amount, food_storage)
	
	sprite.scale = Vector2(1.2, 1.2)
	var tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.2)

func update_visual():
	if label:
		label.text = "Food: %d" % food_storage
	
	var fill_ratio = float(food_storage) / float(max_capacity)
	sprite.modulate = Color(1.0 - fill_ratio * 0.5, 1.0, 1.0 - fill_ratio * 0.5)

func get_position_for_ant() -> Vector2:
	var angle = randf() * TAU
	var distance = randf_range(20, 40)
	return global_position + Vector2(distance, 0).rotated(angle)
