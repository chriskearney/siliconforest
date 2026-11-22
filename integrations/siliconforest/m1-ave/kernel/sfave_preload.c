/* SPDX-License-Identifier: GPL-2.0-only */
/* DPE application order/readback ported from ave_drv.c at
 * aquarat/apple-m-series-ave-driver 9ab14e45281e8f61fb499b760408028171a5f2b5.
 * No Apple register values are embedded. See ../NOTICE and tools/upstream/COPYING. */
#include "sfave/sfave_preload.h"
#ifdef KERNEL
#include <sys/errno.h>
#include <libkern/libkern.h>
#else
#include <errno.h>
#include <string.h>
#endif
static uint32_t le32(const unsigned char *p) {
    return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;
}
static int geometry(const struct sfave_preload *p) {
    if(!p || p->soc!=0x8103 || p->preloaded!=1 || p->segment_count!=2 || p->cold_reserved!=1)
        return ENODEV;
    if(!p->iboot || strcmp(p->iboot,"iBoot-8422.141.2") ||
       !p->rtkit || strcmp(p->rtkit,"RTKit-2062.141.1"))return ENOTSUP;
    for(unsigned n=0;n<2;n++) {
        const struct sfave_segment *s=&p->segment[n];
        if(!s->physical || (s->physical&0x3fff) || s->size!=(n?0x128000u:0xcc000u) ||
           s->flags!=(n?0u:3u) || s->physical>UINT64_MAX-s->size ||
           s->remap>UINT64_MAX-s->size || s->iova!=(n?0xcc000u:0u))return EINVAL;
    }
    const struct sfave_segment *a=&p->segment[0],*b=&p->segment[1];
    if(a->physical<b->physical+b->size && b->physical<a->physical+a->size)return EINVAL;
    return 0;
}
int sfave_validate_preload(const struct sfave_preload *p) {
    int e=geometry(p);
    if(e)return e;
    if(!p->firmware || strcmp(p->firmware,"AppleAVE2FW-6070.11.1"))return ENOTSUP;
    return 0;
}
int sfave_preload_bootable(const struct sfave_preload *p) {
    int e=geometry(p);
    if(e)return e;
    if(!p->firmware)return ENOTSUP;
    if(!strcmp(p->firmware,"AppleAVE2FW-6070.11.1") ||
       !strncmp(p->firmware,"AppleAVE2FW/",12) ||
       !strcmp(p->firmware,"6070.11.1"))return 0;
    return ENOTSUP;
}
int sfave_validate_dpe(const void *data,size_t size) {
    const unsigned char *p=data;
    if(!p || size!=24+40*12 || memcmp(p,"AVEDPE01",8) || le32(p+8)!=0 ||
       le32(p+12)!=1 || le32(p+16)!=39 || le32(p+20)!=0)return EINVAL;
    for(size_t i=24;i<size;i+=12)if((le32(p+i)&3) || le32(p+i)>=0x400)return EINVAL;
    return 0;
}
int sfave_program_dpe(const void *data,size_t size,const struct sfave_register_io *io) {
    int err=sfave_validate_dpe(data,size);
    if(err)return err;
    if(!io || !io->read || !io->write)return EINVAL;
    const unsigned char *p=data;
    for(size_t i=24;i<size;i+=12) {
        uint32_t offset=0xdc400u+le32(p+i),clear=le32(p+i+4),set=le32(p+i+8),old;
        if((err=io->read(io->context,offset,&old)))return err;
        if((err=io->write(io->context,offset,(old&~clear)|set)))return err;
    }
    /* Acis has no CAT entries. Enable only after all default/8-bit writes. */
    for(unsigned n=0;n<2;n++) {
        uint32_t offset=n?0xdc000u:0xdc400u,old;
        if((err=io->read(io->context,offset,&old)))return err;
        if((err=io->write(io->context,offset,old|(n?1u:3u))))return err;
    }
    /* The last (8-bit) table owns final masked values; enable bits at offset0
     * are deliberately outside this check, as in upstream. */
    for(size_t i=36;i<size;i+=12) {
        uint32_t offset=le32(p+i),clear=le32(p+i+4),set=le32(p+i+8),actual;
        if((err=io->read(io->context,0xdc400u+offset,&actual)))return err;
        if(offset==0)actual&=~3u;
        if((actual&clear)!=set)return EIO;
    }
    return 0;
}
