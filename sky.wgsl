override night_stars: bool = true;
override night_aurora: bool = true;
override color_warmth: f32 = 0.45;
override aurora_style: u32 = 0u;
override aurora_palette: u32 = 0u;
override aurora_brightness: f32 = 0.90;
override aurora_speed: f32 = 0.10;
override aurora_scale: f32 = 1.0;
override aurora_height: f32 = 0.30;
override aurora_width: f32 = 1.0;
override aurora_detail: f32 = 0.70;

fn rtx_starfield(d: vec3<f32>) -> vec3<f32> {
    // Sparse procedural stars: one hash per coarse sky cell.
    let uv = vec2<f32>(atan2(d.z, d.x) * 0.15915494 + 0.5, asin(clamp(d.y, -1.0, 1.0)) * 0.31830989 + 0.5);
    let cell = floor(uv * vec2<f32>(360.0, 180.0));
    let rnd = rtx_hash21(cell);
    let twinkle = 0.78 + 0.22 * sin(frame.time * 1.25 + rnd * 31.0);
    let star = smoothstep(0.9975, 1.0, rnd) * twinkle;
    let tint = mix(vec3<f32>(0.62, 0.76, 1.0), vec3<f32>(1.0, 0.91, 0.76), rnd);
    return tint * star * 1.45;
}

fn rtx_aurora_palette(index: u32, t: f32) -> vec3<f32> {
    if (index == 1u) { return mix(vec3<f32>(0.08, 0.35, 1.0), vec3<f32>(0.72, 0.12, 1.0), t); }
    if (index == 2u) { return mix(vec3<f32>(0.0, 0.95, 0.82), vec3<f32>(0.12, 0.32, 1.0), t); }
    if (index == 3u) { return mix(vec3<f32>(0.25, 1.0, 0.18), vec3<f32>(1.0, 0.22, 0.52), t); }
    if (index == 4u) { return mix(vec3<f32>(1.0, 0.18, 0.12), vec3<f32>(1.0, 0.72, 0.12), t); }
    if (index == 5u) { return mix(vec3<f32>(0.18, 0.95, 0.42), vec3<f32>(0.12, 0.55, 1.0), t); }
    return mix(vec3<f32>(0.10, 1.0, 0.48), vec3<f32>(0.20, 0.48, 1.0), t);
}

fn rtx_aurora(d: vec3<f32>) -> vec3<f32> {
    let night = 1.0 - rtx_day_factor();
    // Avoid evaluating the aurora below the horizon or near the zenith.
    let horizon_gate = smoothstep(0.025, 0.16, d.y) * (1.0 - smoothstep(0.78, 0.94, d.y));
    let drift = frame.time * aurora_speed;
    let x = (d.x * 7.0 + d.z * 2.1) * max(aurora_scale, 0.05);
    let wave_a = sin(x * 1.45 + drift);
    let wave_b = sin(x * 0.62 - drift * 0.55);
    var curtain_y = 0.30 + wave_a * 0.065 + wave_b * 0.028;
    var width = 0.105;
    var detail = 0.78 + 0.22 * sin(x * 8.0 + wave_a * 1.6 - drift);
    var pulse = 1.0;

    // 0 natural curtains; 1 discrete arc; 2 diffuse glow; 3 pulsating bands;
    // 4 vertical rays; 5 coronal fan; 6 fantasy spiral; 7 celestial ribbons.
    if (aurora_style == 1u) {
        curtain_y = 0.255 + 0.018 * wave_a;
        width = 0.035;
        detail = 0.82 + 0.18 * sin(x * 3.0 + drift * 0.3);
    } else if (aurora_style == 2u) {
        curtain_y = 0.31 + 0.025 * wave_b;
        width = 0.22;
        detail = 0.72 + 0.12 * sin(x * 1.8 + drift * 0.2);
    } else if (aurora_style == 3u) {
        curtain_y += 0.045 * sin(x * 2.2 - drift * 1.4);
        width = 0.075;
        pulse = 0.72 + 0.28 * sin(drift * 1.7 + x * 0.22);
    } else if (aurora_style == 4u) {
        curtain_y = 0.34 + 0.10 * sin(x * 0.85 + drift * 0.6);
        let rays = pow(max(cos(x * 4.2 + drift * 0.25), 0.0), 7.0);
        detail = 0.12 + 0.88 * rays;
        width = 0.16;
    } else if (aurora_style == 5u) {
        curtain_y = 0.39 + 0.035 * sin(x * 1.1 + drift * 0.3);
        let fan = pow(max(cos(x * 2.4 + drift * 0.18), 0.0), 5.0);
        detail = 0.18 + fan * 0.82;
        width = 0.24;
    } else if (aurora_style == 6u) {
        let angle = atan2(d.z, d.x);
        curtain_y = 0.32 + 0.075 * sin(angle * 3.0 + drift * 0.75 + d.y * 5.0);
        width = 0.095;
        detail = 0.55 + 0.45 * sin(angle * 8.0 - drift + d.y * 9.0);
    } else if (aurora_style == 7u) {
        curtain_y = 0.27 + 0.055 * sin(x * 2.7 + drift) + 0.018 * sin(x * 6.0 - drift * 0.5);
        width = 0.065;
        detail = 0.62 + 0.38 * sin(x * 5.2 + drift * 0.8);
    }

    curtain_y += aurora_height - 0.30;
    width *= max(aurora_width, 0.05);
    detail = clamp(0.5 + (detail - 0.5) * aurora_detail, 0.0, 1.0);
    let band = exp(-abs(d.y - curtain_y) / max(width, 0.012));
    let second_band = exp(-abs(d.y - (curtain_y + 0.105 + wave_b * 0.018)) / max(width * 0.72, 0.01));
    let palette_t = 0.5 + 0.5 * sin(x * 0.36 + drift * 0.18);
    let palette = rtx_aurora_palette(aurora_palette, palette_t);
    let light = (band * detail + second_band * detail * 0.34) * horizon_gate * night * pulse;
    return palette * light * max(aurora_brightness, 0.0) * 0.68;
}


fn sky(input: SkyInput) -> vec4<f32> {
    let d = normalize(input.direction);
    // Dimension IDs used by the Horizon frame interface: 0 Overworld, 1 Nether, 2 End.
    if (frame.dimension == 1) {
        let h = pow(1.0 - clamp(d.y * 0.5 + 0.5, 0.0, 1.0), 2.0);
        let ember = 0.5 + 0.5 * sin(d.x * 7.0 + d.z * 5.0 + frame.time * 0.08);
        let nether_top = vec3<f32>(0.035, 0.006, 0.012);
        let nether_horizon = vec3<f32>(0.30, 0.045, 0.012);
        let nether = mix(nether_top, nether_horizon, h) + vec3<f32>(0.10, 0.018, 0.004) * ember * h;
        return vec4<f32>(max(nether, vec3<f32>(0.0)), 1.0);
    }
    if (frame.dimension == 2) {
        let h = pow(1.0 - clamp(d.y * 0.5 + 0.5, 0.0, 1.0), 2.4);
        let void_top = vec3<f32>(0.006, 0.004, 0.018);
        let void_horizon = vec3<f32>(0.075, 0.018, 0.12);
        let end_glow = pow(max(1.0 - abs(d.y), 0.0), 5.0);
        let end_sky = mix(void_top, void_horizon, h) + vec3<f32>(0.025, 0.008, 0.045) * end_glow;
        return vec4<f32>(max(end_sky, vec3<f32>(0.0)), 1.0);
    }
    let day = rtx_day_factor();
    let low = 1.0 - smoothstep(0.02, 0.45, frame.sun_direction.y);
    let zenith_day = vec3<f32>(0.10, 0.28, 0.72);
    let horizon_day = vec3<f32>(0.72, 0.78, 0.88);
    let zenith_night = vec3<f32>(0.003, 0.009, 0.035);
    let horizon_night = vec3<f32>(0.018, 0.035, 0.085);
    let h = pow(1.0 - clamp(d.y, 0.0, 1.0), 3.0);
    var col = mix(mix(zenith_night, zenith_day, day), mix(horizon_night, horizon_day, day), h);
    let sunset = vec3<f32>(1.0, 0.42, 0.16) * low * day * pow(1.0 - clamp(d.y, 0.0, 1.0), 2.0);
    col += sunset * (0.25 + color_warmth * 0.55);
    // Weather comes from Horizon's live frame state, not the Rain Reflections option.
    // frame.rain rises/falls with real rain and /weather rain; smoothstep avoids a hard pop.
    let rain_amount = smoothstep(0.015, 0.78, clamp(frame.rain, 0.0, 1.0));
    let thunder_amount = smoothstep(0.02, 0.85, clamp(frame.thunder, 0.0, 1.0));
    let storm_amount = clamp(max(rain_amount, thunder_amount * 0.82), 0.0, 1.0);
    let gray_zenith = vec3<f32>(0.285, 0.315, 0.35);
    let gray_horizon = vec3<f32>(0.39, 0.415, 0.445);
    let gray_sky = mix(gray_horizon, gray_zenith, smoothstep(0.0, 0.88, d.y));
    // Only the sky colour changes: no procedural cloud shapes, speckles or fake rain streaks.
    col = mix(col, gray_sky, storm_amount * 0.94);
    let horizon_mist = exp(-abs(d.y) * 7.0) * 0.075 * storm_amount;
    col = mix(col, vec3<f32>(0.405, 0.425, 0.45), horizon_mist);
    let sun_dot = max(dot(d, normalize(frame.sun_direction)), 0.0);
    let sun_visibility = 1.0 - storm_amount * 0.90;
    col += vec3<f32>(1.0, 0.82, 0.58) * pow(sun_dot, 850.0) * day * 2.0 * sun_visibility;
    col += vec3<f32>(1.0, 0.55, 0.25) * pow(sun_dot, 18.0) * day * 0.08 * sun_visibility;
    if (night_stars && day < 0.98 && d.y > 0.0) {
        col += rtx_starfield(d) * (1.0 - day);
    }
    if (night_aurora && day < 0.98 && d.y > 0.025 && d.y < 0.94) {
        col += rtx_aurora(d);
    }
    return vec4<f32>(max(col, vec3<f32>(0.0)), 1.0);
}
