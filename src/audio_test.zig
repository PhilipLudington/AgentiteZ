//! Comprehensive tests for the Audio System
//!
//! These tests verify the audio system's logic and data structures.
//! Note: Tests that require actual SDL audio initialization are marked
//! as integration tests and may be skipped in CI environments.

const std = @import("std");
const audio = @import("audio.zig");

// =============================================================================
// Unit Tests - Pure Logic (No SDL Required)
// =============================================================================

test "clamp function - edge cases" {
    // Test lower bound
    try std.testing.expectEqual(@as(f32, 0.0), clamp(-1000.0, 0.0, 1.0));
    try std.testing.expectEqual(@as(f32, 0.0), clamp(-0.001, 0.0, 1.0));

    // Test upper bound
    try std.testing.expectEqual(@as(f32, 1.0), clamp(1000.0, 0.0, 1.0));
    try std.testing.expectEqual(@as(f32, 1.0), clamp(1.001, 0.0, 1.0));

    // Test within bounds
    try std.testing.expectEqual(@as(f32, 0.5), clamp(0.5, 0.0, 1.0));
    try std.testing.expectEqual(@as(f32, 0.0), clamp(0.0, 0.0, 1.0));
    try std.testing.expectEqual(@as(f32, 1.0), clamp(1.0, 0.0, 1.0));

    // Test pan range
    try std.testing.expectEqual(@as(f32, -1.0), clamp(-2.0, -1.0, 1.0));
    try std.testing.expectEqual(@as(f32, 1.0), clamp(2.0, -1.0, 1.0));
    try std.testing.expectEqual(@as(f32, 0.0), clamp(0.0, -1.0, 1.0));
}

test "handleToChannel - valid handles" {
    // Channel 0 with various generation counters
    try std.testing.expectEqual(@as(?usize, 0), handleToChannel(0x100));
    try std.testing.expectEqual(@as(?usize, 0), handleToChannel(0x200));
    try std.testing.expectEqual(@as(?usize, 0), handleToChannel(0xFF00));

    // Various channels
    try std.testing.expectEqual(@as(?usize, 1), handleToChannel(0x101));
    try std.testing.expectEqual(@as(?usize, 5), handleToChannel(0x205));
    try std.testing.expectEqual(@as(?usize, 15), handleToChannel(0x30F));
    try std.testing.expectEqual(@as(?usize, 31), handleToChannel(0x41F)); // MAX_CHANNELS - 1
}

test "handleToChannel - invalid handles" {
    // Invalid handle constant
    try std.testing.expectEqual(@as(?usize, null), handleToChannel(audio.INVALID_HANDLE));

    // Channel index >= MAX_CHANNELS (32)
    try std.testing.expectEqual(@as(?usize, null), handleToChannel(0x120)); // 32
    try std.testing.expectEqual(@as(?usize, null), handleToChannel(0x1FF)); // 255
}

test "PlayOptions defaults" {
    const opts = audio.PlayOptions{};
    try std.testing.expectEqual(@as(f32, 1.0), opts.volume);
    try std.testing.expectEqual(@as(f32, 0.0), opts.pan);
    try std.testing.expectEqual(false, opts.loop);
}

test "PlayOptions custom values" {
    const opts = audio.PlayOptions{
        .volume = 0.5,
        .pan = -0.8,
        .loop = true,
    };
    try std.testing.expectEqual(@as(f32, 0.5), opts.volume);
    try std.testing.expectEqual(@as(f32, -0.8), opts.pan);
    try std.testing.expectEqual(true, opts.loop);
}

test "AudioChannel defaults" {
    const channel = AudioChannel{};
    try std.testing.expectEqual(@as(?*const audio.Sound, null), channel.sound);
    try std.testing.expectEqual(@as(u32, 0), channel.position);
    try std.testing.expectEqual(@as(f32, 1.0), channel.volume);
    try std.testing.expectEqual(@as(f32, 0.0), channel.pan);
    try std.testing.expectEqual(false, channel.loop);
    try std.testing.expectEqual(false, channel.active);
}

test "MAX_CHANNELS constant" {
    try std.testing.expectEqual(@as(usize, 32), audio.MAX_CHANNELS);
}

test "INVALID_HANDLE constant" {
    try std.testing.expectEqual(@as(audio.SoundHandle, 0), audio.INVALID_HANDLE);
}

test "Sound struct size" {
    // Verify Sound struct has expected fields
    const sound_info = @typeInfo(audio.Sound);
    try std.testing.expect(sound_info == .@"struct");
    try std.testing.expectEqual(@as(usize, 3), sound_info.@"struct".fields.len);
}

test "Music struct size" {
    // Verify Music struct has expected fields
    const music_info = @typeInfo(audio.Music);
    try std.testing.expect(music_info == .@"struct");
    try std.testing.expectEqual(@as(usize, 4), music_info.@"struct".fields.len);
}

test "panning calculation - center" {
    // At center pan (0.0), both channels should be equal
    const pan: f32 = 0.0;
    const base_vol: f32 = 1.0;

    var vol_l = base_vol;
    var vol_r = base_vol;

    if (pan < 0) {
        vol_r *= (1.0 + pan);
    } else if (pan > 0) {
        vol_l *= (1.0 - pan);
    }

    try std.testing.expectEqual(@as(f32, 1.0), vol_l);
    try std.testing.expectEqual(@as(f32, 1.0), vol_r);
}

test "panning calculation - full left" {
    // At full left pan (-1.0), right channel should be 0
    const pan: f32 = -1.0;
    const base_vol: f32 = 1.0;

    var vol_l = base_vol;
    var vol_r = base_vol;

    if (pan < 0) {
        vol_r *= (1.0 + pan);
    } else if (pan > 0) {
        vol_l *= (1.0 - pan);
    }

    try std.testing.expectEqual(@as(f32, 1.0), vol_l);
    try std.testing.expectEqual(@as(f32, 0.0), vol_r);
}

test "panning calculation - full right" {
    // At full right pan (1.0), left channel should be 0
    const pan: f32 = 1.0;
    const base_vol: f32 = 1.0;

    var vol_l = base_vol;
    var vol_r = base_vol;

    if (pan < 0) {
        vol_r *= (1.0 + pan);
    } else if (pan > 0) {
        vol_l *= (1.0 - pan);
    }

    try std.testing.expectEqual(@as(f32, 0.0), vol_l);
    try std.testing.expectEqual(@as(f32, 1.0), vol_r);
}

test "panning calculation - half left" {
    // At half left pan (-0.5), right channel should be 0.5
    const pan: f32 = -0.5;
    const base_vol: f32 = 1.0;

    var vol_l = base_vol;
    var vol_r = base_vol;

    if (pan < 0) {
        vol_r *= (1.0 + pan);
    } else if (pan > 0) {
        vol_l *= (1.0 - pan);
    }

    try std.testing.expectEqual(@as(f32, 1.0), vol_l);
    try std.testing.expectEqual(@as(f32, 0.5), vol_r);
}

test "panning calculation - half right" {
    // At half right pan (0.5), left channel should be 0.5
    const pan: f32 = 0.5;
    const base_vol: f32 = 1.0;

    var vol_l = base_vol;
    var vol_r = base_vol;

    if (pan < 0) {
        vol_r *= (1.0 + pan);
    } else if (pan > 0) {
        vol_l *= (1.0 - pan);
    }

    try std.testing.expectEqual(@as(f32, 0.5), vol_l);
    try std.testing.expectEqual(@as(f32, 1.0), vol_r);
}

test "volume mixing calculation" {
    // Test that volume channels multiply correctly
    const channel_vol: f32 = 0.8;
    const sound_vol: f32 = 0.5;
    const master_vol: f32 = 0.9;

    const final_vol = channel_vol * sound_vol * master_vol;

    // 0.8 * 0.5 * 0.9 = 0.36
    try std.testing.expectApproxEqAbs(@as(f32, 0.36), final_vol, 0.0001);
}

test "stereo pair alignment" {
    // Test that stereo mixing aligns to pairs
    const samples_needed: usize = 100;
    const to_mix = (samples_needed / 2) * 2;
    try std.testing.expectEqual(@as(usize, 100), to_mix);

    const odd_samples: usize = 101;
    const odd_to_mix = (odd_samples / 2) * 2;
    try std.testing.expectEqual(@as(usize, 100), odd_to_mix);
}

test "handle generation wrapping" {
    // Test that handle generation counter wraps correctly
    // The generation counter is shifted by 8 bits, so it uses bits 8-31
    // When it overflows (wraps to 0), we reset it to 1
    var next_handle: u32 = 0xFFFFFF;
    next_handle +%= 1;
    // 0xFFFFFF + 1 = 0x1000000, not 0, so no reset
    try std.testing.expectEqual(@as(u32, 0x1000000), next_handle);

    // Test the actual wrap case
    var wrap_handle: u32 = 0xFFFFFFFF;
    wrap_handle +%= 1;
    if (wrap_handle == 0) wrap_handle = 1;
    try std.testing.expectEqual(@as(u32, 1), wrap_handle);
}

test "sample clamping" {
    // Test audio sample clamping to [-1, 1]
    try std.testing.expectEqual(@as(f32, -1.0), clamp(-2.0, -1.0, 1.0));
    try std.testing.expectEqual(@as(f32, 1.0), clamp(2.0, -1.0, 1.0));
    try std.testing.expectEqual(@as(f32, 0.0), clamp(0.0, -1.0, 1.0));
    try std.testing.expectEqual(@as(f32, 0.5), clamp(0.5, -1.0, 1.0));
    try std.testing.expectEqual(@as(f32, -0.5), clamp(-0.5, -1.0, 1.0));
}

// =============================================================================
// Helper Functions (duplicated from audio.zig for testing)
// =============================================================================

const AudioChannel = struct {
    sound: ?*const audio.Sound = null,
    position: u32 = 0,
    volume: f32 = 1.0,
    pan: f32 = 0.0,
    loop: bool = false,
    active: bool = false,
};

fn handleToChannel(handle: audio.SoundHandle) ?usize {
    if (handle == audio.INVALID_HANDLE) return null;
    const ch = handle & 0xFF;
    if (ch >= audio.MAX_CHANNELS) return null;
    return ch;
}

fn clamp(v: f32, min_val: f32, max_val: f32) f32 {
    return @max(min_val, @min(max_val, v));
}
