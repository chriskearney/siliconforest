/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors */
/*
 * SiliconForest stage 1 v2 (SF_AB_BOOT): chooses which slot's stage 2 to start, from the state
 * record sf/bootstate.bin on the boot partition (sf_ab.c), and falls back to the other slot when
 * the chosen one cannot be started. Read-only like every m1n1 storage path: this stage writes
 * nothing anywhere. The one try of an updated slot is used up by the system itself at its first
 * start (sf-bootslot early); see abboot/README.md for what that leaves open.
 *
 * Only the installer's own chainload target, <PARTUUID>;sf/boot.bin, is handled here. Any other
 * target is chainloaded exactly as stage 1 v1 does.
 */
#include "../build/build_cfg.h"

#ifdef SF_AB_BOOT

#include "chainload.h"
#include "fb.h"
#include "nvme.h"
#include "sf_ab.h"
#include "string.h"
#include "types.h"
#include "utils.h"

/* how long a reason stays on the screen before the fallback slot starts */
#define SF_AB_NOTICE_MS 8000

struct sf_ab_stage1 {
    char uuid[37];
    char **vars;
    size_t *var_cnt;
    size_t var_capacity;
    bool fatal;
};

static int sf_ab_try_slot(void *ctx, const struct sf_ab_candidate *c)
{
    struct sf_ab_stage1 *s = ctx;
    char spec[64];
    int ret;

    if (s->fatal)
        return -1;
    snprintf(spec, sizeof(spec), "%s;%s", s->uuid, sf_ab_boot_path(c->slot));
    printf("SiliconForest: slot %c, %s%s\n", sf_ab_slot_name(c->slot), sf_ab_boot_path(c->slot),
           c->check ? "" : " (not checked against the boot state)");
    ret = chainload_load_slot(spec, s->vars, s->var_cnt, s->var_capacity, c->check, c->bytes,
                              c->crc32);
    if (ret == -1)
        s->fatal = true; /* the storage controller is in an unknown state: try nothing else */
    return ret;
}

static void sf_ab_notice(void *ctx, int why, int slot)
{
    UNUSED(ctx);
    if (why == SF_AB_R_TRYING) {
        printf("SiliconForest: %s (slot %c)\n", sf_ab_reason_text(why), sf_ab_slot_name(slot));
        return;
    }
    fb_set_active(true);
    printf("\nSiliconForest: %s.\n"
           "  Starting slot %c (%s) instead. Nothing on the disk is changed by this.\n",
           sf_ab_reason_text(why), sf_ab_slot_name(slot), sf_ab_boot_path(slot));
    mdelay(SF_AB_NOTICE_MS);
}

int sf_ab_stage1_chainload(const char *spec, char **vars, size_t *var_cnt, size_t var_capacity)
{
    static const char slot_a[] = "sf/boot.bin";
    struct sf_ab_stage1 s;
    struct sf_ab_state st;
    struct sf_ab_plan plan;
    struct sf_ab_ops ops = {sf_ab_try_slot, sf_ab_notice, &s};
    const char *sep = strchr(spec, ';');
    char state_spec[64];
    void *buf = NULL;
    size_t size = 0;
    int load;

    if (!sep || sep - spec != 36 || strcmp(sep + 1, slot_a))
        return chainload_load(spec, vars, var_cnt, var_capacity);

    memset(&s, 0, sizeof(s));
    memcpy(s.uuid, spec, 36);
    s.vars = vars;
    s.var_cnt = var_cnt;
    s.var_capacity = var_capacity;

    snprintf(state_spec, sizeof(state_spec), "%s;" SF_AB_STATE_FILE, s.uuid);
    if (chainload_read_file(state_spec, &buf, &size)) {
        load = SF_AB_ABSENT;
        printf("SiliconForest: no boot state record: slot a, as installed\n");
    } else {
        load = sf_ab_parse(buf, size, &st, NULL);
        chainload_free_file(buf, size);
    }
    sf_ab_decide(load, load == SF_AB_OK ? &st : NULL, &plan);
    if (sf_ab_run(&plan, &ops) < 0) {
        printf("SiliconForest: no slot could be started\n");
        return -1;
    }
    return 0;
}

#endif
