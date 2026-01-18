shader_type canvas_item;

uniform float glow_strength : hint_range(0.0, 2.0) = 1.0;

void fragment() {
    vec4 color = texture(TEXTURE, UV);
    
    // Add glow to green pheromones
    if (color.g > 0.1) {
        float intensity = color.g;
        COLOR = vec4(0.0, intensity, 0.0, intensity * 0.8);
        
        // Add bloom effect
        COLOR += vec4(0.0, intensity * glow_strength, 0.0, 0.0);
    } else {
        COLOR = vec4(0.0, 0.0, 0.0, 0.0);
    }
}