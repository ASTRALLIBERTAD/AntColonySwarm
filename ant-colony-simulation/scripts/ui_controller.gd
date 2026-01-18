extends Control

@onready var stats_panel = $StatsPanel
@onready var generation_label = $StatsPanel/VBoxContainer/GenerationLabel
@onready var ants_label = $StatsPanel/VBoxContainer/AntsLabel
@onready var food_label = $StatsPanel/VBoxContainer/FoodLabel
@onready var time_label = $StatsPanel/VBoxContainer/TimeLabel
@onready var fitness_label = $StatsPanel/VBoxContainer/FitnessLabel
@onready var pheromone_label = $StatsPanel/VBoxContainer/PheromoneLabel
@onready var arduino_label = $StatsPanel/VBoxContainer/ArduinoLabel

@onready var controls_panel = $ControlsPanel
@onready var export_button = $ControlsPanel/VBoxContainer/ExportButton
@onready var send_button = $ControlsPanel/VBoxContainer/SendButton
@onready var reset_button = $ControlsPanel/VBoxContainer/ResetButton

func _ready():
	if export_button:
		export_button.pressed.connect(_on_export_pressed)
	if send_button:
		send_button.pressed.connect(_on_send_pressed)
	if reset_button:
		reset_button.pressed.connect(_on_reset_pressed)

func update_statistics(stats: Dictionary):
	if generation_label:
		generation_label.text = "Generation: %d" % stats.get("generation", 0)
	
	if ants_label:
		ants_label.text = "Ants: %d" % stats.get("ants", 0)
	
	if food_label:
		var active = stats.get("active_food", 0)
		var total = stats.get("total_food", 0)
		var collected = stats.get("food_collected", 0)
		var remaining = stats.get("food_remaining", 0)
		
		food_label.text = "Food: %d collected | %d/%d sources (%d units left)" % [
			collected,
			active,
			total,
			remaining
		]
		
		if active <= 3:
			food_label.modulate = Color.RED
		elif active <= 6:
			food_label.modulate = Color.YELLOW
		else:
			food_label.modulate = Color.WHITE
	
	if time_label:
		var time = stats.get("simulation_time", 0.0)
		var minutes = int(time / 60.0)
		var seconds = int(time) % 60
		time_label.text = "Time: %d:%02d" % [minutes, seconds]
	
	if fitness_label:
		fitness_label.text = "Best Fitness: %.1f" % stats.get("best_fitness", 0.0)
	
	if pheromone_label:
		pheromone_label.text = "Pheromone: %.0f" % stats.get("pheromone_total", 0.0)
	
	if arduino_label:
		var connected = stats.get("arduino_connected", false)
		arduino_label.text = "Arduino: %s" % ("✓ Connected" if connected else "✗ Disconnected")
		arduino_label.modulate = Color.GREEN if connected else Color.RED

func _on_export_pressed():
	get_parent().export_best_ant()

func _on_send_pressed():
	get_parent().send_to_arduino()

func _on_reset_pressed():
	get_parent().reset_simulation()
