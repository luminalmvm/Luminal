//! The passes that carry their own bespoke bind-group layout rather than the
//! shared two-input one: depth-of-field lens blur (docs/08 DoF foundation),
//! the 3-D LUT lookup (docs/08 §3.11) and the adjustment-layer blend.

use crate::GpuContext;

use super::{work_texture, FxEngine};

/// One resolved depth-of-field pass (foundation for the planned DoF effects).
/// The per-pixel depth arrives as its own single-channel texture (see
/// [`upload_depth_map`] and [`FxEngine::dof`]); this uniform carries only the
/// scalars the kernel turns a depth into a circle-of-confusion radius with,
/// plus the host Mix. The near side (`d < focus`) uses `near_aperture`, the far
/// side `far_aperture`; both zero (or every pixel inside the sharp band) is a
/// bit-exact passthrough. `depth_invert` and `display` are u32 flags (to match
/// the WGSL uniform's scalar packing). 32 bytes: seven scalars plus one word of
/// tail padding to the 16-byte uniform stride.
#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct DofParams {
    focus: f32,
    range: f32,
    /// Near-side max CoC radius (depths in front of focus), raster px.
    near_aperture: f32,
    /// Far-side max CoC radius (depths behind focus), raster px.
    far_aperture: f32,
    mix_amt: f32,
    /// 0 = read the depth as-is, 1 = invert it (`d' = 1 - d`) before the CoC.
    depth_invert: u32,
    /// Diagnostic view: 0 = Rendered, 1 = Depth map, 2 = Focus map.
    display: u32,
    _pad: f32,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct AdjustParams {
    opacity: f32,
    _pad: [f32; 3],
}

/// One resolved 3D-LUT lookup (docs/08 §3.11; docs/impl/lut.md). The cube
/// itself arrives as its own 3D texture (see [`upload_lut_3d`] and
/// [`FxEngine::lut`]); this uniform carries only the edge length the shader
/// needs to turn a colour into grid coordinates and the host Mix. Domain is
/// assumed 0..1 (a domain remap is a documented follow-up, docs/impl/lut.md).
#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct LutParams {
    /// LUT edge length N (the cube holds `N³` samples).
    size: u32,
    /// 0..1, blended against the unprocessed input.
    mix: f32,
    _pad: [f32; 2],
}

impl FxEngine {
    /// Apply one depth-of-field lens blur to a linear working texture,
    /// returning a new texture of the same size. Backs the `dof` effect
    /// (docs/08 §3.22, docs/impl/layer-input.md): one pass where each output
    /// pixel reads its depth from the **red channel** of `depth` (values in
    /// `[0, 1]` by convention; the shader reads `.x`), optionally inverts it
    /// (`depth_invert`: `d' = 1 - d`, swapping near and far), turns it into a
    /// circle-of-confusion radius — zero inside `range` of `focus`, ramping smoothstep
    /// to `near_aperture` raster pixels on the near side (`d < focus`) or
    /// `far_aperture` on the far side at the depth extreme — and averages a
    /// box-weighted integer disc of that radius from `src`, edges clamped,
    /// then blends against the input by the host Mix. `display` selects the
    /// output view: 0 = Rendered (the blur above), 1 = Depth map (the
    /// post-invert depth as greyscale), 2 = Focus map (the smooth `1 - s`
    /// in-focus mask); the diagnostic views ignore the blur and Mix and are
    /// continuous, so the oracle covers them. `depth` must be the same
    /// size as `src`; because only its red is read (via `textureLoad`, not a
    /// sampler), it may be **any float texture** — the referenced depth layer
    /// rendered in the working `rgba16float` format (the effect's real depth
    /// input), or the exact R32Float map the §1.6 oracle uploads; both read the
    /// same red. `depth` is consumed exactly as `dof_reference` (the CPU
    /// oracle) reads it and the tap disc is byte-identical, so the two agree.
    /// Shares [`Self::mb_layout`] with Motion blur — the depth field is the one
    /// extra sampled input over the two-input convention. Both apertures zero,
    /// or a Mix of 0, is a bit-exact passthrough.
    #[allow(clippy::too_many_arguments)]
    pub fn dof(
        &self,
        ctx: &GpuContext,
        src: &wgpu::Texture,
        w: u32,
        h: u32,
        depth: &wgpu::Texture,
        focus: f32,
        range: f32,
        near_aperture: f32,
        far_aperture: f32,
        depth_invert: bool,
        display: u32,
        mix: f32,
    ) -> wgpu::Texture {
        use wgpu::util::DeviceExt;
        let out = work_texture(ctx, w, h, "fx-dof-out");
        let ubuf = ctx
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("fx-dof-params"),
                contents: bytemuck::bytes_of(&DofParams {
                    focus,
                    range,
                    near_aperture,
                    far_aperture,
                    mix_amt: mix,
                    depth_invert: u32::from(depth_invert),
                    display,
                    _pad: 0.0,
                }),
                usage: wgpu::BufferUsages::UNIFORM,
            });
        let view = |t: &wgpu::Texture| t.create_view(&Default::default());
        let bind = ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("fx-dof-bind"),
            layout: &self.mb_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&view(src)),
                },
                // orig-for-mix: a single pass, so the unprocessed original is
                // the source itself.
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::TextureView(&view(src)),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(&view(depth)),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: wgpu::BindingResource::TextureView(&view(&out)),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: ubuf.as_entire_binding(),
                },
            ],
        });
        let mut enc = ctx
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("fx-dof-enc"),
            });
        {
            let mut cpass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("fx-dof-pass"),
                timestamp_writes: None,
            });
            cpass.set_pipeline(&self.dof);
            cpass.set_bind_group(0, &bind, &[]);
            cpass.dispatch_workgroups(w.div_ceil(8), h.div_ceil(8), 1);
        }
        ctx.queue.submit([enc.finish()]);
        out
    }

    /// Apply one 3D-LUT lookup (docs/08 §3.11; docs/impl/lut.md) to a linear
    /// working texture, returning a new texture of the same size. One pass on
    /// **unpremultiplied** colour (§2.2 — a LUT is an arbitrary colour map):
    /// per output pixel, unpremultiply, map each channel to a grid coordinate
    /// in `[0, size-1]` (domain assumed 0..1, clamped), `textureLoad` the eight
    /// integer corners of `lut_tex` and trilinearly interpolate in f32 — **not**
    /// the hardware sampler, whose precision is not guaranteed bit-for-bit
    /// across GPUs (docs/impl/lut.md §3) — re-premultiply, then blend against
    /// the input by the host Mix. The cube is consumed exactly as
    /// `lumit_core::lut::Lut3d::sample` reads its red-fastest data, so the two
    /// agree (§1.6). Its own bind group (the cube is a 3D texture, the one
    /// binding no other kernel has). `mix == 0` is the bit-exact input.
    #[allow(clippy::too_many_arguments)]
    pub fn lut(
        &self,
        ctx: &GpuContext,
        src: &wgpu::Texture,
        w: u32,
        h: u32,
        lut_tex: &wgpu::Texture,
        size: u32,
        mix: f32,
    ) -> wgpu::Texture {
        use wgpu::util::DeviceExt;
        let out = work_texture(ctx, w, h, "fx-lut-out");
        let ubuf = ctx
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("fx-lut-params"),
                contents: bytemuck::bytes_of(&LutParams {
                    size,
                    mix,
                    _pad: [0.0; 2],
                }),
                usage: wgpu::BufferUsages::UNIFORM,
            });
        let view = |t: &wgpu::Texture| t.create_view(&Default::default());
        // The cube is a 3D texture; name its view dimension explicitly so the
        // binding matches the layout's `D3` regardless of the default.
        let lut_view = lut_tex.create_view(&wgpu::TextureViewDescriptor {
            dimension: Some(wgpu::TextureViewDimension::D3),
            ..Default::default()
        });
        let bind = ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("fx-lut-bind"),
            layout: &self.lut_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&view(src)),
                },
                // orig-for-mix: a single pass, so the unprocessed original is
                // the source itself.
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::TextureView(&view(src)),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(&view(&out)),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: ubuf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: wgpu::BindingResource::TextureView(&lut_view),
                },
            ],
        });
        let mut enc = ctx
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("fx-lut-enc"),
            });
        {
            let mut cpass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("fx-lut-pass"),
                timestamp_writes: None,
            });
            cpass.set_pipeline(&self.lut);
            cpass.set_bind_group(0, &bind, &[]);
            cpass.dispatch_workgroups(w.div_ceil(8), h.div_ceil(8), 1);
        }
        ctx.queue.submit([enc.finish()]);
        out
    }

    /// The adjustment-layer blend (docs/06 §1.5): per-channel lerp between
    /// the accumulated composite `below` and its effected copy `processed`,
    /// by `coverage`'s alpha (the layer's comp-space mask raster) times
    /// `opacity` (the layer opacity, 0..1). All three textures are comp
    /// sized; returns a new comp-sized working texture.
    #[allow(clippy::too_many_arguments)]
    pub fn adjust_blend(
        &self,
        ctx: &GpuContext,
        below: &wgpu::Texture,
        processed: &wgpu::Texture,
        coverage: &wgpu::Texture,
        w: u32,
        h: u32,
        opacity: f32,
    ) -> wgpu::Texture {
        use wgpu::util::DeviceExt;
        let out = work_texture(ctx, w, h, "fx-adjust-out");
        let ubuf = ctx
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("fx-adjust-params"),
                contents: bytemuck::bytes_of(&AdjustParams {
                    opacity,
                    _pad: [0.0; 3],
                }),
                usage: wgpu::BufferUsages::UNIFORM,
            });
        let bind = ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("fx-adjust-bind"),
            layout: &self.adjust_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(
                        &below.create_view(&Default::default()),
                    ),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::TextureView(
                        &processed.create_view(&Default::default()),
                    ),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(
                        &coverage.create_view(&Default::default()),
                    ),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: wgpu::BindingResource::TextureView(
                        &out.create_view(&Default::default()),
                    ),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: ubuf.as_entire_binding(),
                },
            ],
        });
        let mut enc = ctx
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("fx-adjust-enc"),
            });
        {
            let mut cpass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("fx-adjust-pass"),
                timestamp_writes: None,
            });
            cpass.set_pipeline(&self.adjust);
            cpass.set_bind_group(0, &bind, &[]);
            cpass.dispatch_workgroups(w.div_ceil(8), h.div_ceil(8), 1);
        }
        ctx.queue.submit([enc.finish()]);
        out
    }
}
