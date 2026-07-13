//! Byte-level colour helpers shared by every path that hands sRGB pixels to
//! the GPU or a colour picker — deliberately ungated (the Project panel needs
//! a solid's swatch even in a media-free build).

pub fn srgb_encode(v: f32) -> u8 {
    let v = v.clamp(0.0, 1.0);
    let e = if v <= 0.003_130_8 {
        12.92 * v
    } else {
        1.055 * v.powf(1.0 / 2.4) - 0.055
    };
    (e * 255.0).round() as u8
}

/// Inverse of [`srgb_encode`] (colour pickers hand back sRGB bytes).
pub fn srgb_decode(v: u8) -> f32 {
    let e = f32::from(v) / 255.0;
    if e <= 0.040_45 {
        e / 12.92
    } else {
        ((e + 0.055) / 1.055).powf(2.4)
    }
}

pub fn solid_rgba(c: kiriko_core::model::LinearColour) -> [u8; 4] {
    [
        srgb_encode(c.0[0]),
        srgb_encode(c.0[1]),
        srgb_encode(c.0[2]),
        (c.0[3].clamp(0.0, 1.0) * 255.0).round() as u8,
    ]
}

pub fn px_tile(px: &[u8; 4], w: u32, h: u32) -> Vec<u8> {
    std::iter::repeat_n(*px, (w * h) as usize)
        .flatten()
        .collect()
}
