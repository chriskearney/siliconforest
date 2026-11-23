/* SPDX-License-Identifier: GPL-2.0-only */
/* Port of ave_ipc.c at aquarat/apple-m-series-ave-driver
 * 9ab14e45281e8f61fb499b760408028171a5f2b5. See ../NOTICE.
 * Only exact T8103/13.5, polling, one caller. No lenient ABI negotiation.
 * No raw firmware/DPE/log bytes are emitted by this transport. */
#include "sfave_ipc.h"
#ifdef KERNEL
#include <sys/errno.h>
#include <libkern/libkern.h>
#else
#include <errno.h>
#include <string.h>
#endif
#define DOORBELL 0x0cu
#define STATUS 0x10u
#define SCRATCH(n) (0x18u+4u*(n))
static int fail(struct sfave_ipc *p,int error) {
 p->phase=SFAVE_IPC_FAILED;return error;
}
static int send_message(struct sfave_ipc *p,const uint32_t m[4]) {
 int e;
 for(unsigned i=0;i<4;i++)if((e=p->ops.write(p->ops.context,SCRATCH(i),m[i])))return e;
 p->ops.barrier(p->ops.context);
 return p->ops.write(p->ops.context,DOORBELL,1);
}
static int receive_message(struct sfave_ipc *p,uint32_t m[4]) {
 int e;uint32_t status;
 for(unsigned n=0;n<AVE_BOOT_RECV_TIMEOUT_MS;n++) {
  if((e=p->ops.read(p->ops.context,STATUS,&status)))return e;
  if(status&1) {
   /* W1C before sampling scratch, as upstream RecvIOPMsg. No IRQ consumer. */
   if((e=p->ops.write(p->ops.context,STATUS,1)))return e;
   p->ops.barrier(p->ops.context);
   for(unsigned i=0;i<4;i++)if((e=p->ops.read(p->ops.context,SCRATCH(i),&m[i])))return e;
   return 0;
  }
  p->ops.delay_us(p->ops.context,1000);
 }
 return ETIMEDOUT;
}
int sfave_ipc_init(struct sfave_ipc *p,const struct sfave_preload *preload,
 const struct sfave_ipc_ops *ops,void *cpu,uint64_t iova,uint32_t bytes,
 uint64_t heap_iova,uint32_t heap_bytes) {
 int e=sfave_preload_bootable(preload);
 if(e)return e;
 if(!p||!ops||!ops->read||!ops->write||!ops->delay_us||!ops->barrier||!cpu||
    ((uintptr_t)cpu&63)||!iova||(iova&0x3fff)||bytes!=0x700000||
    iova>UINT64_MAX-bytes||!heap_iova||(heap_iova&0x3fff)||heap_bytes!=0xc0000||
    heap_iova>UINT64_MAX-heap_bytes||
    (iova<heap_iova+heap_bytes&&heap_iova<iova+bytes))return EINVAL;
 memset(p,0,sizeof(*p));p->ops=*ops;p->cpu=cpu;p->iova=iova;p->bytes=bytes;
 p->heap_iova=heap_iova;p->heap_bytes=heap_bytes;
 memset(cpu,0,bytes);return 0;
}
int sfave_ipc_configure(struct sfave_ipc *p) {
 if(!p||!p->cpu||p->phase!=SFAVE_IPC_IDLE)return EINVAL;
 /* T8103 row is DevID13/DevType10/ChipType7; no firmware cfg block. */
 const uint32_t scratch[3]={AVE_BOOT_MAGIC,0,13};int e;
 for(unsigned i=0;i<3;i++)if((e=p->ops.write(p->ops.context,SCRATCH(i),scratch[i])))return fail(p,e);
 p->ops.barrier(p->ops.context);p->phase=SFAVE_IPC_CONFIGURED;return 0;
}
void *sfave_ipc_from_fw(struct sfave_ipc *p,uint64_t fw,size_t bytes) {
 if(!p||!p->cpu||!p->fw_base||!bytes||fw<p->fw_base)return NULL;
 uint64_t off=fw-p->fw_base;
 if(off>=p->bytes||bytes>p->bytes-off)return NULL;
 return p->cpu+(size_t)off;
}
static int bind_channels(struct sfave_ipc *p,const struct ave_boot_abi *a) {
 uint32_t seen=0;
 struct ave_boot_desc descriptors[7];
 /* Validate ALL descriptors before any ring initialization writes. Strict
  * known-layout policy also rules out duplicate/overlapping slot arrays. */
 for(unsigned i=0;i<a->nchans;i++) {
  struct ave_boot_desc d;ave_boot_desc_parse(p->cpu+i*AVE_BOOT_DESC_STRIDE,&d);descriptors[i]=d;
  int id=ave_boot_name_to_id(a,d.name);
  const struct ave_boot_chan *want=id>0?ave_boot_chan_expect(a,id):NULL;
  if(!want||id>=AVE_CH_MAX||(seen&(1u<<id))||d.dir!=want->dir||d.bit!=want->bit||
     d.nslots!=want->nslots||d.slots_fw!=p->fw_base+want->slots_off||
     d.slots_fw<p->fw_base+a->msg1_nch*AVE_BOOT_DESC_STRIDE||
     d.slots_fw-p->fw_base>=a->msg1_chsz||
     (uint64_t)d.nslots*AVE_BOOT_SLOT_SIZE>a->msg1_chsz-(d.slots_fw-p->fw_base))return EPROTO;
  seen|=1u<<id;
 }
 p->ops.barrier(p->ops.context);
 for(unsigned i=0;i<a->nchans;i++) {
  struct ave_boot_desc d=descriptors[i];
  unsigned id=(unsigned)ave_boot_name_to_id(a,d.name);
  ave_ring_init(&p->ring[id],sfave_ipc_from_fw(p,d.slots_fw,(size_t)d.nslots*AVE_BOOT_SLOT_SIZE),
                d.nslots,ave_ring_dir_to_type(d.dir));
  p->doorbell[id]=d.bit;
 }
 p->bound=seen;p->ops.barrier(p->ops.context);return 0;
}
int sfave_ipc_handshake(struct sfave_ipc *p) {
 if(!p||p->phase!=SFAVE_IPC_CONFIGURED)return EINVAL;
 const struct ave_boot_abi *a=ave_boot_abi_get(AVE_ABI_MACOS_13_5);
 uint32_t m[4];int e;
 if((e=receive_message(p,m)))return fail(p,e);
 if(ave_boot_check_msg1(a,m))return fail(p,EPROTO);
 m[0]=(uint32_t)p->iova;m[1]=(uint32_t)(p->iova>>32);m[2]=p->bytes;m[3]=0;
 if((e=send_message(p,m))||(e=receive_message(p,m)))return fail(p,e);
 p->fw_base=(uint64_t)m[0]|(uint64_t)m[1]<<32;
 if(!p->fw_base||(p->fw_base&63)||p->fw_base>UINT64_MAX-p->bytes)return fail(p,EPROTO);
 /* Both blocks are in FwIPC; chanmem starts at its aligned base. Heap is a
  * separately mapped coherent allocation, exactly the requested size. */
 unsigned char *info=p->cpu+a->msg1_chsz;
 ave_boot_put_le64(info+AVE_BOOT_INFO_CHANMEM,p->fw_base);
 ave_boot_put_le64(info+AVE_BOOT_INFO_HEAP_ADDR,p->heap_iova);
 ave_boot_put_le32(info+AVE_BOOT_INFO_HEAP_SIZE,p->heap_bytes);
 ave_boot_put_le32(info+AVE_BOOT_INFO_DEV_TYPE,10);
 p->ops.barrier(p->ops.context);
 uint64_t info_fw=p->fw_base+a->msg1_chsz;
 m[0]=(uint32_t)info_fw;m[1]=(uint32_t)(info_fw>>32);m[2]=0;m[3]=0;
 if((e=send_message(p,m))||(e=receive_message(p,m)))return fail(p,e);
 uint64_t descriptors=(uint64_t)m[0]|(uint64_t)m[1]<<32;
 /* H13G's literal client buffer is0xb0000 (generic H13C table is0xb4000). */
 if(descriptors!=p->fw_base||m[2]!=0xb0000)return fail(p,EPROTO);
 p->client_bytes=m[2];p->ops.barrier(p->ops.context);
 if((e=bind_channels(p,a)))return fail(p,e);
 if((e=p->ops.write(p->ops.context,SCRATCH(3),AVE_BOOT_MAGIC)))return fail(p,e);
 for(unsigned n=0;n<AVE_BOOT_READY_POLLS;n++) {
  if((e=p->ops.read(p->ops.context,SCRATCH(3),&m[0])))return fail(p,e);
  if(!m[0]){p->ops.barrier(p->ops.context);p->phase=SFAVE_IPC_READY;return 0;}
  p->ops.delay_us(p->ops.context,AVE_BOOT_READY_DELAY_US);
 }
 return fail(p,ETIMEDOUT);
}
static int send_raw(struct sfave_ipc *p,unsigned channel,uint64_t fw,uint32_t bytes,uint32_t flags) {
 if(!p||p->phase!=SFAVE_IPC_READY||channel>=AVE_CH_MAX||!(p->bound&(1u<<channel)))return ENODEV;
 struct ave_ring *r=&p->ring[channel];
 if(r->type&2)return EINVAL;
 if(r->wr<0)return EAGAIN;
 unsigned char *slot=r->slots+(size_t)r->wr*AVE_BOOT_SLOT_SIZE;
 ave_boot_put_le64(slot+8,bytes);ave_boot_put_le64(slot+16,flags);
 p->ops.barrier(p->ops.context);
 /* Aligned 64-bit phase publication, not the host selftest's byte stores.
  * The caller's coherent DMA mapping and device barrier remain essential. */
 __atomic_store_n((uint64_t *)slot,fw|((uint64_t)r->type^1),__ATOMIC_RELEASE);
 int32_t rd=r->rd,w=r->wr;
 if(rd<0){r->rd=w;rd=w;}
 w=w==(int32_t)r->nslots-1?0:w+1;r->wr=rd==w?-1:w;r->nsend++;
 p->ops.barrier(p->ops.context);
 int e=p->ops.write(p->ops.context,DOORBELL,1u<<p->doorbell[channel]);
 return e?fail(p,e):0;
}
int sfave_ipc_send(struct sfave_ipc *p,unsigned channel,uint64_t iova,uint32_t bytes,uint32_t flags) {
 if(!p||p->phase!=SFAVE_IPC_READY)return ENODEV;
 if(channel==AVE_CH_IO_T2H)return EINVAL; /* credits only through checked ack */
 uint64_t fw=0;
 if(iova) {
  if(iova<p->iova||iova-p->iova>=p->bytes||bytes>p->bytes-(iova-p->iova))return EINVAL;
  fw=p->fw_base+(iova-p->iova);if(fw&3)return EINVAL;
 }
 return send_raw(p,channel,fw,bytes,flags);
}
int sfave_ipc_receive(struct sfave_ipc *p,unsigned channel,struct sfave_ipc_message *m) {
 if(!p||!m||p->phase!=SFAVE_IPC_READY||channel>=AVE_CH_MAX||!(p->bound&(1u<<channel)))return ENODEV;
 if(channel==AVE_CH_IO_T2H&&p->reply_pending)return EBUSY;
 struct ave_ring *r=&p->ring[channel];
 if(!(r->type&2)&&r->rd<0)return EAGAIN;
 unsigned index=r->rd<0?0:(unsigned)r->rd;
 unsigned char *slot=r->slots+(size_t)index*AVE_BOOT_SLOT_SIZE;
 uint64_t word=__atomic_load_n((uint64_t *)slot,__ATOMIC_ACQUIRE);
 if((word&1)!=(r->type&1))return EAGAIN;
 p->ops.barrier(p->ops.context);
 m->firmware=word&~3ULL;m->bytes=(uint32_t)ave_boot_get_le64(slot+8);m->flags=(uint32_t)ave_boot_get_le64(slot+16);
 m->payload=m->firmware?sfave_ipc_from_fw(p,m->firmware,m->bytes?m->bytes:1):NULL;
 if(m->firmware&&!m->payload)return fail(p,EPROTO);
 if(r->type&2) {
  __atomic_store_n((uint64_t *)slot,(uint64_t)r->type^1,__ATOMIC_RELEASE);
  p->ops.barrier(p->ops.context);r->rd=index+1==r->nslots?0:(int32_t)index+1;
 } else {
  int32_t w=r->wr;if(w<0){r->wr=(int32_t)index;w=(int32_t)index;}
  int32_t next=index+1==r->nslots?0:(int32_t)index+1;r->rd=w==next?-1:next;
 }
 r->nrecv++;
 if(channel==AVE_CH_IO_T2H){p->pending_reply=*m;p->reply_pending=1;}
 return 0;
}
int sfave_ipc_ack(struct sfave_ipc *p,unsigned channel,const struct sfave_ipc_message *m) {
 if(!p||!m||channel!=AVE_CH_IO_T2H||!p->reply_pending||
    m->firmware!=p->pending_reply.firmware||m->payload!=p->pending_reply.payload||
    m->bytes!=p->pending_reply.bytes||m->flags!=p->pending_reply.flags)return EINVAL;
 int e=send_raw(p,channel,m->firmware,m->bytes,0);
 if(!e)p->reply_pending=0;
 return e;
}
