extends Control

@onready var stats_panel = $StatsPanel
@onready var generation_label = $StatsPanel/VBoxContainer/GenerationLabel
@onready var ants_label = $StatsPanel/VBoxContainer/AntsLabel
@onready var food_label = $StatsPanel/VBoxContainer/FoodLabel
@onready var time_label = $StatsPanel/VBoxContainer/TimeLabel
@onready var fitness_label = $StatsPanel/VBoxContainer/FitnessLabel
@onready var pheromone_label = $StatsPanel/VBoxContainer/PheromoneLabel
@onready var arduino_label = $StatsPanel/VBoxContainer/ArduinoLabel

func _ready():
	if arduino_label:
		arduino_label.text = "Learning: Q-Learning"

func update_statistics(stats: Dictionary):
	var ants = stats.get("ants", 0)
	var food_collected = stats.get("food_collected", 0)
	var active_food = stats.get("active_food", 0)
	var total_food = stats.get("total_food", 0)
	var time = stats.get("simulation_time", 0.0)
	var pheromone = stats.get("pheromone_total", 0.0)
	var epsilon = stats.get("avg_epsilon", 0.0)
	var q_size = stats.get("avg_q_size", 0.0)
	var deaths = stats.get("total_deaths", 0)
	
	var minutes = int(time / 60.0)
	var seconds = int(time) % 60
	
	if generation_label:
		generation_label.text = "Mode: Decentralized"
	
	if ants_label:
		ants_label.text = "Ants: %d alive | %d died" % [ants, deaths]
	
	if food_label:
		food_label.text = "Food: %d collected | %d/%d sources" % [food_collected, active_food, total_food]
		if active_food <= 3:
			food_label.modulate = Color.RED
		elif active_food <= 6:
			food_label.modulate = Color.YELLOW
		else:
			food_label.modulate = Color.WHITE
	
	if time_label:
		time_label.text = "Time: %d:%02d" % [minutes, seconds]
	
	if fitness_label:
		fitness_label.text = "Avg ε: %.3f | Q-size: %.0f" % [epsilon, q_size]
	
	if pheromone_label:
		pheromone_label.text = "Pheromone: %.0f total" % pheromone
