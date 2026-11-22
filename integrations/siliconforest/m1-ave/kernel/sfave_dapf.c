/* SPDX-License-Identifier: GPL-2.0-only */
/* T8103 subset of ave_dapf_program_instance/ave_dapf_program at
 * aquarat/apple-m-series-ave-driver 9ab14e45281e8f61fb499b760408028171a5f2b5.
 * The r4/start/end/r0 order derives from Asahi m1n1 dapf_init_t8020.
 * No debug firmware/DPE dumps or Linux debugfs paths are ported. See ../NOTICE. */
#include "sfave/sfave_dapf.h"
#ifdef KERNEL
#include <sys/errno.h>
#else
#include <errno.h>
#endif
int sfave_program_dapf(const struct sfave_preload *p,uint64_t start,uint64_t end,
 int cpu_stopped,const struct sfave_dapf_io *io) {
 int e=sfave_preload_bootable(p);
 if(e)return e;
 /* Only the known T8103 address window. End's low bits are dropped by
  * hardware; accept the live inclusive ADT endpoint or its readback form. */
 if(!cpu_stopped||!io||!io->read32||!io->write32||!io->read64||!io->write64||
    start!=0xf00000000ULL||(end&~3ULL)!=0xffffffffcULL||
    p->segment[1].remap<start||p->segment[1].remap>end||
    p->segment[1].size-1>end-p->segment[1].remap)return EINVAL;
 uint32_t locked;
 if((e=io->read32(io->context,SFAVE_DAPF_CPUDART,0xf0,&locked)))return e;
 if(locked&1)return EPERM;
 /* Exactly sixteen slots. T8103 has no separate ADT MMIO entry. Unused
  * slots are disabled; never pre-clear an enabled slot out of sequence. */
 for(unsigned i=0;i<16;i++) {
  uint32_t base=i*0x40,r0=i==0?0x11u:i==1?0x33u:0u,r4=i<2?1u:0u;
  uint64_t first=i==0?p->segment[0].physical:i==1?start:0;
  uint64_t last=i==0?p->segment[0].physical+p->segment[0].size-4:i==1?(end&~3ULL):0;
  if((e=io->write32(io->context,SFAVE_DAPF_FILTER,base+4,r4))||
     (e=io->write64(io->context,SFAVE_DAPF_FILTER,base+8,first))||
     (e=io->write64(io->context,SFAVE_DAPF_FILTER,base+0x10,last))||
     (e=io->write32(io->context,SFAVE_DAPF_FILTER,base,r0)))return e;
 }
 for(unsigned i=0;i<16;i++) {
  uint32_t base=i*0x40,r0,r4;uint64_t first,last;
  if((e=io->read32(io->context,SFAVE_DAPF_FILTER,base,&r0))||
     (e=io->read32(io->context,SFAVE_DAPF_FILTER,base+4,&r4))||
     (e=io->read64(io->context,SFAVE_DAPF_FILTER,base+8,&first))||
     (e=io->read64(io->context,SFAVE_DAPF_FILTER,base+0x10,&last)))return e;
  if(r0!=(i==0?0x11u:i==1?0x33u:0u)||r4!=(i<2?1u:0u)||
     first!=(i==0?p->segment[0].physical:i==1?start:0)||
     last!=(i==0?p->segment[0].physical+p->segment[0].size-4:i==1?(end&~3ULL):0))return EIO;
 }
 return 0;
}
