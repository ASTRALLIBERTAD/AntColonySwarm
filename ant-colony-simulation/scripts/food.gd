extends Area2D
class_name FoodSource

@export var food_amount: int = 100
@export var max_amount: int = 100
@export var auto_respawn: bool = false
@export var respawn_time: float = 30.0
@export var is_infinite: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = $Label
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var depleted: bool = false
var respawn_timer: float = 0.0

signal food_depleted(food_source: FoodSource)
signal food_taken(amount: int, remaining: int)

func _ready():
	add_to_group("food")
	update_visual()

func _process(delta: float):
	if depleted and auto_respawn:
		respawn_timer += delta
		if respawn_timer >= respawn_time:
			refill()

func take_food(amount: int = 1) -> bool:
	if is_infinite:
		food_taken.emit(amount, 999)
		return true
	
	if depleted or food_amount <= 0:
		return false
	
	food_amount -= amount
	food_amount = max(0, food_amount)
	
	update_visual()
	food_taken.emit(amount, food_amount)
	
	if food_amount <= 0:
		deplete()
	
	return true

func deplete():
	depleted = true
	food_amount = 0
	respawn_timer = 0.0
	update_visual()
	food_depleted.emit(self)
	
	if sprite:
		sprite.modulate = Color(0.3, 0.3, 0.3, 0.5)
	
	if not auto_respawn:
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.2, 2.0)

func refill():
	food_amount = max_amount
	depleted = false
	respawn_timer = 0.0
	modulate.a = 1.0
	update_visual()
	
	if sprite:
		sprite.scale = Vector2(1.5, 1.5)
		var tween = create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.3)

func update_visual():
	if label:
		if is_infinite:
			label.text = "∞"
		elif depleted:
			label.text = "0"
		else:
			label.text = str(food_amount)
	
	if is_infinite:
		if sprite:
			sprite.scale = Vector2(1.0, 1.0)
			sprite.modulate = Color(1, 0.8, 0, 1)
	else:
		var fill_ratio = float(food_amount) / float(max_amount) if max_amount > 0 else 0.0
		
		if sprite:
			var target_scale = 0.3 + fill_ratio * 0.7
			sprite.scale = Vector2(target_scale, target_scale)
			
			if depleted:
				sprite.modulate = Color(0.3, 0.3, 0.3, 0.5)
			else:
				var color: Color
				if fill_ratio > 0.5:
					color = Color(1.0 - fill_ratio, 1, 0)
				else:
					color = Color(1, fill_ratio * 2, 0)
				sprite.modulate = color
