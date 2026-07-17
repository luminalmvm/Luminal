// Separable gaussian blur (docs/08-EFFECTS.md §3.8) — one pass per axis,
// direction in the uniform. Mirrors lumit_core::fx::cpu::blur_gaussian
// op-for-op (§1.6: the CPU is the oracle): same σ = radius/2, same tap
// count ceil(radius), weights normalised over the FULL kernel regardless of
// edge policy, fixed tap order.

struct Params {
    dir: vec2<f32>,     // (1,0) horizontal pass, (0,1) vertical pass
    radius: f32,        // kernel half-width, px
    sigma: f32,         // radius * 0.5, clamped ≥ 1e-3
    edge: u32,          // 0 transparent, 1 repeat, 2 mirror
    mix_amt: f32,       // 0..1, blended against `orig` (1 on the h-pass)
    _pad: vec2<f32>,
};

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var orig: texture_2d<f32>;
@group(0) @binding(2) var dst: texture_storage_2d<rgba16float, write>;
@group(0) @binding(3) var<uniform> p: Params;

// Resolve a tap index under the edge policy; -1 means transparent (no tap).
fn edge_idx(i: i32, len: i32) -> i32 {
    if (i >= 0 && i < len) {
        return i;
    }
    if (p.edge == 1u) {
        return clamp(i, 0, len - 1);
    }
    if (p.edge == 2u) {
        var m = i;
        if (m < 0) {
            m = -m;
        } else {
            m = 2 * (len - 1) - m;
        }
        return clamp(m, 0, len - 1);
    }
    return -1;
}

@compute @workgroup_size(8, 8)
fn blur_pass(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size = vec2<i32>(textureDimensions(src));
    let xy = vec2<i32>(gid.xy);
    if (xy.x >= size.x || xy.y >= size.y) {
        return;
    }
    let r = i32(ceil(p.radius));
    var acc = vec4<f32>(0.0);
    if (r == 0) {
        acc = textureLoad(src, xy, 0);
    } else {
        let axis_len = select(size.y, size.x, p.dir.x > 0.5);
        let along = select(xy.y, xy.x, p.dir.x > 0.5);
        var wsum = 0.0;
        for (var i = -r; i <= r; i++) {
            let d = f32(i) / max(p.sigma, 1e-3);
            let wt = exp(-0.5 * d * d);
            wsum += wt;
            let q = edge_idx(along + i, axis_len);
            if (q >= 0) {
                var tap = xy;
                if (p.dir.x > 0.5) {
                    tap.x = q;
                } else {
                    tap.y = q;
                }
                acc += textureLoad(src, tap, 0) * wt;
            }
        }
        acc /= wsum;
    }
    let o = textureLoad(orig, xy, 0);
    textureStore(dst, xy, mix(o, acc, p.mix_amt));
}
