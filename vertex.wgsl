override water_wave_height: f32 = 0.018;
fn water_wave(xz: vec2<f32>, t: f32) -> f32 {
    // Broad, overlapping swells. Only vertex Y is displaced; no tessellation,
    // extra textures, screen-space ray marching, or additional texture samples.
    let a = xz.x * 0.72 + t * 0.82;
    let b = xz.y * 0.58 + t * 0.68;
    let c = (xz.x + xz.y) * 1.12 - t * 0.92;
    let d = (xz.x - xz.y) * 0.46 + t * 0.42;
    let swell = 0.58 * sin(a) * sin(b);
    let cross = 0.27 * sin(c);
    let long_swell = 0.15 * sin(d);
    return 0.5 + (swell + cross + long_swell) * 0.5;
}

fn vertex(input: VertexInput) -> vec3<f32> {
    if (input.fluid != 1u || input.face != 1u) {
        return input.position;
    }
    let world = input.position + frame.camera_position;
    // Keep the vertex profile fixed and inexpensive across shader stages.
    let t = frame.time * 0.55;
    let h = water_wave(world.xz, t) - 0.5;
    let displacement = h * clamp(water_wave_height, 0.0, 0.03);
    return input.position + vec3<f32>(0.0, displacement, 0.0);
}
