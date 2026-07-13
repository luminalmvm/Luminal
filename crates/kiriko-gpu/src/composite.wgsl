// Layer compositing (docs/06-RENDER-PIPELINE.md render order, evaluator v0).
//
// Each layer draws as a textured quad. The vertex transform is a full 4×4
// (decision K-023: 4×4 from day one, so 3D bolts on without a rewrite).
// Blending is premultiplied-over in LINEAR light — the whole reason the
// working format exists: light adds correctly here.

struct LayerUniform {
    // comp pixel space → NDC, including the layer's transform.
    matrix: mat4x4<f32>,
    // x: opacity 0..1 · y: use_matte · z: matte luma (else alpha) · w: invert
    params: vec4<f32>,
    // xy: comp target size in pixels (normalises frag position to matte uv)
    target_size: vec4<f32>,
};

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> layer: LayerUniform;
// Comp-space matte (a rendered layer); 1×1 white when unused.
@group(0) @binding(3) var matte: texture_2d<f32>;

struct VsOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_layer(@builtin(vertex_index) i: u32) -> VsOut {
    // Unit quad 0..1 (two triangles, 6 vertices).
    var corners = array<vec2<f32>, 6>(
        vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.0, 1.0),
        vec2<f32>(1.0, 0.0), vec2<f32>(1.0, 1.0), vec2<f32>(0.0, 1.0),
    );
    let c = corners[i];
    var out: VsOut;
    out.pos = layer.matrix * vec4<f32>(c, 0.0, 1.0);
    out.uv = c;
    return out;
}

@fragment
fn fs_layer(in: VsOut) -> @location(0) vec4<f32> {
    let texel = textureSample(src, samp, in.uv);
    // Straight-alpha source → premultiplied output, opacity folded in.
    var a = texel.a * layer.params.x;
    if (layer.params.y > 0.5) {
        // Matte lives in comp space: sample at this fragment's comp position.
        let comp_uv = in.pos.xy / layer.target_size.xy;
        let m = textureSample(matte, samp, comp_uv);
        var strength = m.a;
        if (layer.params.z > 0.5) {
            // Luma matte (v0: luma of the premultiplied composite).
            strength = dot(m.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
        }
        if (layer.params.w > 0.5) {
            strength = 1.0 - strength;
        }
        a = a * clamp(strength, 0.0, 1.0);
    }
    return vec4<f32>(texel.rgb * a, a);
}
