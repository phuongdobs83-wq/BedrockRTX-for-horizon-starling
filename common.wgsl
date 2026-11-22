const RTX_PI: f32 = 3.14159265;

fn rtx_hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn rtx_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = rtx_hash21(i);
    let b = rtx_hash21(i + vec2<f32>(1.0, 0.0));
    let c = rtx_hash21(i + vec2<f32>(0.0, 1.0));
    let d = rtx_hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn rtx_luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn rtx_day_factor() -> f32 {
    return smoothstep(-0.12, 0.28, frame.sun_direction.y);
}

// API 0.2 works in linear light. Use this only for authored display-space constants.
fn rtx_to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}
