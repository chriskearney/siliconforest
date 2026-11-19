/* SPDX-License-Identifier: MIT */
/* Existing System Sound API, real WAV completion through the retained PD queue. */
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
typedef uint32_t SystemSoundID;
typedef int32_t OSStatus;
extern OSStatus AudioServicesCreateSystemSoundID(CFURLRef,SystemSoundID *);
extern OSStatus AudioServicesDisposeSystemSoundID(SystemSoundID);
extern OSStatus AudioServicesAddSystemSoundCompletion(SystemSoundID,CFRunLoopRef,CFStringRef,void (*)(SystemSoundID,void *),void *);
extern void AudioServicesRemoveSystemSoundCompletion(SystemSoundID);
extern void AudioServicesPlaySystemSound(SystemSoundID);
static int completed;
static void done(SystemSoundID sound,void *context){(void)sound;(void)context;completed++;}
int main(int argc,char **argv){
    if(argc!=2)return 2;
    CFURLRef url=CFURLCreateFromFileSystemRepresentation(NULL,(const UInt8 *)argv[1],strlen(argv[1]),false);
    SystemSoundID sound=0;OSStatus status=AudioServicesCreateSystemSoundID(url,&sound);CFRelease(url);
    if(status || !sound)return 3;
    status=AudioServicesAddSystemSoundCompletion(sound,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode,done,NULL);
    if(status)return 4;
    AudioServicesPlaySystemSound(sound);
    for(int n=0;n<300 && !completed;n++)CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.01,true);
    AudioServicesRemoveSystemSoundCompletion(sound);
    status=AudioServicesDisposeSystemSoundID(sound);
    printf("system-sound completion=%d dispose=%d\n",completed,(int)status);
    return completed==1 && status==0?0:5;
}
