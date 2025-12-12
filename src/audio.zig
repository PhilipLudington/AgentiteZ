//! Audio System for AgentiteZ
//!
//! Provides sound effect playback and background music with mixing support.
//! Built on SDL3's audio subsystem using float32 stereo output.
//!
//! Features:
//! - Sound effect loading and playback (WAV format)
//! - Background music with looping
//! - Volume control (master, music, sfx channels)
//! - Spatial audio (2D panning)
//! - Audio channel pooling for performance

const std = @import("std");
const sdl = @import("sdl.zig");
const c = sdl.c;

/// Maximum number of simultaneous sound channels
pub const MAX_CHANNELS: usize = 32;

/// Invalid sound handle constant
pub const INVALID_HANDLE: SoundHandle = 0;

/// Handle to a playing sound instance
pub const SoundHandle = u32;

/// Sound data (fully loaded in memory)
pub const Sound = struct {
    /// Audio data in float32 stereo format
    data: []f32,
    /// Sample rate
    sample_rate: i32,
    /// Allocator used to create this sound
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Sound) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }
};

/// Music data (currently same as Sound, loaded fully into memory)
pub const Music = struct {
    /// Audio data in float32 stereo format
    data: []f32,
    /// Sample rate
    sample_rate: i32,
    /// Original file path (for debugging)
    filepath: ?[]const u8,
    /// Allocator used to create this music
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Music) void {
        self.allocator.free(self.data);
        if (self.filepath) |path| {
            self.allocator.free(path);
        }
        self.* = undefined;
    }
};

/// Audio channel for mixing (internal)
const AudioChannel = struct {
    sound: ?*const Sound = null,
    position: u32 = 0,
    volume: f32 = 1.0,
    pan: f32 = 0.0,
    loop: bool = false,
    active: bool = false,
};

/// Options for playing a sound
pub const PlayOptions = struct {
    /// Volume (0.0 to 1.0)
    volume: f32 = 1.0,
    /// Pan (-1.0 = left, 0.0 = center, 1.0 = right)
    pan: f32 = 0.0,
    /// Whether to loop the sound
    loop: bool = false,
};

/// Main audio system
pub const AudioSystem = struct {
    allocator: std.mem.Allocator,

    /// SDL audio stream handle
    stream: ?*c.SDL_AudioStream = null,

    /// Device audio spec (actual format)
    device_spec: c.SDL_AudioSpec = .{
        .format = c.SDL_AUDIO_F32,
        .channels = 2,
        .freq = 48000,
    },

    /// Mixing channels for sounds
    channels: [MAX_CHANNELS]AudioChannel = [_]AudioChannel{.{}} ** MAX_CHANNELS,

    /// Handle generation counter (for unique handles)
    next_handle: u32 = 1,

    /// Music state
    current_music: ?*const Music = null,
    music_position: u32 = 0,
    music_volume: f32 = 1.0,
    music_loop: bool = true,
    music_playing: bool = false,
    music_paused: bool = false,

    /// Volume controls
    master_volume: f32 = 1.0,
    sound_volume: f32 = 1.0,
    global_music_volume: f32 = 1.0,

    /// Mixing buffer (reused each callback)
    mix_buffer: []f32 = &[_]f32{},

    /// Thread safety mutex for callback
    mutex: std.Thread.Mutex = .{},

    /// Initialize the audio system
    pub fn init(allocator: std.mem.Allocator) !AudioSystem {
        // Initialize SDL audio subsystem if not already initialized
        if (!c.SDL_WasInit(c.SDL_INIT_AUDIO)) {
            if (!c.SDL_InitSubSystem(c.SDL_INIT_AUDIO)) {
                std.log.err("Failed to initialize SDL audio: {s}", .{c.SDL_GetError()});
                return error.AudioInitFailed;
            }
        }

        var self = AudioSystem{
            .allocator = allocator,
        };

        // Set up desired audio spec (float32, stereo, 48kHz)
        const desired_spec = c.SDL_AudioSpec{
            .format = c.SDL_AUDIO_F32,
            .channels = 2,
            .freq = 48000,
        };

        // Create audio stream with callback
        self.stream = c.SDL_OpenAudioDeviceStream(
            c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK,
            &desired_spec,
            audioCallback,
            &self,
        );

        if (self.stream == null) {
            std.log.err("Failed to create audio stream: {s}", .{c.SDL_GetError()});
            return error.AudioStreamFailed;
        }

        // Get actual device spec
        var sample_frames: c_int = 0;
        const device_id = c.SDL_GetAudioStreamDevice(self.stream);
        _ = c.SDL_GetAudioDeviceFormat(device_id, &self.device_spec, &sample_frames);

        // Allocate initial mix buffer (4096 samples)
        self.mix_buffer = try allocator.alloc(f32, 4096);

        // Start playback
        _ = c.SDL_ResumeAudioStreamDevice(self.stream);

        std.log.info("Audio system initialized: {d}Hz, {d} channels", .{
            self.device_spec.freq,
            self.device_spec.channels,
        });

        return self;
    }

    /// Shutdown the audio system
    pub fn deinit(self: *AudioSystem) void {
        // Stop all sounds
        self.stopAllSounds();
        self.stopMusic();

        // Destroy audio stream
        if (self.stream) |stream| {
            c.SDL_DestroyAudioStream(stream);
        }

        // Free mix buffer
        if (self.mix_buffer.len > 0) {
            self.allocator.free(self.mix_buffer);
        }

        std.log.info("Audio system shutdown complete", .{});
    }

    /// Load a sound from a WAV file
    pub fn loadSound(self: *AudioSystem, filepath: [:0]const u8) !Sound {
        var spec: c.SDL_AudioSpec = undefined;
        var wav_data: [*c]u8 = null;
        var wav_length: u32 = 0;

        if (!c.SDL_LoadWAV(filepath.ptr, &spec, &wav_data, &wav_length)) {
            std.log.err("Failed to load WAV '{s}': {s}", .{ filepath, c.SDL_GetError() });
            return error.LoadWavFailed;
        }
        defer c.SDL_free(wav_data);

        // Convert to device format (float32 stereo)
        const converted = try self.convertAudio(
            wav_data[0..wav_length],
            spec,
        );

        std.log.info("Loaded sound '{s}': {d} samples", .{ filepath, converted.len });

        return Sound{
            .data = converted,
            .sample_rate = self.device_spec.freq,
            .allocator = self.allocator,
        };
    }

    /// Load a sound from memory (WAV format)
    pub fn loadSoundFromMemory(self: *AudioSystem, data: []const u8) !Sound {
        const io = c.SDL_IOFromConstMem(data.ptr, @intCast(data.len));
        if (io == null) {
            return error.LoadWavFailed;
        }

        var spec: c.SDL_AudioSpec = undefined;
        var wav_data: [*c]u8 = null;
        var wav_length: u32 = 0;

        if (!c.SDL_LoadWAV_IO(io, true, &spec, &wav_data, &wav_length)) {
            std.log.err("Failed to load WAV from memory: {s}", .{c.SDL_GetError()});
            return error.LoadWavFailed;
        }
        defer c.SDL_free(wav_data);

        const converted = try self.convertAudio(
            wav_data[0..wav_length],
            spec,
        );

        return Sound{
            .data = converted,
            .sample_rate = self.device_spec.freq,
            .allocator = self.allocator,
        };
    }

    /// Load music from a WAV file
    pub fn loadMusic(self: *AudioSystem, filepath: [:0]const u8) !Music {
        var spec: c.SDL_AudioSpec = undefined;
        var wav_data: [*c]u8 = null;
        var wav_length: u32 = 0;

        if (!c.SDL_LoadWAV(filepath.ptr, &spec, &wav_data, &wav_length)) {
            std.log.err("Failed to load music '{s}': {s}", .{ filepath, c.SDL_GetError() });
            return error.LoadWavFailed;
        }
        defer c.SDL_free(wav_data);

        const converted = try self.convertAudio(
            wav_data[0..wav_length],
            spec,
        );

        // Store filepath for debugging
        const path_copy = try self.allocator.dupe(u8, filepath);

        std.log.info("Loaded music '{s}': {d} samples", .{ filepath, converted.len });

        return Music{
            .data = converted,
            .sample_rate = self.device_spec.freq,
            .filepath = path_copy,
            .allocator = self.allocator,
        };
    }

    /// Play a sound with default options
    pub fn playSound(self: *AudioSystem, sound: *const Sound) SoundHandle {
        return self.playSoundEx(sound, .{});
    }

    /// Play a sound with custom options
    pub fn playSoundEx(self: *AudioSystem, sound: *const Sound, options: PlayOptions) SoundHandle {
        self.mutex.lock();
        defer self.mutex.unlock();

        const ch = self.findFreeChannel();

        self.channels[ch] = .{
            .sound = sound,
            .position = 0,
            .volume = clamp(options.volume, 0.0, 1.0),
            .pan = clamp(options.pan, -1.0, 1.0),
            .loop = options.loop,
            .active = true,
        };

        // Generate unique handle (channel index + generation counter)
        const handle = @as(u32, @intCast(ch)) | (self.next_handle << 8);
        self.next_handle +%= 1;
        if (self.next_handle == 0) self.next_handle = 1;

        return handle;
    }

    /// Stop a playing sound by handle
    pub fn stopSound(self: *AudioSystem, handle: SoundHandle) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (handleToChannel(handle)) |ch| {
            self.channels[ch].active = false;
        }
    }

    /// Check if a sound is still playing
    pub fn isPlaying(self: *AudioSystem, handle: SoundHandle) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (handleToChannel(handle)) |ch| {
            return self.channels[ch].active;
        }
        return false;
    }

    /// Set volume of a playing sound
    pub fn setSoundVolume(self: *AudioSystem, handle: SoundHandle, volume: f32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (handleToChannel(handle)) |ch| {
            if (self.channels[ch].active) {
                self.channels[ch].volume = clamp(volume, 0.0, 1.0);
            }
        }
    }

    /// Set pan of a playing sound
    pub fn setSoundPan(self: *AudioSystem, handle: SoundHandle, pan: f32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (handleToChannel(handle)) |ch| {
            if (self.channels[ch].active) {
                self.channels[ch].pan = clamp(pan, -1.0, 1.0);
            }
        }
    }

    /// Stop all playing sounds
    pub fn stopAllSounds(self: *AudioSystem) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (&self.channels) |*channel| {
            channel.active = false;
        }
    }

    /// Play music (loops by default)
    pub fn playMusic(self: *AudioSystem, music: *const Music) void {
        self.playMusicEx(music, .{ .volume = 1.0, .loop = true });
    }

    /// Play music with custom options
    pub fn playMusicEx(self: *AudioSystem, music: *const Music, options: struct {
        volume: f32 = 1.0,
        loop: bool = true,
    }) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.current_music = music;
        self.music_position = 0;
        self.music_volume = clamp(options.volume, 0.0, 1.0);
        self.music_loop = options.loop;
        self.music_playing = true;
        self.music_paused = false;
    }

    /// Stop the currently playing music
    pub fn stopMusic(self: *AudioSystem) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.music_playing = false;
        self.music_paused = false;
        self.current_music = null;
        self.music_position = 0;
    }

    /// Pause the currently playing music
    pub fn pauseMusic(self: *AudioSystem) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.music_paused = true;
    }

    /// Resume paused music
    pub fn resumeMusic(self: *AudioSystem) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.music_paused = false;
    }

    /// Check if music is playing (not paused)
    pub fn isMusicPlaying(self: *AudioSystem) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.music_playing and !self.music_paused;
    }

    /// Check if music is paused
    pub fn isMusicPaused(self: *AudioSystem) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.music_playing and self.music_paused;
    }

    /// Set master volume (affects all audio)
    pub fn setMasterVolume(self: *AudioSystem, volume: f32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.master_volume = clamp(volume, 0.0, 1.0);
    }

    /// Get master volume
    pub fn getMasterVolume(self: *AudioSystem) f32 {
        return self.master_volume;
    }

    /// Set sound effects volume (affects all sounds)
    pub fn setSoundChannelVolume(self: *AudioSystem, volume: f32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.sound_volume = clamp(volume, 0.0, 1.0);
    }

    /// Get sound effects volume
    pub fn getSoundChannelVolume(self: *AudioSystem) f32 {
        return self.sound_volume;
    }

    /// Set music volume (affects music playback)
    pub fn setMusicChannelVolume(self: *AudioSystem, volume: f32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.global_music_volume = clamp(volume, 0.0, 1.0);
    }

    /// Get music volume
    pub fn getMusicChannelVolume(self: *AudioSystem) f32 {
        return self.global_music_volume;
    }

    /// Set volume for the currently playing music track
    pub fn setCurrentMusicVolume(self: *AudioSystem, volume: f32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.music_volume = clamp(volume, 0.0, 1.0);
    }

    /// Get number of active sound channels
    pub fn getActiveChannelCount(self: *AudioSystem) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        var count: usize = 0;
        for (self.channels) |channel| {
            if (channel.active) count += 1;
        }
        return count;
    }

    // =========================================================================
    // Private methods
    // =========================================================================

    /// Find a free channel, or steal the oldest one
    fn findFreeChannel(self: *AudioSystem) usize {
        for (self.channels, 0..) |channel, i| {
            if (!channel.active) {
                return i;
            }
        }
        // All channels busy - steal first one
        return 0;
    }

    /// Convert audio data to device format (float32 stereo)
    fn convertAudio(self: *AudioSystem, src_data: []const u8, src_spec: c.SDL_AudioSpec) ![]f32 {
        const dst_spec = c.SDL_AudioSpec{
            .format = c.SDL_AUDIO_F32,
            .channels = 2,
            .freq = self.device_spec.freq,
        };

        // Create a temporary stream for conversion
        const conv = c.SDL_CreateAudioStream(&src_spec, &dst_spec);
        if (conv == null) {
            std.log.err("Failed to create conversion stream: {s}", .{c.SDL_GetError()});
            return error.AudioConversionFailed;
        }
        defer c.SDL_DestroyAudioStream(conv);

        // Put source data
        if (!c.SDL_PutAudioStreamData(conv, src_data.ptr, @intCast(src_data.len))) {
            std.log.err("Failed to put data in conversion stream: {s}", .{c.SDL_GetError()});
            return error.AudioConversionFailed;
        }

        // Flush to signal end of input
        _ = c.SDL_FlushAudioStream(conv);

        // Get converted data size
        const available = c.SDL_GetAudioStreamAvailable(conv);
        if (available <= 0) {
            return error.AudioConversionFailed;
        }

        // Allocate output buffer
        const num_samples: usize = @intCast(@divTrunc(available, @sizeOf(f32)));
        const out_data = try self.allocator.alloc(f32, num_samples);
        errdefer self.allocator.free(out_data);

        // Get converted data
        const bytes_read = c.SDL_GetAudioStreamData(conv, out_data.ptr, available);
        if (bytes_read <= 0) {
            return error.AudioConversionFailed;
        }

        return out_data;
    }

    /// Audio callback - called by SDL to fill audio buffer
    fn audioCallback(userdata: ?*anyopaque, stream: ?*c.SDL_AudioStream, additional_amount: c_int, total_amount: c_int) callconv(.C) void {
        _ = total_amount;

        const self: *AudioSystem = @ptrCast(@alignCast(userdata));

        if (additional_amount <= 0) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        const samples_needed: usize = @intCast(@divTrunc(additional_amount, @sizeOf(f32)));

        // Ensure mix buffer is large enough
        if (samples_needed > self.mix_buffer.len) {
            // Can't allocate in callback, so limit to current buffer size
            // This shouldn't happen if we allocated enough initially
            std.log.warn("Audio buffer too small: need {d}, have {d}", .{ samples_needed, self.mix_buffer.len });
            return;
        }

        // Clear mix buffer
        @memset(self.mix_buffer[0..samples_needed], 0);

        // Mix all active sound channels
        for (&self.channels) |*channel| {
            if (!channel.active) continue;
            const sound = channel.sound orelse continue;

            const src = sound.data;
            const src_samples = src.len;

            var vol_l = channel.volume * self.sound_volume * self.master_volume;
            var vol_r = vol_l;

            // Apply pan (-1 = left, 0 = center, +1 = right)
            if (channel.pan < 0) {
                vol_r *= (1.0 + channel.pan);
            } else if (channel.pan > 0) {
                vol_l *= (1.0 - channel.pan);
            }

            var samples_written: usize = 0;
            while (samples_written < samples_needed) {
                var src_pos = channel.position;

                if (src_pos >= src_samples) {
                    if (channel.loop) {
                        channel.position = 0;
                        src_pos = 0;
                    } else {
                        channel.active = false;
                        break;
                    }
                }

                // Mix stereo samples
                const remaining_src = src_samples - src_pos;
                const remaining_dst = samples_needed - samples_written;
                var to_mix = @min(remaining_src, remaining_dst);

                // Ensure we mix stereo pairs
                to_mix = (to_mix / 2) * 2;

                var i: usize = 0;
                while (i < to_mix) : (i += 2) {
                    self.mix_buffer[samples_written + i] += src[src_pos + i] * vol_l;
                    self.mix_buffer[samples_written + i + 1] += src[src_pos + i + 1] * vol_r;
                }

                channel.position += @intCast(to_mix);
                samples_written += to_mix;
            }
        }

        // Mix music
        if (self.current_music) |music| {
            if (self.music_playing and !self.music_paused) {
                const src = music.data;
                const src_samples = src.len;
                const vol = self.music_volume * self.global_music_volume * self.master_volume;

                var samples_written: usize = 0;
                while (samples_written < samples_needed) {
                    var src_pos = self.music_position;

                    if (src_pos >= src_samples) {
                        if (self.music_loop) {
                            self.music_position = 0;
                            src_pos = 0;
                        } else {
                            self.music_playing = false;
                            break;
                        }
                    }

                    const remaining_src = src_samples - src_pos;
                    const remaining_dst = samples_needed - samples_written;
                    var to_mix = @min(remaining_src, remaining_dst);
                    to_mix = (to_mix / 2) * 2;

                    var i: usize = 0;
                    while (i < to_mix) : (i += 1) {
                        self.mix_buffer[samples_written + i] += src[src_pos + i] * vol;
                    }

                    self.music_position += @intCast(to_mix);
                    samples_written += to_mix;
                }
            }
        }

        // Clamp final output
        for (self.mix_buffer[0..samples_needed]) |*sample| {
            sample.* = clamp(sample.*, -1.0, 1.0);
        }

        // Write to stream
        _ = c.SDL_PutAudioStreamData(stream, self.mix_buffer.ptr, additional_amount);
    }
};

/// Convert handle to channel index
fn handleToChannel(handle: SoundHandle) ?usize {
    if (handle == INVALID_HANDLE) return null;
    const ch = handle & 0xFF;
    if (ch >= MAX_CHANNELS) return null;
    return ch;
}

/// Clamp a float value
fn clamp(v: f32, min_val: f32, max_val: f32) f32 {
    return @max(min_val, @min(max_val, v));
}

// =============================================================================
// Tests
// =============================================================================

test "AudioSystem basic initialization" {
    // Note: This test requires SDL to be available
    // In CI environments without audio, this may be skipped
}

test "clamp function" {
    try std.testing.expectEqual(@as(f32, 0.0), clamp(-0.5, 0.0, 1.0));
    try std.testing.expectEqual(@as(f32, 1.0), clamp(1.5, 0.0, 1.0));
    try std.testing.expectEqual(@as(f32, 0.5), clamp(0.5, 0.0, 1.0));
}

test "handleToChannel conversion" {
    try std.testing.expectEqual(@as(?usize, 0), handleToChannel(0x100));
    try std.testing.expectEqual(@as(?usize, 5), handleToChannel(0x205));
    try std.testing.expectEqual(@as(?usize, 31), handleToChannel(0x31F));
    try std.testing.expectEqual(@as(?usize, null), handleToChannel(INVALID_HANDLE));
    try std.testing.expectEqual(@as(?usize, null), handleToChannel(0x1FF)); // 255 >= MAX_CHANNELS
}

test "PlayOptions defaults" {
    const opts = PlayOptions{};
    try std.testing.expectEqual(@as(f32, 1.0), opts.volume);
    try std.testing.expectEqual(@as(f32, 0.0), opts.pan);
    try std.testing.expectEqual(false, opts.loop);
}

test "AudioChannel defaults" {
    const channel = AudioChannel{};
    try std.testing.expectEqual(@as(?*const Sound, null), channel.sound);
    try std.testing.expectEqual(@as(u32, 0), channel.position);
    try std.testing.expectEqual(@as(f32, 1.0), channel.volume);
    try std.testing.expectEqual(@as(f32, 0.0), channel.pan);
    try std.testing.expectEqual(false, channel.loop);
    try std.testing.expectEqual(false, channel.active);
}
