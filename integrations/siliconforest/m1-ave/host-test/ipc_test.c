/* SPDX-License-Identifier: GPL-2.0-only */
/* Synthetic peer and injected faults only. This is not firmware execution. */
#include "sfave_ipc.h"
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
struct peer {
 struct sfave_ipc *ipc;
 unsigned message,reads,writes,delays,barriers,doorbells,acked;
 int fault;
 uint32_t host[4];
};
enum {BAD_MSG1=1,BAD_FW_BASE,BAD_LAST_DESC,BAD_CLIENT,NO_MESSAGE,NO_READY,WRITE_FAULT,POSTED_DOORBELL_FAULT};
static void descriptors(struct peer *p) {
 const struct ave_boot_abi *a=ave_boot_abi_get(AVE_ABI_MACOS_13_5);
 memset(p->ipc->cpu,0xab,a->msg1_chsz);
 for(unsigned i=0;i<a->nchans;i++) {
  const struct ave_boot_chan *c=&a->chans[i];unsigned char *d=p->ipc->cpu+i*AVE_BOOT_DESC_STRIDE;
  memset(d,0,AVE_BOOT_DESC_STRIDE);memcpy(d,c->name,strlen(c->name));
  ave_boot_put_le32(d+AVE_BOOT_DESC_DIR,c->dir);ave_boot_put_le32(d+AVE_BOOT_DESC_BIT,c->bit);
  ave_boot_put_le32(d+AVE_BOOT_DESC_NSLOTS,c->nslots);
  ave_boot_put_le64(d+AVE_BOOT_DESC_SLOTS,p->ipc->fw_base+c->slots_off);
 }
 if(p->fault==BAD_LAST_DESC)p->ipc->cpu[6*AVE_BOOT_DESC_STRIDE]='?';
}
static int read_reg(void *context,uint32_t reg,uint32_t *value) {
 struct peer *p=context;p->reads++;
 if(reg==0x10){*value=p->fault==NO_MESSAGE?0:1;return 0;}
 assert(reg>=0x18&&reg<=0x24&&!(reg&3));unsigned index=(reg-0x18)/4;
 if(p->message>=3){assert(index==3);*value=p->fault==NO_READY?AVE_BOOT_MAGIC:0;return 0;}
 assert(p->acked); /* Firmware status acknowledged BEFORE scratch read. */
 uint32_t m[4]={0};
 if(p->message==0){m[0]=p->fault==BAD_MSG1?6:7;m[1]=0x9bc0;m[2]=0x100;m[3]=0xc0000;}
 else if(p->message==1){m[0]=p->fault==BAD_FW_BASE?0xffffffc0:0x80000000;m[1]=p->fault==BAD_FW_BASE?0xffffffff:0;}
 else {m[0]=0x80000000;m[2]=p->fault==BAD_CLIENT?0xb4000:0xb0000;}
 *value=m[index];if(index==3){p->message++;p->acked=0;}return 0;
}
static int write_reg(void *context,uint32_t reg,uint32_t value) {
 struct peer *p=context;p->writes++;
 if(p->fault==WRITE_FAULT)return EIO;
 if(reg==0x10){assert(value==1&&!p->acked);p->acked=1;return 0;}
 if(reg==0x0c){
  if(p->ipc->phase==SFAVE_IPC_READY){assert(value==2||value==8);return 0;}
  assert(value==1);p->doorbells++;
  if(p->doorbells==1){assert(p->host[0]==0x1000000&&p->host[1]==0&&p->host[2]==0x700000&&p->host[3]==0);}
  else {assert(p->host[0]==0x80009bc0&&p->host[1]==0&&p->host[2]==0&&p->host[3]==0);descriptors(p);}
  return 0;
 }
 assert(reg>=0x18&&reg<=0x24&&!(reg&3));p->host[(reg-0x18)/4]=value;return 0;
}
static void delay(void *context,uint32_t us){struct peer *p=context;assert(us==100||us==1000);p->delays++;}
static void barrier(void *context){((struct peer *)context)->barriers++;}
int main(void) {
 const struct sfave_preload preload={.soc=0x8103,.preloaded=1,.segment_count=2,.cold_reserved=1,
  .segment={{0x100000,0,0x100000,0xcc000,3},{0x300000,0xcc000,0x400000,0x128000,0}},
  .iboot="iBoot-8422.141.2",.firmware="AppleAVE2FW-6070.11.1",.rtkit="RTKit-2062.141.1"};
 unsigned char *memory=aligned_alloc(0x4000,0x700000);assert(memory);
 {
  struct sfave_ipc ipc;struct peer peer={.ipc=&ipc};
  struct sfave_preload path=preload;path.firmware="AppleAVE2FW/Firmware/H13G";
  const struct sfave_ipc_ops ops={&peer,read_reg,write_reg,delay,barrier};
  assert(!sfave_ipc_init(&ipc,&path,&ops,memory,0x1000000,0x700000,0x2000000,0xc0000));
  assert(!peer.reads&&!peer.writes);
 }
 for(int fault=0;fault<=POSTED_DOORBELL_FAULT;fault++) {
  struct sfave_ipc ipc;struct peer peer={.ipc=&ipc,.fault=fault};
  const struct sfave_ipc_ops ops={&peer,read_reg,write_reg,delay,barrier};
  struct sfave_preload absent=preload;absent.cold_reserved=0;
  assert(sfave_ipc_init(&ipc,&absent,&ops,memory,0x1000000,0x700000,0x2000000,0xc0000)==ENODEV);
  assert(sfave_ipc_init(&ipc,&preload,&ops,memory,0x1000000,0x700000,0x1004000,0xc0000)==EINVAL);
  assert(!peer.reads&&!peer.writes);
  assert(!sfave_ipc_init(&ipc,&preload,&ops,memory,0x1000000,0x700000,0x2000000,0xc0000));
  assert(sfave_ipc_handshake(&ipc)==EINVAL);
  int result=sfave_ipc_configure(&ipc);
  if(fault==WRITE_FAULT){assert(result==EIO&&ipc.phase==SFAVE_IPC_FAILED);continue;}
  assert(!result&&peer.host[0]==AVE_BOOT_MAGIC&&peer.host[1]==0&&peer.host[2]==13);
  result=sfave_ipc_handshake(&ipc);
  if(fault==POSTED_DOORBELL_FAULT) {
   assert(!result);peer.fault=WRITE_FAULT;
   assert(sfave_ipc_send(&ipc,AVE_CH_IO,ipc.iova+0x30000,128,0)==EIO);
   assert(ipc.phase==SFAVE_IPC_FAILED);
   assert(sfave_ipc_send(&ipc,AVE_CH_IO,ipc.iova+0x30000,128,0)==ENODEV);
   continue;
  }
  if(!fault) {
   assert(!result&&ipc.phase==SFAVE_IPC_READY&&ipc.bound==0xfe&&ipc.client_bytes==0xb0000);
   assert(ipc.ring[AVE_CH_IO].nslots==32&&ipc.ring[AVE_CH_TERMINAL].nslots==512);
   assert(ave_boot_get_le64(memory+0x9bc0+AVE_BOOT_INFO_HEAP_ADDR)==0x2000000);
   assert(ave_boot_get_le32(memory+0x9bc0+AVE_BOOT_INFO_DEV_TYPE)==10);
   assert(sfave_ipc_from_fw(&ipc,ipc.fw_base,1)==memory);
   assert(!sfave_ipc_from_fw(&ipc,ipc.fw_base-1,1));
   assert(!sfave_ipc_from_fw(&ipc,ipc.fw_base+ipc.bytes,1));
   assert(!sfave_ipc_from_fw(&ipc,ipc.fw_base+ipc.bytes-1,2));
   assert(!sfave_ipc_from_fw(&ipc,ipc.fw_base,SIZE_MAX));
   struct ave_ring firmware;
   ave_ring_init(&firmware,ipc.ring[AVE_CH_IO].slots,32,0);
   for(unsigned i=0;i<32;i++)assert(!sfave_ipc_send(&ipc,AVE_CH_IO,ipc.iova+0x30000+4*i,128,i));
   assert(sfave_ipc_send(&ipc,AVE_CH_IO,ipc.iova+0x30000,128,0)==EAGAIN);
   assert(sfave_ipc_send(&ipc,AVE_CH_IO,ipc.iova+ipc.bytes-4,8,0)==EINVAL);
   assert(sfave_ipc_send(&ipc,AVE_CH_IO,ipc.iova+1,8,0)==EINVAL);
   for(unsigned i=0;i<32;i++) {
    uint64_t payload;uint32_t bytes,flags;
    assert(!ave_ring_recv(&firmware,&payload,&bytes,&flags));
    assert(payload==ipc.fw_base+0x30000+4*i&&bytes==128&&flags==i);
    assert(!ave_ring_send(&firmware,payload,bytes,0));
    struct sfave_ipc_message message;
    assert(!sfave_ipc_receive(&ipc,AVE_CH_IO,&message));
    assert(message.payload==memory+0x30000+4*i&&message.bytes==128);
   }
   struct sfave_ipc_message message;
   assert(sfave_ipc_receive(&ipc,AVE_CH_IO,&message)==EAGAIN);
   assert(!sfave_ipc_send(&ipc,AVE_CH_IO,ipc.iova+0x30000,128,0));
   ave_ring_init(&firmware,ipc.ring[AVE_CH_IO_T2H].slots,32,1);
   assert(!ave_ring_send(&firmware,ipc.fw_base+0x40000,64,5));
   assert(!sfave_ipc_receive(&ipc,AVE_CH_IO_T2H,&message));
   assert(message.payload==memory+0x40000&&message.bytes==64&&message.flags==5);
   uint64_t payload;uint32_t bytes,flags;
   assert(ave_ring_recv(&firmware,&payload,&bytes,&flags)); /* no early credit */
   struct sfave_ipc_message later;
   assert(sfave_ipc_receive(&ipc,AVE_CH_IO_T2H,&later)==EBUSY);
   struct sfave_ipc_message forged=message;forged.bytes++;
   assert(sfave_ipc_ack(&ipc,AVE_CH_IO_T2H,&forged)==EINVAL);
   assert(sfave_ipc_ack(&ipc,AVE_CH_IO,&message)==EINVAL);
   assert(!sfave_ipc_ack(&ipc,AVE_CH_IO_T2H,&message));
   assert(sfave_ipc_ack(&ipc,AVE_CH_IO_T2H,&message)==EINVAL);
   assert(!ave_ring_recv(&firmware,&payload,&bytes,&flags)&&bytes==64&&flags==0);
   assert(!ave_ring_send(&firmware,ipc.fw_base+ipc.bytes-4,8,0));
   assert(sfave_ipc_receive(&ipc,AVE_CH_IO_T2H,&message)==EPROTO&&ipc.phase==SFAVE_IPC_FAILED);
  } else {
   assert(result==(fault==NO_MESSAGE||fault==NO_READY?ETIMEDOUT:EPROTO));
   assert(ipc.phase==SFAVE_IPC_FAILED&&sfave_ipc_handshake(&ipc)==EINVAL);
   if(fault==BAD_LAST_DESC)for(unsigned i=0;i<8;i++)assert(memory[0x8700+i]==0xab);
   if(fault==NO_MESSAGE)assert(peer.delays==2000);
   if(fault==NO_READY)assert(peer.delays==20000);
  }
 }
 free(memory);puts("AVE polling transport: synthetic handshake, W1C order, T8103 row, late descriptor rejection before ring writes, bounds, I/O failure and finite timeouts PASS; no hardware");
}
