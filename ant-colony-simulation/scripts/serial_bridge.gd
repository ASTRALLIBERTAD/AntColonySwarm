extends Node
class_name SerialBridge

var serial_port
var port_name: String = ""
var baud_rate: int = 9600

var is_connected: bool = false
var connection_attempts: int = 0
var max_connection_attempts: int = 3

var receive_buffer: String = ""
var send_queue: Array[Dictionary] = []

var update_interval: float = 0.1 
var update_timer: float = 0.0

signal connection_established
signal connection_lost
signal data_received(data: Dictionary)
signal weights_sent_successfully
signal error_occurred(error_message: String)

func _ready():
	if not ClassDB.class_exists("SerialPort"):
		print("⚠ GDSerial plugin not found!")
		print("Please install GDSerial from AssetLib:")
		print("1. Click AssetLib at top of Godot")
		print("2. Search for 'GDSerial'")
		print("3. Download and Install")
		print("4. Enable in Project → Project Settings → Plugins")
		error_occurred.emit("GDSerial plugin not installed")
		return
	detect_and_connect()

func detect_and_connect():
	var SerialPort = GdSerial.new()
	var available_ports = SerialPort.list_ports()
	print("Available serial ports: ", available_ports)
	
	if available_ports.size() == 0:
		print("No serial ports found. Arduino not connected?")
		error_occurred.emit("No serial ports available")
		return
	for port in available_ports:
		if "Arduino" in port or "USB" in port or "ACM" in port or "ttyUSB" in port:
			port_name = port
			break
	
	if port_name == "":
		port_name = available_ports[0]
	
	connect_to_port(port_name)

func connect_to_port(port: String):
	port_name = port
	serial_port = GdSerial.new()
	
	var err = serial_port.open(port_name, baud_rate)
	
	if err == OK:
		is_connected = true
		connection_attempts = 0
		print("✓ Connected to Arduino on ", port_name)
		connection_established.emit()
		
		await get_tree().create_timer(2.0).timeout
		send_handshake()
	else:
		is_connected = false
		connection_attempts += 1
		print("✗ Failed to connect to ", port_name, " - Error: ", err)
		error_occurred.emit("Connection failed: " + str(err))
		
		if connection_attempts < max_connection_attempts:
			print("Retrying in 2 seconds...")
			await get_tree().create_timer(2.0).timeout
			detect_and_connect()

func disconnect_arduino():
	if serial_port and is_connected:
		serial_port.close()
		is_connected = false
		connection_lost.emit()
		print("Disconnected from Arduino")

func _process(delta: float):
	if not is_connected or not serial_port:
		return
	
	read_from_arduino()
	update_timer += delta
	if update_timer >= update_interval and send_queue.size() > 0:
		update_timer = 0.0
		send_next_in_queue()

func read_from_arduino():
	var available = serial_port.get_available()
	
	if available > 0:
		var data = serial_port.read(available)
		var text = data.get_string_from_utf8()
		receive_buffer += text
		
		while "\n" in receive_buffer:
			var line_end = receive_buffer.find("\n")
			var line = receive_buffer.substr(0, line_end).strip_edges()
			receive_buffer = receive_buffer.substr(line_end + 1)
			
			if line.length() > 0:
				parse_arduino_message(line)

func parse_arduino_message(message: String):
	var json = JSON.new()
	var parse_result = json.parse(message)
	
	if parse_result == OK:
		var data = json.data
		
		if typeof(data) == TYPE_DICTIONARY:
			handle_json_message(data)
		else:
			print("Arduino (invalid JSON): ", message)
	else:
		print("Arduino: ", message)

func handle_json_message(data: Dictionary):
	if not data.has("type"):
		return
	
	match data["type"]:
		"ready":
			print("✓ Arduino is ready")
		"sensor_data":
			data_received.emit(data)
		"weights_loaded":
			print("✓ Arduino loaded neural weights")
			weights_sent_successfully.emit()
		"food_found":
			print("✓ Arduino ant found food!")
		"returned_to_nest":
			print("✓ Arduino ant returned to nest")
		"error":
			print("✗ Arduino error: ", data.get("message", "Unknown"))
			error_occurred.emit(data.get("message", "Unknown error"))
		"status":
			print("Arduino status: ", data.get("message", ""))
		_:
			print("Unknown message type from Arduino: ", data["type"])

func send_handshake():
	send_message({
		"type": "handshake",
		"version": "1.0",
		"timestamp": Time.get_ticks_msec()
	})

func send_ant_behavior_data(ant_data: Dictionary):
	send_message({
		"type": "behavior",
		"data": ant_data
	})

func send_pheromone_data(positions: Array, strengths: Array):
	send_message({
		"type": "pheromones",
		"positions": positions,
		"strengths": strengths
	})

func send_command(command: String, params: Dictionary = {}):
	var message = {
		"type": "command",
		"cmd": command
	}
	message.merge(params)
	send_message(message)

func send_led_pattern(pattern: String, color: Color = Color.WHITE):
	send_command("set_leds", {
		"pattern": pattern,
		"r": int(color.r * 255),
		"g": int(color.g * 255),
		"b": int(color.b * 255)
	})

func request_sensor_data():
	send_command("read_sensors")

func send_message(data: Dictionary):
	if not is_connected:
		print("Cannot send - Arduino not connected")
		return
	
	send_queue.append(data)

func send_next_in_queue():
	if send_queue.size() == 0:
		return
	
	var message = send_queue.pop_front()
	var json_string = JSON.stringify(message) + "\n"
	var bytes = json_string.to_utf8_buffer()
	
	if serial_port:
		serial_port.write(bytes)

func _exit_tree():
	disconnect_arduino()

func get_connection_status() -> String:
	if is_connected:
		return "Connected to " + port_name
	else:
		return "Not connected"

func is_arduino_connected() -> bool:
	return is_connected
