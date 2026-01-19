extends Node
class_name ExperienceReplay

var memory: Array = []
var max_memory_size: int = 1000
var batch_size: int = 32

class Experience:
	var state: Array
	var action: Array
	var reward: float
	var next_state: Array
	var done: bool
	
	func _init(s: Array, a: Array, r: float, ns: Array, d: bool):
		state = s
		action = a
		reward = r
		next_state = ns
		done = d

func add_experience(state: Array, action: Array, reward: float, next_state: Array, done: bool):
	var experience = Experience.new(state, action, reward, next_state, done)
	memory.append(experience)
	
	if memory.size() > max_memory_size:
		memory.pop_front()

func sample_batch() -> Array:
	if memory.size() < batch_size:
		return memory.duplicate()
	
	var batch = []
	var indices = []
	
	for i in range(batch_size):
		var idx = randi() % memory.size()
		while indices.has(idx):
			idx = randi() % memory.size()
		indices.append(idx)
		batch.append(memory[idx])
	
	return batch

func get_memory_size() -> int:
	return memory.size()

func clear():
	memory.clear()
