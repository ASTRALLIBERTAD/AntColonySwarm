extends Node
class_name NeuralNetwork

var input_size: int
var hidden_size: int
var output_size: int

var weights_input_hidden: Array = []
var weights_hidden_output: Array = []
var bias_hidden: Array = []
var bias_output: Array = []

var learning_rate: float = 0.01
var last_inputs: Array = []
var last_hidden: Array = []
var last_outputs: Array = []

func _init(input_sz: int = 10, hidden_sz: int = 16, output_sz: int = 4):
	input_size = input_sz
	hidden_size = hidden_sz
	output_size = output_sz
	initialize_weights()

func initialize_weights():
	weights_input_hidden.clear()
	weights_hidden_output.clear()
	bias_hidden.clear()
	bias_output.clear()
	
	for i in range(input_size):
		var row = []
		for j in range(hidden_size):
			row.append(randf_range(-1.0, 1.0))
		weights_input_hidden.append(row)
	
	for i in range(hidden_size):
		var row = []
		for j in range(output_size):
			row.append(randf_range(-1.0, 1.0))
		weights_hidden_output.append(row)
	
	for i in range(hidden_size):
		bias_hidden.append(randf_range(-0.5, 0.5))
	
	for i in range(output_size):
		bias_output.append(randf_range(-0.5, 0.5))

func forward(inputs: Array) -> Array:
	last_inputs = inputs.duplicate()
	
	var hidden = []
	for j in range(hidden_size):
		var sum_val = bias_hidden[j]
		for i in range(input_size):
			sum_val += inputs[i] * weights_input_hidden[i][j]
		hidden.append(relu(sum_val))
	
	last_hidden = hidden.duplicate()
	
	var outputs = []
	for j in range(output_size):
		var sum_val = bias_output[j]
		for i in range(hidden_size):
			sum_val += hidden[i] * weights_hidden_output[i][j]
		outputs.append(tanh(sum_val))
	
	last_outputs = outputs.duplicate()
	return outputs

func backward(target_outputs: Array, learning_rate_multiplier: float = 1.0):
	var lr = learning_rate * learning_rate_multiplier
	
	var output_errors = []
	for i in range(output_size):
		output_errors.append(target_outputs[i] - last_outputs[i])
	
	var output_deltas = []
	for i in range(output_size):
		output_deltas.append(output_errors[i] * tanh_derivative(last_outputs[i]))
	
	var hidden_errors = []
	for i in range(hidden_size):
		var error = 0.0
		for j in range(output_size):
			error += output_deltas[j] * weights_hidden_output[i][j]
		hidden_errors.append(error)
	
	var hidden_deltas = []
	for i in range(hidden_size):
		hidden_deltas.append(hidden_errors[i] * relu_derivative(last_hidden[i]))
	
	for i in range(hidden_size):
		for j in range(output_size):
			weights_hidden_output[i][j] += lr * last_hidden[i] * output_deltas[j]
	
	for j in range(output_size):
		bias_output[j] += lr * output_deltas[j]
	
	for i in range(input_size):
		for j in range(hidden_size):
			weights_input_hidden[i][j] += lr * last_inputs[i] * hidden_deltas[j]
	
	for j in range(hidden_size):
		bias_hidden[j] += lr * hidden_deltas[j]

func relu(x: float) -> float:
	return max(0.0, x)

func relu_derivative(x: float) -> float:
	return 1.0 if x > 0.0 else 0.0

func tanh(x: float) -> float:
	return (exp(x) - exp(-x)) / (exp(x) + exp(-x))

func tanh_derivative(x: float) -> float:
	return 1.0 - x * x

func clone() -> NeuralNetwork:
	var new_brain = NeuralNetwork.new(input_size, hidden_size, output_size)
	
	for i in range(input_size):
		for j in range(hidden_size):
			new_brain.weights_input_hidden[i][j] = weights_input_hidden[i][j]
	
	for i in range(hidden_size):
		for j in range(output_size):
			new_brain.weights_hidden_output[i][j] = weights_hidden_output[i][j]
	
	for i in range(hidden_size):
		new_brain.bias_hidden[i] = bias_hidden[i]
	
	for i in range(output_size):
		new_brain.bias_output[i] = bias_output[i]
	
	return new_brain

func mutate(mutation_rate: float = 0.1, mutation_strength: float = 0.2):
	for i in range(input_size):
		for j in range(hidden_size):
			if randf() < mutation_rate:
				weights_input_hidden[i][j] += randf_range(-mutation_strength, mutation_strength)
	
	for i in range(hidden_size):
		for j in range(output_size):
			if randf() < mutation_rate:
				weights_hidden_output[i][j] += randf_range(-mutation_strength, mutation_strength)
	
	for i in range(hidden_size):
		if randf() < mutation_rate:
			bias_hidden[i] += randf_range(-mutation_strength, mutation_strength)
	
	for i in range(output_size):
		if randf() < mutation_rate:
			bias_output[i] += randf_range(-mutation_strength, mutation_strength)

func export_weights() -> Dictionary:
	return {
		"input_hidden": weights_input_hidden,
		"hidden_output": weights_hidden_output,
		"bias_hidden": bias_hidden,
		"bias_output": bias_output,
		"input_size": input_size,
		"hidden_size": hidden_size,
		"output_size": output_size
	}

func import_weights(data: Dictionary):
	if data.has("input_hidden"):
		weights_input_hidden = data["input_hidden"].duplicate(true)
	if data.has("hidden_output"):
		weights_hidden_output = data["hidden_output"].duplicate(true)
	if data.has("bias_hidden"):
		bias_hidden = data["bias_hidden"].duplicate()
	if data.has("bias_output"):
		bias_output = data["bias_output"].duplicate()
