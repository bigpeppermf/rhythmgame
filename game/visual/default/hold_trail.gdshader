shader_type spatial;
render_mode unshaded;

uniform vec4 trail_color : source_color = vec4(1.0);
uniform float trail_length = 1.0;
varying float distance_from_head;

void vertex() {
	// The box is centred on its own origin: +Z is the head, -Z is the tail.
	distance_from_head = clamp(0.5 - VERTEX.z / max(trail_length, 0.001), 0.0, 1.0);
}

void fragment() {
	float fade = 1.0 - smoothstep(0.0, 1.0, distance_from_head);
	ALBEDO = trail_color.rgb;
	EMISSION = trail_color.rgb * 1.4;
	ALPHA = trail_color.a * fade;
}
