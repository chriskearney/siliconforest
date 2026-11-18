/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * stream-probe FILE: the streamed SFPlayerMedia on the machine, without a window or an audible sound (volume 0).
 * Plays the file through as a display would (one request per frame time), then checks the decoded window's
 * bounds, a seek inside the read-ahead window (no reader restart), a seek backward and one near the end (one
 * restart each, the right picture), the end of the file (the last picture, end of video), and the sound from a
 * position near the end until the queue has returned every buffer. Prints every picture's NV12 MD5 by
 * presentation time ("STREAM_FRAME pts md5") for comparison with an independent decoder. Exit 0 when all passed.
 */
#import <AVFoundation/AVFoundation.h>
#import "SFPlayerMedia.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static int failures;
static void check(BOOL ok, const char *what) { if (!ok) failures++; printf("STREAM_%s %s\n", ok ? "OK" : "FAIL", what); }
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static void pump(double interval) { double end = now() + interval; while (now() < end) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.005]]; }

static size_t frameAt(SFPlayerMedia *media, double seconds)
{
    size_t index = SIZE_MAX;
    CGImageRef image = [media copyImageAtTime:CMTimeMakeWithSeconds(seconds, 600) index:&index];
    if (image) CGImageRelease(image); else index = SIZE_MAX;
    return index;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    setenv("SF_PLAYER_DIGESTS", "1", 1);   /* (the player takes each picture's digest only when asked) */
    @autoreleasepool {
        if (argc != 2) { fprintf(stderr, "usage: stream-probe movie\n"); return 2; }
        Class mediaClass = NSClassFromString(@"SFPlayerMedia");
        if (!mediaClass) { fprintf(stderr, "no SFPlayerMedia in this AVFoundation\n"); return 2; }
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]] options:nil];
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        double duration = CMTimeGetSeconds(asset.duration), fps = track.nominalFrameRate > 0 ? track.nominalFrameRate : 30;
        printf("STREAM_FILE duration=%.3f fps=%.3f\n", duration, fps);

        double start = now();
        NSError *error = nil;
        SFPlayerMedia *media = [[mediaClass alloc] initWithAsset:asset error:&error];
        check(media != nil, "prepared");
        if (!media) { fprintf(stderr, "%s\n", error.description.UTF8String); return 1; }
        NSDictionary *prepared = [media statistics];
        printf("STREAM_PREPARED seconds=%.3f %s\n", now() - start, prepared.description.UTF8String);
        check([prepared[@"videoFrames"] unsignedIntegerValue] > 1 && [prepared[@"hardware"] boolValue], "first window decoded in hardware");
        check([prepared[@"framesHeld"] unsignedIntegerValue] <= 96 && [prepared[@"frameBytes"] unsignedLongLongValue] <= 256ull << 20, "first window within its bounds");

        /* the whole file at one request per frame time, as fast as the decoder allows */
        size_t last = 0, shown = 0, maxHeld = 0; unsigned long long maxBytes = 0; BOOL ordered = YES;
        size_t total = (size_t)llround(duration * fps);
        start = now();
        for (size_t n = 0; n < total; n++) {
            size_t index = frameAt(media, (n + 0.25) / fps);
            if (index == SIZE_MAX || index < last) ordered = NO;
            if (index != SIZE_MAX && (n == 0 || index != last)) shown++;
            if (index != SIZE_MAX) last = index;
            if (getenv("STREAM_TRACE") && n < 80) printf("STREAM_SEQ %zu t=%.4f index=%zu held=%s\n", n, (n + 0.25) / fps, index, [[[media statistics][@"framesHeld"] description] UTF8String]);
            NSDictionary *s = [media statistics];
            maxHeld = MAX(maxHeld, [s[@"framesHeld"] unsignedIntegerValue]);
            maxBytes = MAX(maxBytes, [s[@"frameBytes"] unsignedLongLongValue]);
        }
        NSDictionary *played = [media statistics];
        printf("STREAM_PLAYED seconds=%.3f shown=%zu of %zu last=%zu maxHeld=%zu maxMiB=%.1f %s\n", now() - start, shown, total, last, maxHeld, maxBytes / 1048576.0, played.description.UTF8String);
        check(ordered, "pictures come in order, one for every request");
        check(shown + 1 >= total && last + 1 >= total, "every picture of the file shown once");
        check(maxHeld <= 96 && maxBytes <= 256ull << 20, "the decoded window stays within its bounds");
        check([played[@"readerRestarts"] unsignedIntegerValue] == 0, "playing through needs no reader restart");

        /* inside the read-ahead window: no restart */
        size_t restarts = [[media statistics][@"readerRestarts"] unsignedIntegerValue];
        frameAt(media, 1.0);   /* (a seek back from the end, counted) */
        restarts = [[media statistics][@"readerRestarts"] unsignedIntegerValue];
        size_t a = frameAt(media, 1.0), b = frameAt(media, 1.5);
        check([[media statistics][@"readerRestarts"] unsignedIntegerValue] == restarts && labs((long)b - (long)llround(1.5 * fps)) <= 1, "a seek inside the read-ahead window reads nothing again");
        printf("STREAM_WINDOW at1.0=%zu at1.5=%zu\n", a, b);

        /* backward: one restart, the right picture */
        size_t back = frameAt(media, 0.5);
        check([[media statistics][@"readerRestarts"] unsignedIntegerValue] == restarts + 1 && labs((long)back - (long)llround(0.5 * fps)) <= 1, "a seek backward restarts once and shows its picture");

        /* near the end: one restart, the right picture */
        double nearEnd = duration - 0.2;
        size_t end = frameAt(media, nearEnd);
        check([[media statistics][@"readerRestarts"] unsignedIntegerValue] == restarts + 2 && labs((long)end - (long)floor(nearEnd * fps)) <= 1, "a seek near the end restarts once and shows its picture");
        printf("STREAM_NEAR_END t=%.3f index=%zu\n", nearEnd, end);

        /* the end of the file: the last picture stays, end of video */
        size_t after = frameAt(media, duration + 1);
        NSDictionary *ended = [media statistics];
        check([ended[@"endOfVideo"] boolValue] && after != SIZE_MAX && after + 2 >= total, "the end of the file keeps its last picture");

        /* sound from near the end until every buffer has come back, at volume 0 */
        if ([media hasAudio]) {
            check([media startAtSeconds:duration - 0.5 volume:0], "sound starts near the end");
            double deadline = now() + 5;
            while (![media isAudioDrained] && now() < deadline) pump(.02);
            NSDictionary *s = [media statistics];
            printf("STREAM_AUDIO clock=%.3f %s\n", [media clockSeconds], s.description.UTF8String);
            check([media isAudioDrained] && [s[@"audioQueued"] isEqual:s[@"audioFrames"]] && [s[@"error"] intValue] == 0, "the sound plays to the file's end and every buffer returns");
            [media pause];
        }

        NSDictionary *final = [media statistics];
        check([final[@"digestConflicts"] unsignedIntegerValue] == 0, "after every seek each time shows the same picture as in the play-through");
        check([[media frameDigests] count] == total, "no picture with a time the file does not have");
        for (NSDictionary *f in [media frameDigests]) printf("STREAM_FRAME %.9f %s\n", [f[@"pts"] doubleValue], [f[@"md5"] UTF8String]);
        /* the decoder thread must not keep the media alive: released, it stops */
        __weak SFPlayerMedia *weakMedia = media;
        media = nil;
        check(weakMedia == nil, "released with its decoder thread");
        printf("STREAM_RESULT failures=%d\n", failures);
    }
    return failures ? 1 : 0;
}
