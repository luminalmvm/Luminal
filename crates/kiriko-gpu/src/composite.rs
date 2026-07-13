//! The compositor seed (evaluator v0): transformed, opacity-blended layer
//! quads rendered bottom-up into the linear fp16 working format.
//!
//! In plain terms: each layer is a picture on a piece of glass; the
//! compositor stacks the glass. Position/scale/rotation move the glass (as a
//! full 4×4 matrix so 3D later needs no rewrite), opacity fades it, and the
//! stacking maths happens in linear light where "add two lights" is physically
//! correct — the same working format the colour golden test locks.

use crate::{ColourEngine, GpuContext, WORKING_FORMAT};
use glam::Mat4;

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct LayerUniform {
    matrix: [[f32; 4]; 4],
    opacity: f32,
    _pad: [f32; 3],
}

/// One layer to draw: a linear texture plus its placement in comp space.
pub struct CompositeLayer<'a> {
    /// Linear-light texture (run sources through ColourEngine::linearise).
    pub texture: &'a wgpu::Texture,
    /// Layer-pixel size the transform applies to (usually the texture size).
    pub size: (f32, f32),
    /// Comp-space placement: position of the layer's anchor in comp pixels,
    /// anchor point in layer pixels, scale in percent, rotation in degrees.
    pub position: (f32, f32),
    pub anchor: (f32, f32),
    pub scale: (f32, f32),
    pub rotation_deg: f32,
    /// 0..100 (UI percent; folded to 0..1 in the uniform).
    pub opacity: f32,
}

impl CompositeLayer<'_> {
    /// comp pixel space → NDC, with the layer transform applied.
    /// Full 4×4 (K-023). Order: quad(0..1) → layer px → −anchor → scale →
    /// rotate → +position → NDC.
    fn matrix(&self, comp_w: f32, comp_h: f32) -> Mat4 {
        let ndc_from_comp = Mat4::from_translation(glam::vec3(-1.0, 1.0, 0.0))
            * Mat4::from_scale(glam::vec3(2.0 / comp_w, -2.0 / comp_h, 1.0));
        let place = Mat4::from_translation(glam::vec3(self.position.0, self.position.1, 0.0))
            * Mat4::from_rotation_z(self.rotation_deg.to_radians())
            * Mat4::from_scale(glam::vec3(self.scale.0 / 100.0, self.scale.1 / 100.0, 1.0))
            * Mat4::from_translation(glam::vec3(-self.anchor.0, -self.anchor.1, 0.0));
        let quad_to_px = Mat4::from_scale(glam::vec3(self.size.0, self.size.1, 1.0));
        ndc_from_comp * place * quad_to_px
    }
}

pub struct Compositor {
    pipeline: wgpu::RenderPipeline,
    layout: wgpu::BindGroupLayout,
    sampler: wgpu::Sampler,
}

impl Compositor {
    pub fn new(ctx: &GpuContext) -> Self {
        let shader = ctx
            .device
            .create_shader_module(wgpu::include_wgsl!("composite.wgsl"));
        let layout = ctx
            .device
            .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("composite-layer"),
                entries: &[
                    wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 1,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 2,
                        visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
                        ty: wgpu::BindingType::Buffer {
                            ty: wgpu::BufferBindingType::Uniform,
                            has_dynamic_offset: false,
                            min_binding_size: None,
                        },
                        count: None,
                    },
                ],
            });
        let pipeline_layout = ctx
            .device
            .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("composite"),
                bind_group_layouts: &[&layout],
                push_constant_ranges: &[],
            });
        // Premultiplied over, in linear light.
        let blend = wgpu::BlendState {
            color: wgpu::BlendComponent {
                src_factor: wgpu::BlendFactor::One,
                dst_factor: wgpu::BlendFactor::OneMinusSrcAlpha,
                operation: wgpu::BlendOperation::Add,
            },
            alpha: wgpu::BlendComponent {
                src_factor: wgpu::BlendFactor::One,
                dst_factor: wgpu::BlendFactor::OneMinusSrcAlpha,
                operation: wgpu::BlendOperation::Add,
            },
        };
        let pipeline = ctx
            .device
            .create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("composite"),
                layout: Some(&pipeline_layout),
                vertex: wgpu::VertexState {
                    module: &shader,
                    entry_point: Some("vs_layer"),
                    buffers: &[],
                    compilation_options: Default::default(),
                },
                fragment: Some(wgpu::FragmentState {
                    module: &shader,
                    entry_point: Some("fs_layer"),
                    targets: &[Some(wgpu::ColorTargetState {
                        format: WORKING_FORMAT,
                        blend: Some(blend),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                    compilation_options: Default::default(),
                }),
                primitive: Default::default(),
                depth_stencil: None,
                multisample: Default::default(),
                multiview: None,
                cache: None,
            });
        let sampler = ctx.device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("composite-linear"),
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });
        Self {
            pipeline,
            layout,
            sampler,
        }
    }

    /// Render layers bottom-up over a linear background colour; returns the
    /// linear fp16 comp frame (feed to ColourEngine::display for the screen).
    pub fn composite(
        &self,
        ctx: &GpuContext,
        width: u32,
        height: u32,
        background: [f64; 4],
        layers: &[CompositeLayer<'_>],
    ) -> wgpu::Texture {
        let target = ctx.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("comp-frame"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: WORKING_FORMAT,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            view_formats: &[],
        });
        let view = target.create_view(&Default::default());

        // Per-layer bind groups first (uniforms are tiny; pooling later).
        let binds: Vec<wgpu::BindGroup> = layers
            .iter()
            .map(|layer| {
                let uniform = LayerUniform {
                    matrix: layer.matrix(width as f32, height as f32).to_cols_array_2d(),
                    opacity: (layer.opacity / 100.0).clamp(0.0, 1.0) as f32,
                    _pad: [0.0; 3],
                };
                let buffer = wgpu::util::DeviceExt::create_buffer_init(
                    &ctx.device,
                    &wgpu::util::BufferInitDescriptor {
                        label: Some("layer-uniform"),
                        contents: bytemuck::bytes_of(&uniform),
                        usage: wgpu::BufferUsages::UNIFORM,
                    },
                );
                ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
                    label: Some("composite-layer"),
                    layout: &self.layout,
                    entries: &[
                        wgpu::BindGroupEntry {
                            binding: 0,
                            resource: wgpu::BindingResource::TextureView(
                                &layer.texture.create_view(&Default::default()),
                            ),
                        },
                        wgpu::BindGroupEntry {
                            binding: 1,
                            resource: wgpu::BindingResource::Sampler(&self.sampler),
                        },
                        wgpu::BindGroupEntry {
                            binding: 2,
                            resource: buffer.as_entire_binding(),
                        },
                    ],
                })
            })
            .collect();

        let mut encoder = ctx
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("composite"),
            });
        {
            let mut rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("composite"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: background[0],
                            g: background[1],
                            b: background[2],
                            a: background[3],
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                ..Default::default()
            });
            rpass.set_pipeline(&self.pipeline);
            for bind in &binds {
                rpass.set_bind_group(0, bind, &[]);
                rpass.draw(0..6, 0..1);
            }
        }
        ctx.queue.submit([encoder.finish()]);
        target
    }
}

/// Convenience: full comp render → display-encoded sRGB texture.
pub fn render_for_display(
    ctx: &GpuContext,
    colour: &ColourEngine,
    compositor: &Compositor,
    width: u32,
    height: u32,
    background: [f64; 4],
    layers: &[CompositeLayer<'_>],
) -> wgpu::Texture {
    let linear = compositor.composite(ctx, width, height, background, layers);
    colour.display(ctx, &linear)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
mod tests {
    use super::*;

    fn solid_linear(
        ctx: &GpuContext,
        colour: &ColourEngine,
        rgba8: [u8; 4],
        w: u32,
        h: u32,
    ) -> wgpu::Texture {
        let px: Vec<u8> = std::iter::repeat(rgba8)
            .take((w * h) as usize)
            .flatten()
            .collect();
        let src = colour.upload_srgb8(ctx, &px, w, h);
        colour.linearise(ctx, &src)
    }

    fn srgb_encode(linear: f64) -> f64 {
        if linear <= 0.003_130_8 {
            12.92 * linear
        } else {
            1.055 * linear.powf(1.0 / 2.4) - 0.055
        }
    }
    fn srgb_decode(encoded: f64) -> f64 {
        if encoded <= 0.040_45 {
            encoded / 12.92
        } else {
            ((encoded + 0.055) / 1.055).powf(2.4)
        }
    }

    /// Half-opacity sRGB-red over sRGB-green background must blend in LINEAR
    /// light — the physically-correct result, distinct from naive byte
    /// averaging by ~19 code values on the red channel.
    #[test]
    fn blending_happens_in_linear_light() {
        let Ok(ctx) = GpuContext::headless() else {
            eprintln!("skipping: no GPU adapter");
            return;
        };
        let colour = ColourEngine::new(&ctx);
        let compositor = Compositor::new(&ctx);

        let red = solid_linear(&ctx, &colour, [255, 0, 0, 255], 4, 4);
        let layer = CompositeLayer {
            texture: &red,
            size: (4.0, 4.0),
            position: (0.0, 0.0),
            anchor: (0.0, 0.0),
            scale: (100.0, 100.0),
            rotation_deg: 0.0,
            opacity: 50.0,
        };
        // Background: linear green = sRGB 0,255,0 decoded.
        let g_lin = srgb_decode(1.0);
        let shown = render_for_display(
            &ctx,
            &colour,
            &compositor,
            4,
            4,
            [0.0, g_lin, 0.0, 1.0],
            &[layer],
        );
        let back = colour.readback8(&ctx, &shown).unwrap();

        // Expected: 0.5·linear(red) over linear(green), then sRGB-encoded.
        let expect_r = (srgb_encode(0.5 * srgb_decode(1.0)) * 255.0).round() as i16;
        let expect_g = (srgb_encode(0.5 * srgb_decode(1.0)) * 255.0).round() as i16;
        let (r, g, b) = (i16::from(back[0]), i16::from(back[1]), i16::from(back[2]));
        assert!((r - expect_r).abs() <= 2, "r {r} vs {expect_r}");
        assert!((g - expect_g).abs() <= 2, "g {g} vs {expect_g}");
        assert!(b <= 2, "b {b}");
        // And the linear result is NOT the gamma-naive 128:
        assert!((r - 128).abs() > 10, "blend looks gamma-naive: r {r}");
    }

    /// A quarter-size quad placed at the centre covers exactly the centre
    /// quarter: transforms map comp pixels correctly (and the rest of the
    /// frame keeps the background).
    #[test]
    fn transforms_place_layers_in_comp_pixels() {
        let Ok(ctx) = GpuContext::headless() else {
            eprintln!("skipping: no GPU adapter");
            return;
        };
        let colour = ColourEngine::new(&ctx);
        let compositor = Compositor::new(&ctx);
        let white = solid_linear(&ctx, &colour, [255, 255, 255, 255], 8, 8);
        let layer = CompositeLayer {
            texture: &white,
            size: (8.0, 8.0),
            position: (8.0, 8.0), // centre of a 16×16 comp
            anchor: (4.0, 4.0),   // layer centre
            scale: (50.0, 50.0),  // 8px quad → 4px
            rotation_deg: 0.0,
            opacity: 100.0,
        };
        let shown = render_for_display(
            &ctx,
            &colour,
            &compositor,
            16,
            16,
            [0.0, 0.0, 0.0, 1.0],
            &[layer],
        );
        let back = colour.readback8(&ctx, &shown).unwrap();
        let px = |x: usize, y: usize| back[(y * 16 + x) * 4];
        // Centre 4×4 block is white; corners stay background.
        assert!(px(8, 8) > 250, "centre {}", px(8, 8));
        assert!(px(6, 6) > 250 && px(9, 9) > 250);
        assert!(px(0, 0) < 5 && px(15, 15) < 5);
        assert!(px(4, 8) < 5 && px(11, 8) < 5, "outside the scaled quad");
    }
}
