/* SPDX-License-Identifier: MIT
   TextEdit asks NSSpellChecker about automatic substitution. Those methods
   are registered, and each one raises "is not implemented", so they have to
   be replaced rather than added. The answers are NO and the setters do
   nothing: TextEdit only stores the result as a default. */
#import <Foundation/Foundation.h>
#include <objc/runtime.h>

static BOOL sf_no(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    return NO;
}

static void sf_ignore(id self, SEL _cmd, BOOL value)
{
    (void)self;
    (void)_cmd;
    (void)value;
}

static void sf_put(Class cls, const char *name, IMP imp, const char *types)
{
    if (cls)
        class_replaceMethod(cls, sel_registerName(name), imp, types);
}

__attribute__((constructor))
static void sf_spell_install(void)
{
    Class cls = objc_lookUpClass("NSSpellChecker");
    if (!cls)
        return;
    Class meta = object_getClass((id)cls);
    const char *gets[] = {
        "isAutomaticDashSubstitutionEnabled",
        "isAutomaticDataDetectionEnabled",
        "isAutomaticLinkDetectionEnabled",
        "isAutomaticQuoteSubstitutionEnabled",
        "isAutomaticSpellingCorrectionEnabled",
        "isAutomaticTextCompletionEnabled",
        "isAutomaticTextReplacementEnabled",
        "isGrammarCheckingEnabled",
    };
    const char *sets[] = {
        "setAutomaticDashSubstitutionEnabled:",
        "setAutomaticDataDetectionEnabled:",
        "setAutomaticLinkDetectionEnabled:",
        "setAutomaticQuoteSubstitutionEnabled:",
        "setAutomaticSpellingCorrectionEnabled:",
        "setAutomaticTextCompletionEnabled:",
        "setAutomaticTextReplacementEnabled:",
        "setContinuousSpellCheckingEnabled:",
        "setGrammarCheckingEnabled:",
    };
    for (unsigned i = 0; i < sizeof gets / sizeof gets[0]; i++) {
        sf_put(cls, gets[i], (IMP)sf_no, "c@:");
        sf_put(meta, gets[i], (IMP)sf_no, "c@:");
    }
    for (unsigned i = 0; i < sizeof sets / sizeof sets[0]; i++) {
        sf_put(cls, sets[i], (IMP)sf_ignore, "v@:c");
        sf_put(meta, sets[i], (IMP)sf_ignore, "v@:c");
    }
}
