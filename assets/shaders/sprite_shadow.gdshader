shader_type canvas_item;

// Shadow settings
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);
uniform float shadow_blur : hint_range(0.0, 10.0) = 1.0;
uniform float shadow_expand : hint_range(0.0, 5.0) = 1.5;

void fragment() {
	// Expanded blur sampling for soft shadow (no offset - stays within bounds)
	float shadow_alpha = 0.0;
	float blur_size = shadow_blur * TEXTURE_PIXEL_SIZE.x * shadow_expand;

	// 9-tap blur pattern for smoother shadow
	shadow_alpha += texture(TEXTURE, UV).a * 0.25;
	shadow_alpha += texture(TEXTURE, UV + vec2(blur_size, 0.0)).a * 0.1;
	shadow_alpha += texture(TEXTURE, UV - vec2(blur_size, 0.0)).a * 0.1;
	shadow_alpha += texture(TEXTURE, UV + vec2(0.0, blur_size)).a * 0.1;
	shadow_alpha += texture(TEXTURE, UV - vec2(0.0, blur_size)).a * 0.1;
	shadow_alpha += texture(TEXTURE, UV + vec2(blur_size, blur_size) * 0.7).a * 0.0875;
	shadow_alpha += texture(TEXTURE, UV + vec2(-blur_size, blur_size) * 0.7).a * 0.0875;
	shadow_alpha += texture(TEXTURE, UV + vec2(blur_size, -blur_size) * 0.7).a * 0.0875;
	shadow_alpha += texture(TEXTURE, UV + vec2(-blur_size, -blur_size) * 0.7).a * 0.0875;

	// Create shadow color
	vec4 shadow = vec4(shadow_color.rgb, shadow_alpha * shadow_color.a);

	// Get original pixel
	vec4 original = texture(TEXTURE, UV);

	// Composite: shadow underneath, original on top
	COLOR = mix(shadow, original, original.a);
}
