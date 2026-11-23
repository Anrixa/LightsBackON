shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Authored in-repository; no stock photograph or third-party texture.
// UV-based wear is stable between frames and contains no TIME dependency.
uniform vec4 base_color : source_color = vec4(0.35, 0.43, 0.48, 1.0);
uniform vec4 oxidation_color : source_color = vec4(0.46, 0.30, 0.23, 1.0);
uniform float wetness : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	float grit = fract(sin(dot(floor(UV * 137.0), vec2(12.9898, 78.233))) * 43758.5453);
	float runoff = smoothstep(0.22, 0.85, 1.0 - UV.y);
	float corrosion = clamp(0.22 * grit + 0.28 * runoff, 0.0, 0.42);
	ALBEDO = mix(base_color.rgb, oxidation_color.rgb, corrosion);
	METALLIC = 0.24;
	ROUGHNESS = clamp(0.85 - 0.42 * wetness, 0.35, 0.91);
	SPECULAR = 0.34;
}
