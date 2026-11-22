override godrays_enabled: bool = false;
override godrays_intensity: f32 = 0.48;
override godrays_count: i32 = 12;
override godrays_length: f32 = 0.72;
override godrays_quality: u32 = 1u;
override godrays_smoothing: f32 = 0.75;
override bloom_strength: f32 = 0.07;
override post_exposure: f32 = 1.0;
override color_saturation: f32 = 1.0;
override color_contrast: f32 = 1.03;
override color_vibrance: f32 = 0.12;
override color_temperature: f32 = 0.0;
override color_tint: f32 = 0.0;
override adaptive_color: bool = true;
override color_style: u32 = 0u;

// Photon-inspired depth-tested God Rays, adapted to Horizon Android API 0.1.
// One lane is used in Performance/Balanced; Cinematic adds two neighbouring lanes.
fn rtx_ray_lane(
    uv: vec2<f32>,
    to_sun: vec2<f32>,
    perp: vec2<f32>,
    lane_px: f32,
    samples: i32,
    jitter: f32
) -> f32 {
    var acc = 0.0;
    var weight_sum = 0.0;
    for (var i: i32 = 0; i < 12; i = i + 1) {
        if (i >= samples) { break; }
        let t = (f32(i) + jitter) / f32(samples);
        let suv = uv + to_sun * (t * clamp(godrays_length, 0.1, 1.0)) +
                  perp * lane_px;
        if (suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0) {
            let depth = depth_at(suv);
            // Horizon uses reversed depth: sky samples are at/near zero.
            let soft_depth = mix(0.000005, 0.00035, clamp(godrays_smoothing, 0.0, 1.0));
            let visible = 1.0 - smoothstep(0.000001, soft_depth, depth);
            let weight = 1.0 - t * 0.45;
            acc += visible * weight;
            weight_sum += weight;
        }
    }
    return acc / max(weight_sum, 0.001);
}

fn rtx_sun_shafts(uv: vec2<f32>, sun_uv: vec2<f32>, samples: i32) -> f32 {
    let to_sun = sun_uv - uv;
    let perp = normalize(vec2<f32>(-to_sun.y, to_sun.x) + vec2<f32>(0.000001, 0.0));
    let pixel = floor(uv * frame.resolution);
    let jitter = clamp(rtx_hash21(pixel), 0.02, 0.98);
    var visibility = 0.0;
    if (godrays_quality == 2u) {
        let px = 1.25 / max(frame.resolution.y, 1.0);
        visibility = (
            rtx_ray_lane(uv, to_sun, perp, -px, samples, jitter) +
            rtx_ray_lane(uv, to_sun, perp, 0.0, samples, jitter) +
            rtx_ray_lane(uv, to_sun, perp, px, samples, jitter)
        ) / 3.0;
    } else {
        visibility = rtx_ray_lane(uv, to_sun, perp, 0.0, samples, jitter);
    }
    let mu = clamp(dot(normalize(to_sun + vec2<f32>(0.000001)), normalize(vec2<f32>(0.000001, 0.0) + to_sun)), 0.0, 1.0);
    let shaft = smoothstep(0.12, 0.62, visibility);
    return shaft * (0.72 + 0.28 * visibility) * (0.75 + 0.25 * mu);
}

fn rtx_color_grade(source: vec3<f32>) -> vec3<f32> {
    var color = max(source, vec3<f32>(0.0));
    let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
    color = mix(vec3<f32>(luma), color, max(color_saturation, 0.0));
    let vibrance = clamp(color_vibrance, 0.0, 1.0);
    let chroma = max(color.r, max(color.g, color.b)) - min(color.r, min(color.g, color.b));
    color = mix(color, mix(vec3<f32>(luma), color, 1.0 + vibrance * (1.0 - clamp(chroma, 0.0, 1.0))), vibrance);
    color = (color - vec3<f32>(0.5)) * max(color_contrast, 0.0) + vec3<f32>(0.5);
    let temp = clamp(color_temperature, -1.0, 1.0);
    let tint = clamp(color_tint, -1.0, 1.0);
    color *= vec3<f32>(1.0 + temp * 0.10 + tint * 0.035, 1.0 - tint * 0.055, 1.0 - temp * 0.10 + tint * 0.035);
    let day = rtx_day_factor();
    let sunset = (1.0 - smoothstep(0.02, 0.28, abs(frame.sun_direction.y))) * (1.0 - day * 0.15);
    if (adaptive_color && color_style == 0u) {
        color *= mix(vec3<f32>(0.94, 0.97, 1.04), vec3<f32>(1.035, 1.005, 0.965), sunset * 0.45);
    }
    // 0 RealLife, 1 Golden Cinema, 2 Vibrant Fantasy, 3 Teal & Orange,
    // 4 Dark Fantasy, 5 Dreamcore, 6 Arctic Blue, 7 Apocalypse,
    // 8 Emerald Night, 9 Muted Film.
    if (color_style == 1u) {
        color *= mix(vec3<f32>(1.04, 1.015, 0.94), vec3<f32>(1.08, 1.025, 0.91), smoothstep(0.18, 1.0, luma));
    } else if (color_style == 2u) {
        color = mix(vec3<f32>(luma), color, 1.28) * vec3<f32>(1.02, 1.015, 1.035);
    } else if (color_style == 3u) {
        let shadows = 1.0 - smoothstep(0.08, 0.48, luma);
        let highlights = smoothstep(0.28, 0.9, luma);
        color *= mix(vec3<f32>(0.82, 1.02, 1.12), vec3<f32>(1.12, 0.96, 0.82), highlights);
        color = mix(color, color * vec3<f32>(0.90, 1.04, 1.12), shadows * 0.32);
    } else if (color_style == 4u) {
        color *= vec3<f32>(0.86, 0.91, 1.02);
        color = mix(vec3<f32>(luma), color, 0.86);
    } else if (color_style == 5u) {
        color = mix(vec3<f32>(luma), color, 0.88) * vec3<f32>(1.04, 0.99, 1.07);
        color = color * 0.94 + vec3<f32>(0.012, 0.008, 0.022);
    } else if (color_style == 6u) {
        color = mix(vec3<f32>(luma), color * vec3<f32>(0.90, 1.0, 1.13), 0.94);
    } else if (color_style == 7u) {
        color = mix(vec3<f32>(luma), color * vec3<f32>(1.12, 0.88, 0.76), 1.08);
    } else if (color_style == 8u) {
        color = mix(vec3<f32>(luma), color * vec3<f32>(0.70, 1.10, 0.88), 0.90);
        color *= vec3<f32>(0.88, 1.02, 0.96);
    } else if (color_style == 9u) {
        color = mix(vec3<f32>(luma), color, 0.72) * vec3<f32>(1.02, 1.00, 0.96);
        color = (color - vec3<f32>(0.45)) * 0.92 + vec3<f32>(0.45);
    }
    return max(color, vec3<f32>(0.0));
}

fn post(input: PostInput) -> vec4<f32> {
    var color = max(input.color.rgb, vec3<f32>(0.0));
    if (godrays_enabled && frame.dimension == 0 && frame.eye_in == 0u && frame.sun_direction.y > -0.04) {
        let sun_view = (frame.view * vec4<f32>(frame.sun_direction, 0.0)).xyz;
        let clip = frame.projection * vec4<f32>(sun_view, 1.0);
        if (clip.w > 0.02) {
            let ndc = clip.xy / clip.w;
            let sun_uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
            let near_screen = sun_uv.x > -0.25 && sun_uv.x < 1.25 && sun_uv.y > -0.25 && sun_uv.y < 1.25;
            if (near_screen) {
                var samples = clamp(godrays_count, 4, 12);
                if (godrays_quality == 0u) { samples = min(samples, 6); }
                if (godrays_quality == 1u) { samples = min(samples, 8); }
                let shafts = rtx_sun_shafts(input.uv, sun_uv, samples);
                let sun_screen_distance = length(sun_uv - input.uv);
                let phase = 0.25 + pow(max(1.0 - sun_screen_distance * 0.7, 0.0), 4.0) * 1.8;
                let sun_gate = smoothstep(-0.08, 0.10, frame.sun_direction.y);
                let edge = smoothstep(-0.05, 0.48, 1.0 - sun_screen_distance);
                let distance_fade = 1.0 / (1.0 + length(sun_uv - input.uv) * 0.55);
                let rain_attenuation = 1.0 - clamp(frame.rain * 0.8 + frame.thunder * 0.2, 0.0, 0.9);
                var quality_gain = 1.0;
                if (godrays_quality == 0u) { quality_gain = 0.82; }
                if (godrays_quality == 2u) { quality_gain = 1.12; }
                color += vec3<f32>(1.0, 0.82, 0.62) * shafts * phase *
                         godrays_intensity * quality_gain * sun_gate * edge *
                         distance_fade * rain_attenuation * 0.24;
                if (bloom_strength > 0.0) {
                    let d = dot(sun_uv - input.uv, sun_uv - input.uv);
                    let halo = 0.9 / (1.0 + d * 900.0) + 0.30 / (1.0 + d * 30.0);
                    color += vec3<f32>(1.0, 0.82, 0.62) * halo * bloom_strength *
                             sun_gate * edge * rain_attenuation * 0.12;
                }
            }
        }
    }
    // Rain reflections/droplets are composited per material in material.wgsl.
    // Do not apply a full-screen gray veil, exposure lift, or vignette here.
    color *= max(post_exposure, 0.0);
    color = rtx_color_grade(color);
    let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
    let glow = max(luma - 0.72, 0.0) * bloom_strength;
    color += color * glow;
    color = color / (vec3<f32>(1.0) + color * 0.16);
    return vec4<f32>(color, input.color.a);
}
