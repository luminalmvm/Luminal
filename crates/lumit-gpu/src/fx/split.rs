//! Channel-offset kernels (docs/08 §3.6, §3.15): the classic RGB split, its
//! wavelength-dispersion sibling, and the always-radial chromatic aberration.

use crate::GpuContext;

use super::{work_texture, FxEngine};

/// One resolved RGB split (docs/08 §3.6). The linear-mode offset vector is
/// host-computed (`lumit_core::fx::rgb_split_offset`) so the kernel never
/// runs its own trigonometry.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RgbSplitOp {
    /// Linear-mode channel offset, raster pixels.
    pub dx: f32,
    pub dy: f32,
    /// Radial-mode peak offset (reached at the corner distance), raster px.
    pub amount_px: f32,
    pub radial: bool,
    /// 0..1, blended against the unprocessed input.
    pub mix: f32,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct RgbSplitParams {
    dx: f32,
    dy: f32,
    amount: f32,
    radial: u32,
    mix_amt: f32,
    _pad: [f32; 3],
}

/// One resolved spectral split — the RGB split's Wavelength mode (docs/08
/// §3.6, K-090), its own kernel so the classic mode stays byte-identical.
/// The offset vector and the wavelength basis both arrive host-computed
/// (`lumit_core::fx::rgb_split_offset` / `spectral_basis_vec4`), so the
/// kernel consumes exactly the CPU reference's numbers.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SpectralSplitOp {
    /// Linear-mode peak offset, raster pixels.
    pub dx: f32,
    pub dy: f32,
    /// Radial-mode peak offset (reached at the corner distance), raster px.
    pub amount_px: f32,
    pub radial: bool,
    /// Wavelength → linear-RGB basis rows (w unused), columns normalised.
    pub basis: [[f32; 4]; 9],
    /// 0..1, blended against the unprocessed input.
    pub mix: f32,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct SpectralSplitParams {
    basis: [[f32; 4]; 9],
    dx: f32,
    dy: f32,
    amount: f32,
    radial: u32,
    mix_amt: f32,
    _pad: [f32; 3],
}

/// One resolved chromatic aberration (docs/08 §3.15): a dedicated,
/// always-radial sibling of [`RgbSplitOp`]'s own radial mode — no linear
/// offset or wavelength dispersion of its own.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ChromaticAberrationOp {
    /// Peak channel offset, raster pixels (reached at the corner distance).
    pub amount_px: f32,
    /// 0..1, blended against the unprocessed input.
    pub mix: f32,
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct ChromaticAberrationParams {
    amount: f32,
    mix_amt: f32,
    _pad0: f32,
    _pad1: f32,
}

impl FxEngine {
    /// Apply one RGB split (docs/08 §3.6) to a linear working texture,
    /// returning a new texture of the same size. Single pointwise pass with
    /// offset bilinear taps.
    pub fn rgb_split(
        &self,
        ctx: &GpuContext,
        src: &wgpu::Texture,
        w: u32,
        h: u32,
        op: &RgbSplitOp,
    ) -> wgpu::Texture {
        let out = work_texture(ctx, w, h, "fx-rgb-split-out");
        self.dispatch(
            ctx,
            &self.rgb_split,
            src,
            src,
            &out,
            w,
            h,
            bytemuck::bytes_of(&RgbSplitParams {
                dx: op.dx,
                dy: op.dy,
                amount: op.amount_px,
                radial: u32::from(op.radial),
                mix_amt: op.mix,
                _pad: [0.0; 3],
            }),
        );
        out
    }

    /// Apply one spectral split — the RGB split's Wavelength mode (docs/08
    /// §3.6, K-090) — to a linear working texture, returning a new texture
    /// of the same size. Single pointwise pass, nine offset bilinear taps
    /// weighted by the host-supplied wavelength basis.
    pub fn spectral_split(
        &self,
        ctx: &GpuContext,
        src: &wgpu::Texture,
        w: u32,
        h: u32,
        op: &SpectralSplitOp,
    ) -> wgpu::Texture {
        let out = work_texture(ctx, w, h, "fx-spectral-split-out");
        self.dispatch(
            ctx,
            &self.spectral_split,
            src,
            src,
            &out,
            w,
            h,
            bytemuck::bytes_of(&SpectralSplitParams {
                basis: op.basis,
                dx: op.dx,
                dy: op.dy,
                amount: op.amount_px,
                radial: u32::from(op.radial),
                mix_amt: op.mix,
                _pad: [0.0; 3],
            }),
        );
        out
    }

    /// Apply one chromatic aberration (docs/08 §3.15) to a linear working
    /// texture, returning a new texture of the same size. Single pointwise
    /// pass with offset bilinear taps — a dedicated, always-radial sibling
    /// of [`FxEngine::rgb_split`]'s own radial mode.
    pub fn chromatic_aberration(
        &self,
        ctx: &GpuContext,
        src: &wgpu::Texture,
        w: u32,
        h: u32,
        op: &ChromaticAberrationOp,
    ) -> wgpu::Texture {
        let out = work_texture(ctx, w, h, "fx-chromatic-aberration-out");
        self.dispatch(
            ctx,
            &self.chromatic_aberration,
            src,
            src,
            &out,
            w,
            h,
            bytemuck::bytes_of(&ChromaticAberrationParams {
                amount: op.amount_px,
                mix_amt: op.mix,
                _pad0: 0.0,
                _pad1: 0.0,
            }),
        );
        out
    }
}
