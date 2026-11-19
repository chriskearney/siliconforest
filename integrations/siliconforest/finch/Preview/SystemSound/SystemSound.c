// SPDX-License-Identifier: MIT
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

typedef uint32_t SystemSoundID;
extern int32_t AudioServicesCreateSystemSoundID(CFURLRef, SystemSoundID *);
extern int32_t AudioServicesDisposeSystemSoundID(SystemSoundID);
extern int32_t AudioServicesGetProperty(uint32_t, uint32_t, const void *, uint32_t *, void *);
extern void AudioServicesPlayAlertSound(SystemSoundID);

void AudioServicesPlaySystemSound(SystemSoundID sound)
{
    // Preview uses legacy system alert 16. Play the configured local alert.
    if (sound == 16 || sound == 0x1000) {
        CFURLRef url = NULL;
        uint32_t size = sizeof(url);
        if (AudioServicesGetProperty('aurl', 0, NULL, &size, &url) != 0 || !url)
            return;
        SystemSoundID alert;
        if (AudioServicesCreateSystemSoundID(url, &alert) == 0) {
            AudioServicesPlayAlertSound(alert);
            // Playback takes its own copy of the samples before returning.
            AudioServicesDisposeSystemSoundID(alert);
        }
        CFRelease(url);
        return;
    }
    AudioServicesPlayAlertSound(sound);
}
