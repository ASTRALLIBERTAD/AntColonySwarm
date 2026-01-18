#include <ArduinoJson.h>
#include <FastLED.h>

#define NUM_LEDS 16
#define LED_PIN 6
#define SERIAL_BAUD 9600

CRGB leds[NUM_LEDS];

enum AntState {
    SEARCHING_FOR_FOOD,
    FOLLOWING_TRAIL,
    RETURNING_TO_NEST,
    IDLE
};

struct AntRobot {
    AntState state;
    bool has_food;
    int food_collected;
    float fitness;
    
    float wander_strength;
    float rotation_speed;
    float pheromone_deposit;
} ant;.
float sensors[8];


struct PheromoneTrail {
    float strength[32];
    int write_index;
    int read_index;
} trail;

String input_buffer = "";
unsigned long last_status_send = 0;
const unsigned long STATUS_INTERVAL = 1000; 

unsigned long last_update = 0;
const unsigned long UPDATE_INTERVAL = 50; 

void setup() {
    Serial.begin(SERIAL_BAUD);

    FastLED.addLeds<WS2812B, LED_PIN, GRB>(leds, NUM_LEDS);
    FastLED.setBrightness(100);

    ant.state = SEARCHING_FOR_FOOD;
    ant.has_food = false;
    ant.food_collected = 0;
    ant.fitness = 0.0;
    ant.wander_strength = 0.5;
    ant.rotation_speed = 3.0;
    ant.pheromone_deposit = 2.0;

    for (int i = 0; i < 32; i++) {
        trail.strength[i] = 0.0;
    }
    trail.write_index = 0;
    trail.read_index = 0;

    randomSeed(analogRead(A0));
    
    startupAnimation();
    
    sendMessage("ready", "Ant robot initialized");
    
    Serial.println("=== ANT ROBOT READY ===");
}

void loop() {
    unsigned long current_time = millis();
    
    if (Serial.available()) {
        char c = Serial.read();
        if (c == '\n') {
            processCommand(input_buffer);
            input_buffer = "";
        } else {
            input_buffer += c;
        }
    }
   
    if (current_time - last_update >= UPDATE_INTERVAL) {
        last_update = current_time;
        
        readSensors();
        updateAntBehavior();
        visualizeState();
    }
    
    if (current_time - last_status_send >= STATUS_INTERVAL) {
        last_status_send = current_time;
        sendStatus();
    }
}

void processCommand(String json_string) {
    StaticJsonDocument<1024> doc;
    DeserializationError error = deserializeJson(doc, json_string);
    
    if (error) {
        sendMessage("error", "JSON parse failed: " + String(error.c_str()));
        return;
    }
    
    const char* type = doc["type"];
    
    if (strcmp(type, "handshake") == 0) {
        sendMessage("ready", "Handshake acknowledged");
    }
    else if (strcmp(type, "behavior") == 0) {
        loadBehaviorData(doc["data"]);
    }
    else if (strcmp(type, "command") == 0) {
        handleCommand(doc);
    }
    else if (strcmp(type, "pheromones") == 0) {
        sendMessage("status", "Pheromone data received");
    }
}

void loadBehaviorData(JsonObject data) {
    if (data.containsKey("food_collected")) {
        int food = data["food_collected"];
        Serial.print("Loading ant with ");
        Serial.print(food);
        Serial.println(" food collected");
    }
    
    if (data.containsKey("fitness")) {
        ant.fitness = data["fitness"];
    }
    
    if (data.containsKey("behavior_weights")) {
        JsonObject weights = data["behavior_weights"];
        ant.wander_strength = weights["wander_strength"];
        ant.rotation_speed = weights["rotation_speed"];
        ant.pheromone_deposit = weights["pheromone_deposit"];
    }
    
    sendMessage("weights_loaded", "Behavior parameters loaded");
    celebrationAnimation();
}

void handleCommand(JsonObject doc) {
    const char* cmd = doc["cmd"];
    
    if (strcmp(cmd, "read_sensors") == 0) {
        sendSensorData();
    }
    else if (strcmp(cmd, "set_leds") == 0) {
        setLEDPattern(doc);
    }
    else if (strcmp(cmd, "update_state") == 0) {
        const char* state_name = doc["state"];
        bool has_food = doc["has_food"];

        if (strcmp(state_name, "SEARCHING") == 0) {
            ant.state = SEARCHING_FOR_FOOD;
        } else if (strcmp(state_name, "FOLLOWING") == 0) {
            ant.state = FOLLOWING_TRAIL;
        } else if (strcmp(state_name, "RETURNING") == 0) {
            ant.state = RETURNING_TO_NEST;
        }
        
        ant.has_food = has_food;
    }
}

void readSensors() {

    for (int i = 0; i < 8; i++) {
        if (i < 6) {
            sensors[i] = analogRead(A0 + i) / 1023.0;
        } else {
            sensors[i] = random(0, 100) / 100.0;
        }
        
        static float last_sensors[8] = {0};
        sensors[i] = sensors[i] * 0.3 + last_sensors[i] * 0.7;
        last_sensors[i] = sensors[i];
    }
}

void updateAntBehavior() {
    switch (ant.state) {
        case SEARCHING_FOR_FOOD:
            searchBehavior();
            break;
            
        case FOLLOWING_TRAIL:
            followTrailBehavior();
            break;
            
        case RETURNING_TO_NEST:
            returnBehavior();
            break;
            
        case IDLE:
            idleBehavior();
            break;
    }
}

void searchBehavior() {
    if (sensors[0] > 0.85) {
        // Found food!
        ant.has_food = true;
        ant.state = RETURNING_TO_NEST;
        sendMessage("food_found", "Food detected by front sensor");
        return;
    }
    
    float left_pheromone = sensors[6] + sensors[7];
    float right_pheromone = sensors[1] + sensors[2];
    
    if (left_pheromone > 1.0 || right_pheromone > 1.0) {
        ant.state = FOLLOWING_TRAIL;
        return;
    }
    
}

void followTrailBehavior() {
    if (sensors[0] > 0.85) {
        ant.has_food = true;
        ant.state = RETURNING_TO_NEST;
        sendMessage("food_found", "Food found while following trail");
        return;
    }
    
    float total_pheromone = 0;
    for (int i = 0; i < 8; i++) {
        total_pheromone += sensors[i];
    }
    
    if (total_pheromone < 2.0) {
        ant.state = SEARCHING_FOR_FOOD;
    }
}

void returnBehavior() {
    depositPheromone();
    
    static int return_progress = 0;
    return_progress++;
    
    if (return_progress > 40) { 
        ant.has_food = false;
        ant.food_collected++;
        ant.state = SEARCHING_FOR_FOOD;
        return_progress = 0;
        
        sendMessage("returned_to_nest", "Food delivered, count: " + String(ant.food_collected));
        deliveryAnimation();
    }
}

void idleBehavior() {
    static uint8_t hue = 0;
    fill_solid(leds, NUM_LEDS, CHSV(hue++, 100, 50));
}

void depositPheromone() {
    trail.strength[trail.write_index] = ant.pheromone_deposit;
    trail.write_index = (trail.write_index + 1) % 32;
    
    for (int i = 0; i < 32; i++) {
        trail.strength[i] *= 0.95; 
        if (trail.strength[i] < 0.1) {
            trail.strength[i] = 0.0;
        }
    }
}

void visualizeState() {
    switch (ant.state) {
        case SEARCHING_FOR_FOOD:
            visualizeSearching();
            break;
            
        case FOLLOWING_TRAIL:
            visualizeFollowingTrail();
            break;
            
        case RETURNING_TO_NEST:
            visualizeReturning();
            break;
            
        case IDLE:
            visualizeIdle();
            break;
    }
    
    FastLED.show();
}

void visualizeSearching() {
    static uint8_t pos = 0;
    static uint8_t hue = 160; 
    
    fadeToBlackBy(leds, NUM_LEDS, 20);
    leds[pos] = CHSV(hue, 255, 200);
    leds[(pos + 1) % NUM_LEDS] = CHSV(hue, 255, 100);
    
    pos = (pos + 1) % NUM_LEDS;
    hue += 2;
}

void visualizeFollowingTrail() {
    static uint8_t pos = 0;
    
    fill_solid(leds, NUM_LEDS, CRGB::Black);
    leds[pos] = CRGB::Yellow;
    leds[(pos + 1) % NUM_LEDS] = CRGB::Yellow;
    leds[(pos + 2) % NUM_LEDS] = CRGB(128, 128, 0);
    
    pos = (pos + 1) % NUM_LEDS;
}

void visualizeReturning() {
    static int pos = NUM_LEDS - 1;
    
    for (int i = 0; i < NUM_LEDS && i < 32; i++) {
        float strength = trail.strength[i] / ant.pheromone_deposit;
        leds[i] = CRGB(255, int(165 * strength), 0); 
    }
    
    leds[pos] = CRGB::OrangeRed;
    leds[(pos - 1 + NUM_LEDS) % NUM_LEDS] = CRGB::Orange;
    
    pos = (pos - 1 + NUM_LEDS) % NUM_LEDS;
}

void visualizeIdle() {
    static uint8_t brightness = 0;
    static int8_t direction = 1;
    
    brightness += direction * 2;
    if (brightness >= 200 || brightness <= 30) {
        direction = -direction;
    }
    
    fill_solid(leds, NUM_LEDS, CHSV(96, 200, brightness)); // Green
}

void setLEDPattern(JsonObject doc) {
    const char* pattern = doc["pattern"];
    int r = doc["r"];
    int g = doc["g"];
    int b = doc["b"];
    
    if (strcmp(pattern, "solid") == 0) {
        fill_solid(leds, NUM_LEDS, CRGB(r, g, b));
    }
    else if (strcmp(pattern, "off") == 0) {
        fill_solid(leds, NUM_LEDS, CRGB::Black);
    }
    
    FastLED.show();
}

void startupAnimation() {
    for (int i = 0; i < NUM_LEDS; i++) {
        leds[i] = CRGB::Blue;
        FastLED.show();
        delay(30);
    }
    delay(200);
    fadeToBlackBy(leds, NUM_LEDS, 255);
    FastLED.show();
}

void celebrationAnimation() {
    for (int j = 0; j < 3; j++) {
        fill_solid(leds, NUM_LEDS, CRGB::Green);
        FastLED.show();
        delay(150);
        fill_solid(leds, NUM_LEDS, CRGB::Black);
        FastLED.show();
        delay(150);
    }
}

void deliveryAnimation() {
    fill_solid(leds, NUM_LEDS, CRGB::Yellow);
    FastLED.show();
    delay(100);
}

void sendSensorData() {
    StaticJsonDocument<512> doc;
    doc["type"] = "sensor_data";
    
    JsonArray values = doc.createNestedArray("values");
    for (int i = 0; i < 8; i++) {
        values.add(sensors[i]);
    }
    
    sendJsonMessage(doc);
}

void sendStatus() {
    StaticJsonDocument<256> doc;
    doc["type"] = "status";
    doc["state"] = getStateName();
    doc["has_food"] = ant.has_food;
    doc["food_collected"] = ant.food_collected;
    doc["uptime"] = millis();
    
    sendJsonMessage(doc);
}

void sendMessage(const char* type, String message) {
    StaticJsonDocument<256> doc;
    doc["type"] = type;
    doc["message"] = message;
    
    sendJsonMessage(doc);
}

void sendJsonMessage(JsonDocument& doc) {
    String output;
    serializeJson(doc, output);
    Serial.println(output);
}

const char* getStateName() {
    switch (ant.state) {
        case SEARCHING_FOR_FOOD: return "SEARCHING";
        case FOLLOWING_TRAIL: return "FOLLOWING";
        case RETURNING_TO_NEST: return "RETURNING";
        case IDLE: return "IDLE";
        default: return "UNKNOWN";
    }
}