# System Sound playback for Preview

The private AudioToolbox wrapper provides `AudioServicesPlaySystemSound`
through the installed System Sound playback engine. Registered sounds
use their existing PCM buffers and completion callbacks. The two legacy
alert IDs use the configured local alert. The native probe registers a
silent WAV, plays it through the new entry point, checks one completion,
and disposes it.
