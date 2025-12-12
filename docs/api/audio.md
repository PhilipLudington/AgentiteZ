# Audio System

Sound effects and music playback built on SDL3 (`src/audio.zig`).

## Features

- **Sound effects** - Load and play WAV files with automatic format conversion
- **Background music** - Looping music playback with pause/resume
- **Volume control** - Master, sound effects, and music channel volumes
- **2D panning** - Stereo positioning (-1.0 left to +1.0 right)
- **Channel pooling** - 32 simultaneous sound channels
- **Thread-safe** - Mutex-protected callback for audio mixing

## Usage

### Basic Setup

```zig
const audio = @import("AgentiteZ").audio;

// Initialize audio system
var audio_system = try audio.AudioSystem.init(allocator);
defer audio_system.deinit();

// Load sounds
var explosion = try audio_system.loadSound("sounds/explosion.wav");
defer explosion.deinit();

var music = try audio_system.loadMusic("music/theme.wav");
defer music.deinit();
```

### Playing Sounds

```zig
// Play sound with options
const handle = audio_system.playSoundEx(&explosion, .{
    .volume = 0.8,
    .pan = -0.5, // Slightly left
    .loop = false,
});

// Check if sound is still playing
if (audio_system.isPlaying(handle)) {
    // Still playing...
}

// Stop specific sound
audio_system.stopSound(handle);

// Stop all sounds
audio_system.stopAllSounds();
```

### Music Control

```zig
// Play background music (loops by default)
audio_system.playMusic(&music);

// Control music
audio_system.pauseMusic();
audio_system.resumeMusic();
audio_system.setMusicChannelVolume(0.7);

// Control master volume
audio_system.setMasterVolume(0.9);
```

## Volume Hierarchy

- `master_volume` - Affects all audio output
- `sound_volume` - Affects all sound effects (multiplied with master)
- `global_music_volume` - Affects music playback (multiplied with master)
- Per-sound `volume` - Individual sound volume (multiplied with sound_volume and master)
- Per-music `music_volume` - Current track volume (multiplied with global_music_volume and master)

## Data Structures

- `AudioSystem` - Main system managing channels, mixing, and playback
- `Sound` - Loaded sound effect (converted to float32 stereo)
- `Music` - Loaded music track (converted to float32 stereo)
- `SoundHandle` - Handle to a playing sound instance
- `PlayOptions` - Volume, pan, and loop settings

## Technical Details

- Output format: 48kHz, stereo, float32
- Audio is mixed in a callback using SDL3's audio stream API
- All input formats automatically converted to device format
- Channel stealing when all 32 channels are in use

## Tests

27 tests covering clamp, handle conversion, panning, volume mixing.
