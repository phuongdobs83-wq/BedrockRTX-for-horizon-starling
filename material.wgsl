override shadow_enabled: bool = true;
override shadow_resolution: i32 = 512;
override shadow_distance: i32 = 48;
override shadow_strength: f32 = 0.78;
override shadow_softness: f32 = 0.0;
override ambient_gi: f32 = 0.42;
override day_brightness: f32 = 1.25;
override ambient_brightness: f32 = 1.15;
override colored_glass_lighting: bool = true;
override glass_light_strength: f32 = 0.72;
override dynamic_light_strength: f32 = 1.0;
override water_reflections: bool = true;
override water_texture_enabled: bool = false;
override water_waves: bool = true;
override water_wave_speed: f32 = 0.55;
override water_wave_scale: f32 = 0.85;
override water_reflection_strength: f32 = 0.72;
override water_distortion: f32 = 0.30;
override reflections_enabled: bool = true;
override block_reflections: bool = true;
override reflection_mode: u32 = 0u;
override block_reflection_strength: f32 = 0.24;
override wet_reflection_strength: f32 = 0.20;
override wet_reflection_roughness: f32 = 0.72;
override all_block_strength: f32 = 0.18;
override all_block_roughness: f32 = 0.42;
override block_reflection_quality: u32 = 0u;
override block_reflection_distance: f32 = 7.0;
override reflection_thickness: f32 = 0.24;
override reflection_edge_fade: f32 = 0.18;
override rain_reflection_strength: f32 = 0.24;
override rain_droplet_strength: f32 = 0.45;
override rain_droplet_scale: f32 = 1.2;
override shadow_color_style: u32 = 0u;
override shadow_color_strength: f32 = 0.22;


fn rtx_water_normal(xz: vec2<f32>, time: f32) -> vec3<f32> {
    if (!water_waves) { return vec3<f32>(0.0, 1.0, 0.0); }
    // Analytic slope of the same crossing-swell profile used by vertex.wgsl.
    // This creates a gentle 3D light response without extra texture reads.
    let p = xz;
    let t = time * 0.55;
    let a = p.x * 0.72 + t * 0.82;
    let b = p.y * 0.58 + t * 0.68;
    let c = (p.x + p.y) * 1.12 - t * 0.92;
    let d = (p.x - p.y) * 0.46 + t * 0.42;
    let dx = (0.58 * 0.72 * cos(a) * sin(b)
            + 0.27 * 1.12 * cos(c)
            + 0.15 * 0.46 * cos(d)) * 0.5;
    let dz = (0.58 * 0.58 * sin(a) * cos(b)
            + 0.27 * 1.12 * cos(c)
            - 0.15 * 0.46 * cos(d)) * 0.5;
    let height = 0.018;
    return normalize(vec3<f32>(-dx * height * 3.0, 1.0, -dz * height * 3.0));
}

fn rtx_shadow(position: vec3<f32>) -> f32 {
    if (!shadow_enabled || frame.has_shadow == 0u) { return 1.0; }
    let p = shadow_position(position);
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z < 0.0 || p.z > 1.0) { return 1.0; }
    let bias = max(frame.shadow_center_texel * 0.85, 0.00045);
    let center = textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy, p.z - bias);
    let storm = max(smoothstep(0.015, 0.78, clamp(frame.rain, 0.0, 1.0)),
                    smoothstep(0.02, 0.70, clamp(frame.thunder, 0.0, 1.0)));
    if (shadow_softness <= 0.001) { return mix(center, 1.0, storm); }
    let texel = frame.shadow_center_texel * (1.0 + shadow_softness * 1.5);
    let a = textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + vec2<f32>( texel, 0.0), p.z - bias);
    let b = textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + vec2<f32>(-texel, 0.0), p.z - bias);
    let c = textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + vec2<f32>(0.0, texel), p.z - bias);
    let d = textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + vec2<f32>(0.0,-texel), p.z - bias);
    let softened = mix(center, (center + a + b + c + d) * 0.2, shadow_softness);
    return mix(softened, 1.0, storm);
}


fn rtx_transmitted_shadow_tint(position: vec3<f32>) -> vec3<f32> {
    if (!shadow_enabled || frame.has_shadow == 0u) { return vec3<f32>(1.0); }
    let p = shadow_position(position);
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z < 0.0 || p.z > 1.0) {
        return vec3<f32>(1.0);
    }
    // The difference between the solid-only and translucent-inclusive maps
    // identifies light that crossed glass/water/ice instead of being blocked.
    let solid_visibility = textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy, p.z - 0.00045);
    let translucent_visibility = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, p.xy, p.z - 0.00045);
    let transmitted = clamp(solid_visibility - translucent_visibility, 0.0, 1.0);
    let dims = vec2<i32>(textureDimensions(shadow_color));
    let texel = clamp(vec2<i32>(p.xy * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
    let tint = textureLoad(shadow_color, texel, 0);
    let storm = max(smoothstep(0.015, 0.78, clamp(frame.rain, 0.0, 1.0)),
                    smoothstep(0.02, 0.70, clamp(frame.thunder, 0.0, 1.0)));
    let amount = transmitted * clamp(tint.a, 0.0, 1.0) * (1.0 - storm);
    return mix(vec3<f32>(1.0), clamp(tint.rgb, vec3<f32>(0.0), vec3<f32>(1.0)), amount);
}

fn rtx_metal_mask(base: vec3<f32>) -> f32 {
    let hi = max(base.r, max(base.g, base.b));
    let lo = min(base.r, min(base.g, base.b));
    let sat = (hi - lo) / max(hi, 0.001);
    let luma = dot(base, vec3<f32>(0.2126, 0.7152, 0.0722));
    let iron = (1.0 - smoothstep(0.045, 0.19, sat)) * smoothstep(0.30, 0.58, luma) * (1.0 - smoothstep(0.90, 0.99, luma));
    let gold = smoothstep(0.10, 0.24, base.r - base.b) * smoothstep(0.06, 0.18, base.g - base.b) * (1.0 - smoothstep(0.82, 0.98, luma));
    let copper = smoothstep(0.12, 0.28, base.r - base.g) * smoothstep(0.05, 0.16, base.g - base.b) * smoothstep(0.18, 0.40, luma);
    let diamond = smoothstep(0.07, 0.20, base.b - base.r) * smoothstep(0.06, 0.19, base.g - base.r) * smoothstep(0.18, 0.36, luma);
    let emerald = smoothstep(0.08, 0.22, base.g - base.r) * smoothstep(0.04, 0.17, base.g - base.b) * smoothstep(0.12, 0.30, luma);
    let amethyst = smoothstep(0.07, 0.20, base.r - base.g) * smoothstep(0.07, 0.20, base.b - base.g) * smoothstep(0.12, 0.32, luma);
    let lapis = smoothstep(0.08, 0.22, base.b - base.r) * smoothstep(0.04, 0.18, base.b - base.g) * smoothstep(0.10, 0.28, luma);
    let redstone = smoothstep(0.10, 0.26, base.r - base.g) * smoothstep(0.08, 0.22, base.r - base.b) * smoothstep(0.10, 0.28, luma);
    return clamp(max(max(max(iron, gold), max(copper, diamond)),
                      max(max(emerald, amethyst), max(lapis, redstone))), 0.0, 1.0);
}

fn rtx_shadow_tint() -> vec3<f32> {
    if (shadow_color_style == 1u) { return vec3<f32>(1.0, 0.72, 0.48); }
    if (shadow_color_style == 2u) { return vec3<f32>(0.52, 0.70, 1.0); }
    if (shadow_color_style == 3u) { return vec3<f32>(0.42, 0.88, 0.82); }
    if (shadow_color_style == 4u) { return vec3<f32>(0.72, 0.56, 1.0); }
    if (shadow_color_style == 5u) { return vec3<f32>(1.0, 0.48, 0.42); }
    return vec3<f32>(1.0);
}

fn rtx_droplets(position: vec3<f32>, normal: vec3<f32>) -> f32 {
    var plane = position.xz;
    let horizontal = abs(normal.y) > 0.65;
    if (abs(normal.x) > 0.65) { plane = position.zy; }
    else if (abs(normal.z) > 0.65) { plane = position.xy; }
    let scale = max(rain_droplet_scale, 0.1);
    let p = plane * scale;
    let cell = floor(p);
    let local = fract(p);
    let seed = rtx_hash21(cell + vec2<f32>(2.3, 7.1));
    let phase = fract(frame.time * 0.42 + seed);
    let center_x = 0.18 + rtx_hash21(cell + vec2<f32>(8.2, 1.4)) * 0.64;
    // Beads descend on vertical faces; on horizontal faces they form soft ripple rings.
    let drop_center = vec2<f32>(center_x, 1.0 - phase);
    let drop_dist = length((local - drop_center) * vec2<f32>(1.0, 1.8));
    let falling_bead = 1.0 - smoothstep(0.035, 0.095, drop_dist);
    let tail_x = abs(local.x - center_x);
    let tail_y = smoothstep(0.04, 0.18, local.y - drop_center.y) * (1.0 - smoothstep(0.20, 0.48, local.y - drop_center.y));
    let tail = (1.0 - smoothstep(0.012, 0.038, tail_x)) * tail_y;
    let ripple_phase = fract(frame.time * 0.28 + seed);
    let ripple_radius = ripple_phase * 0.48;
    let ripple_dist = abs(length(local - vec2<f32>(0.5)) - ripple_radius);
    let ripple = (1.0 - smoothstep(0.018, 0.055, ripple_dist)) * (1.0 - ripple_phase) * 0.42;
    let vertical_effect = max(falling_bead, tail * 0.42);
    return clamp(select(vertical_effect, ripple, horizontal), 0.0, 1.0);
}

// API 0.1's built-in mirrored-world texture. This avoids the unverified custom depth-ray
// pass and does not require hardware ray-tracing support.
fn rtx_block_reflection(uv: vec2<f32>, normal: vec3<f32>, roughness: f32) -> vec3<f32> {
    let count = clamp(i32(block_reflection_quality) * 2 + 3, 3, 7);
    let direction = vec2<f32>(normal.x, -normal.y);
    let span = clamp(roughness, 0.0, 1.0) * 0.0018;
    var accum = vec3<f32>(0.0);
    var weight_sum = 0.0;
    for (var i: i32 = 0; i < 8; i = i + 1) {
        if (i >= count) { break; }
        let centered = (f32(i) - (f32(count) - 1.0) * 0.5) / max(f32(count), 1.0);
        let sample_uv = clamp(uv + direction * centered * span, vec2<f32>(0.001), vec2<f32>(0.999));
        let weight = 1.0 - abs(centered) * 0.55;
        accum += textureSample(reflection, reflection_sampler, sample_uv).rgb * weight;
        weight_sum += weight;
    }
    return accum / max(weight_sum, 0.001);
}

fn material(input: MaterialInput) -> Surface {
    var n = normalize(input.normal);
    let base = input.albedo * input.tint;
    let sun = normalize(frame.light_direction);
    let ndl = max(dot(n, sun), 0.0);
    let shadow_raw = rtx_shadow(input.position);
    let shadow = mix(1.0, shadow_raw, clamp(shadow_strength, 0.0, 1.0));
    let shadow_amount = (1.0 - shadow) * clamp(shadow_color_strength, 0.0, 1.0);
    let shadow_tone = mix(vec3<f32>(1.0), rtx_shadow_tint(), shadow_amount);
    let day = rtx_day_factor();
    let sky_light = clamp(input.light.y, 0.0, 1.0);
    let block_light = clamp(input.light.x, 0.0, 1.0);
    // Live weather controls storm lighting and automatic shadow fading.
    let rain_factor = smoothstep(0.015, 0.78, clamp(frame.rain, 0.0, 1.0));
    let wet_factor = clamp(frame.wetness, 0.0, 1.0);
    let direct_weather = mix(1.0, 0.52, rain_factor);
    let transmitted_tint = rtx_transmitted_shadow_tint(input.position);
    let direct = vec3<f32>(1.0, 0.94, 0.82) * transmitted_tint * ndl * shadow * day * 1.45 * day_brightness * shadow_tone * direct_weather;
    let ambient_night = vec3<f32>(0.055, 0.075, 0.12);
    let ambient_day = vec3<f32>(0.34, 0.39, 0.48);
    let ambient_clear = mix(ambient_night, ambient_day, day);
    let storm_ambient = vec3<f32>(0.39, 0.425, 0.47);
    let ambient_color = mix(ambient_clear, storm_ambient, rain_factor);
    let ambient_floor = mix(0.34, 0.58, rain_factor);
    let sky_contribution = mix(sky_light * 0.72, max(sky_light * 0.72, 0.48), rain_factor);
    let bounce = ambient_color * (ambient_floor + sky_contribution) * ambient_gi * ambient_brightness;
    let torch = vec3<f32>(1.0, 0.48, 0.20) * block_light * block_light * 1.35 * dynamic_light_strength;
    let chroma = max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b));
    let tint_bounce = select(vec3<f32>(0.0), base.rgb * block_light * glass_light_strength * 0.12, colored_glass_lighting && chroma > 0.10);
    let floor_base = mix(0.075, 0.105, rain_factor);
    let floor = vec3<f32>(floor_base + frame.night_vision * 0.45);
    let shadow_fill = (1.0 - shadow_raw) * clamp(shadow_color_strength, 0.0, 1.0) * 0.12;
    var lit = base.rgb * (direct + bounce + torch + tint_bounce + floor) + base.rgb * rtx_shadow_tint() * shadow_fill;

    let metal_mask = rtx_metal_mask(base.rgb);
    let view_facing = 1.0 - abs(dot(n, normalize(-input.position)));
    let facing = mix(0.18, 1.0, clamp(view_facing, 0.0, 1.0));
    let view_distance = length(input.position);
    let distance_fade = 1.0 - smoothstep(max(block_reflection_distance * 0.72, 0.1), max(block_reflection_distance, 0.2), view_distance);

    // Block reflections use Horizon's API 0.1 mirrored-world buffer.
    // The three modes share this path so a mode change cannot bypass the renderer target.
    if (reflections_enabled && block_reflections && frame.has_reflection != 0u && input.fluid == 0u) {
        var reflect_mask = 0.0;
        var reflect_strength = 0.0;
        var roughness = 0.42;
        if (reflection_mode == 1u) {
            // All Blocks: every solid surface, including dry blocks.
            reflect_mask = 1.0;
            reflect_strength = all_block_strength;
            roughness = all_block_roughness;
        } else if (reflection_mode == 2u) {
            // Wet Surfaces: only when the world reports rain or wetness.
            let wet_amount = max(wet_factor, rain_factor * 0.72);
            reflect_mask = smoothstep(0.015, 0.12, wet_amount);
            reflect_strength = wet_reflection_strength * wet_amount;
            roughness = wet_reflection_roughness;
        } else {
            // Natural: reflective metal and gem-like albedo colours.
            reflect_mask = metal_mask;
            reflect_strength = block_reflection_strength;
            roughness = 0.22;
        }
        // Fade the mirrored buffer near the screen boundary to avoid edge smearing.
        let edge_distance = min(min(input.screen.x, 1.0 - input.screen.x),
                                min(input.screen.y, 1.0 - input.screen.y));
        let edge = smoothstep(0.0, max(reflection_edge_fade, 0.001), edge_distance);
        let amount = clamp(reflect_mask * reflect_strength * (1.0 - roughness * 0.55) * facing * edge, 0.0, 0.42);
        if (amount > 0.002) {
            let reflected = rtx_block_reflection(input.screen, n, roughness);
            lit = mix(lit, reflected, amount);
        }
    }

    // Rain reflections remain a separate wet-surface effect; block reflections no longer
    // sample the vertically ambiguous reflection buffer.
    if (reflections_enabled && block_reflections && reflection_mode == 2u && rain_factor > 0.01 &&
        input.fluid == 0u && frame.has_reflection != 0u) {
        let uv = clamp(input.screen, vec2<f32>(0.001), vec2<f32>(0.999));
        let reflected = textureSample(reflection, reflection_sampler, uv).rgb;
        let wet_amount = clamp(rain_reflection_strength * rain_factor * facing, 0.0, 0.24);
        lit = mix(lit, reflected, wet_amount);
    }
    if (reflections_enabled && block_reflections && reflection_mode == 2u && wet_factor > 0.01 && input.fluid == 0u) {
        let droplets = rtx_droplets(input.position, n);
        let droplet_glint = droplets * rain_droplet_strength * wet_factor * (0.18 + 0.42 * facing);
        lit += vec3<f32>(0.30, 0.38, 0.46) * droplet_glint;
    }

    if (input.fluid == 1u && input.face == 1u) {
        let water_world = input.position + frame.camera_position;
        n = rtx_water_normal(water_world.xz, frame.time);
        let water_fresnel = pow(1.0 - clamp(dot(n, normalize(-input.position)), 0.0, 1.0), 5.0);
        // Water Texture ON keeps Minecraft's original water surface appearance.
        // OFF uses a clean, low-detail turquoise surface for a lightweight clear-water look.
        var water = vec3<f32>(0.012, 0.115, 0.165);
        if (water_texture_enabled) {
            water = lit;
        }
        if (reflections_enabled && water_reflections && frame.has_reflection != 0u) {
            let distortion = n.xz * water_distortion * 0.008;
            let uv = clamp(input.screen + distortion, vec2<f32>(0.001), vec2<f32>(0.999));
            let water_reflected = textureSample(reflection, reflection_sampler, uv).rgb;
            water = mix(water, water_reflected, clamp(water_reflection_strength * (0.25 + water_fresnel * 0.75), 0.0, 1.0));
        }
        lit = water;
    }
    return Surface(vec4<f32>(max(lit, vec3<f32>(0.0)), base.a));
}
