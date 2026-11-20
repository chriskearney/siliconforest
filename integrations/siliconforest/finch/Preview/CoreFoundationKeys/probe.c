// SPDX-License-Identifier: MIT
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>

extern const CFStringRef NSURLContentTypeKey;
extern const CFStringRef NSURLIsPackageKey;
extern const CFStringRef NSURLVolumeIsLocalKey;
extern const CFStringRef NSURLVolumeUUIDStringKey;
void CFLogTest(Boolean toConsole, CFStringRef format, ...);

int main(void)
{
    assert(CFEqual(NSURLContentTypeKey, CFSTR("NSURLContentTypeKey")));
    assert(CFEqual(NSURLIsPackageKey, CFSTR("NSURLIsPackageKey")));
    assert(CFEqual(NSURLVolumeIsLocalKey, CFSTR("NSURLVolumeIsLocalKey")));
    assert(CFEqual(NSURLVolumeUUIDStringKey, CFSTR("NSURLVolumeUUIDStringKey")));

    const char *home = getenv("HOME");
    char path[1024];
    assert(home && snprintf(path, sizeof(path), "%s/Library/Logs/CFLogTest.log", home) < sizeof(path));
    CFLogTest(false, CFSTR("Preview %@ %d"), CFSTR("key probe"), 42);
    CFLogTest(false, CFSTR("second record"));
    FILE *log = fopen(path, "r");
    assert(log);
    char line[128];
    assert(fgets(line, sizeof(line), log) && strcmp(line, "Preview key probe 42\n") == 0);
    assert(fgets(line, sizeof(line), log) && strcmp(line, "second record\n") == 0);
    fclose(log);
    CFLogTest(true, CFSTR("Preview console probe"));
    puts("CoreFoundation PASS for URL resource keys and formatted log append");
    return 0;
}
