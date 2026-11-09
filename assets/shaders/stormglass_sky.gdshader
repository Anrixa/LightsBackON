// DS08 Stormglass sky: storm-blue zenith, lighter horizon band, static cloud bands and a faint warm glow on one horizon
// (a powered district far away). No TIME: a static sky keeps the radiance map from updating every frame (Compatibility cost).
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.055, 0.1, 0.17);
uniform vec3 horizon : source_color = vec3(0.24, 0.35, 0.45);
uniform vec3 ground : source_color = vec3(0.08, 0.12, 0.15);
uniform vec3 far_glow : source_color = vec3(0.79, 0.54, 0.3);
uniform vec3 far_glow_dir = vec3(0.0, 0.1, -1.0);
uniform float far_glow_strength = 0.45;
uniform vec3 cloud_tint : source_color = vec3(0.16, 0.24, 0.32);
uniform float cloud_amount = 0.55;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 c = mix(horizon, zenith, smoothstep(0.0, 0.55, y));
	if (y < 0.0) {
		c = mix(horizon, ground, smoothstep(0.0, -0.15, y));
	}
	// Cloud deck projected on a plane: large soft bands, denser near the horizon.
	if (y > 0.0) {
		vec2 uv = d.xz / (y + 0.12) * 0.9;
		float n = fbm(uv * 0.6);
		float cloud = smoothstep(0.35, 0.85, n) * cloud_amount * (1.0 - smoothstep(0.25, 0.9, y) * 0.6);
		c = mix(c, cloud_tint, cloud);
	}
	float glow = pow(max(dot(d, normalize(far_glow_dir)), 0.0), 6.0) * (1.0 - smoothstep(-0.02, 0.35, y));
	c += far_glow * glow * far_glow_strength;
	COLOR = c;
}
