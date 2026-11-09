// DS08 Stormglass surface: one project-made shader for every kit and ground surface. Patterns are generated from world
// position (no textures), so the 4 m kit can be re-skinned per building without new assets. Detail fades with distance
// (fwidth) so brick and slab joints never shimmer. Rain wetness darkens and smooths streaks on walls and puddles on the
// ground; the specular streaks from lamps and windows on wet ground are the "wet street" read without SSR (Compatibility).
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.5);
uniform vec3 accent_color : source_color = vec3(0.3);
uniform int pattern = 0; // 0 render, 1 brick, 2 corrugated, 3 concrete panels, 4 painted metal, 5 asphalt, 6 paving, 7 ground
uniform float roughness_base = 0.85;
uniform float wetness = 0.5;
uniform float scale = 1.0; // metres per pattern unit
uniform float grime_height = 1.1;
uniform float grime_strength = 0.3;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Antialiased grid line: 1 on the joint, 0 elsewhere, faded out once the joint is thinner than a pixel.
float joint(float v, float width) {
	float fw = fwidth(v);
	float d = min(fract(v), 1.0 - fract(v));
	float line = 1.0 - smoothstep(width - fw, width + fw, d);
	return line * (1.0 - smoothstep(0.15, 0.45, fw));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(wnorm);
	bool floor_like = n.y > 0.7;
	vec2 uv = floor_like ? wpos.xz : (n.x > n.z ? wpos.zy : wpos.xy);
	vec3 col = base_color;
	float rough = roughness_base;
	float wet_mask = 0.0;
	float big = noise(uv * 0.35);
	float fine = noise(uv * 3.1);
	if (pattern == 1) {
		// brick: 23 x 8.5 cm courses, running bond, per-brick tint
		float row = floor(uv.y / 0.085);
		vec2 b = vec2(uv.x / 0.23 + 0.5 * mod(row, 2.0), uv.y / 0.085);
		float id = hash(floor(b));
		col = base_color * (0.82 + 0.3 * id);
		float m = max(joint(b.x, 0.05), joint(b.y, 0.09));
		col = mix(col, accent_color, m * 0.85);
	} else if (pattern == 2) {
		// corrugated sheet: vertical ribs every 7.6 cm, light falls off on one side of each rib
		float rib = sin(uv.x / 0.076 * 6.2832);
		float fw = fwidth(uv.x / 0.076);
		rib *= 1.0 - smoothstep(0.3, 0.8, fw);
		col = mix(accent_color, base_color, 0.55 + 0.45 * rib);
		col *= 0.9 + 0.2 * big;
	} else if (pattern == 3) {
		// concrete panels 1.5 x 1.0 m with form-tie dots and mottling
		vec2 p = uv / vec2(1.5, 1.0) * (1.0 / scale);
		col = base_color * (0.88 + 0.2 * big + 0.06 * fine);
		col = mix(col, accent_color, max(joint(p.x, 0.012), joint(p.y, 0.018)) * 0.8);
	} else if (pattern == 4) {
		// painted metal: flat, slight wear
		col = base_color * (0.93 + 0.1 * big);
		rough = roughness_base - 0.1 * fine;
	} else if (pattern == 5) {
		// asphalt: aggregate speckle, tar patches, puddles
		col = mix(accent_color, base_color, 0.55 + 0.45 * fine);
		col *= 0.85 + 0.25 * big;
		wet_mask = smoothstep(0.58, 0.66, noise(uv * 0.18 + 3.7));
	} else if (pattern == 6) {
		// paving slabs, 60 cm, staggered rows, per-slab tint
		vec2 p = uv / scale;
		p.x += 0.5 * mod(floor(p.y), 2.0);
		col = base_color * (0.86 + 0.22 * hash(floor(p)));
		col = mix(col, accent_color, max(joint(p.x, 0.02), joint(p.y, 0.02)) * 0.9);
		wet_mask = smoothstep(0.62, 0.7, noise(uv * 0.22 + 9.1));
	} else if (pattern == 7) {
		// bare ground: gravel and dirt mottling
		col = mix(accent_color, base_color, 0.4 + 0.6 * big) * (0.9 + 0.15 * fine);
		wet_mask = smoothstep(0.62, 0.72, noise(uv * 0.2 + 1.3));
	} else {
		// render / plaster: soft blotches and fine grain
		col = base_color * (0.9 + 0.16 * big + 0.05 * fine);
		col = mix(col, accent_color, smoothstep(0.7, 0.95, noise(uv * 1.3)) * 0.25);
	}
	if (!floor_like) {
		// grime at the base of walls, and vertical rain streaks
		float g = 1.0 - smoothstep(0.0, grime_height, wpos.y);
		col *= 1.0 - grime_strength * g;
		float streak = smoothstep(0.55, 0.8, noise(vec2(uv.x * 7.0, uv.y * 0.35)));
		wet_mask = max(wet_mask, streak * 0.8);
	}
	if (floor_like) {
		// the whole street is damp; puddles on top are mirror-smooth
		rough = mix(rough, 0.38, wetness * 0.6);
	}
	float wet = wet_mask * wetness;
	col *= 1.0 - 0.35 * wet;
	rough = mix(rough, floor_like ? 0.06 : 0.3, wet);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	SPECULAR = 0.5;
}
