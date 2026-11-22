/* SPDX-License-Identifier: MIT */
#include "sfave/sfave_preload.h"
#include "sfave/sfave_identity.h"
#include "sfave/sfave_ioctl.h"
#include <assert.h>
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
struct bank { uint32_t reg[512]; unsigned reads,writes,fail_write; int mismatch; };
static int rd(void *ctx,uint32_t off,uint32_t *out) {
 struct bank *b=ctx;assert(off>=0xdc000 && off<0xdc800 && !(off&3));
 b->reads++;*out=b->reg[(off-0xdc000)/4];
 if(b->mismatch && off==0xdc404)*out^=1;
 return 0;
}
static int wr(void *ctx,uint32_t off,uint32_t value) {
 struct bank *b=ctx;assert(off>=0xdc000 && off<0xdc800 && !(off&3));
 if(++b->writes==b->fail_write)return EIO;
 b->reg[(off-0xdc000)/4]=value;return 0;
}
static void put32(unsigned char *p,uint32_t n){for(int i=0;i<4;i++)p[i]=(unsigned char)(n>>(8*i));}
int main(void) {
 _Static_assert(sizeof(struct sfave_info)==232,"INFO layout");
 _Static_assert(offsetof(struct sfave_info,handshake)==28,"handshake slot");
 _Static_assert(offsetof(struct sfave_info,text_crc)==192,"crc slot");
 _Static_assert(offsetof(struct sfave_info,phys_base)==208,"phys slot");
 char metadata[48];char padded[256]={0};memcpy(padded,"iBoot-8422.141.2",16);
 assert(!sfave_copy_metadata_text(padded,sizeof padded,metadata,sizeof metadata));
 assert(!strcmp(metadata,"iBoot-8422.141.2"));
 assert(!sfave_copy_metadata_text("version",7,metadata,sizeof metadata)&&!strcmp(metadata,"version"));
 assert(sfave_copy_metadata_text("bad\x01",4,metadata,sizeof metadata)==EINVAL);
 memset(padded,'x',sizeof padded);assert(sfave_copy_metadata_text(padded,sizeof padded,metadata,sizeof metadata)==EINVAL);
 assert(sfave_copy_metadata_text("",1,metadata,sizeof metadata)==EINVAL);
 const char image[]="noise AppleAVE2FW-6070.11.1.release noise RTKit-2062.141.1.release end";
 char version[48];
 assert(!sfave_find_identity(image,sizeof image,"AppleAVE2FW-",version,sizeof version));
 assert(!strcmp(version,"AppleAVE2FW-6070.11.1"));
 assert(sfave_find_identity(image,24,"AppleAVE2FW-",version,sizeof version)==EINVAL);
 const char conflict[]="AppleAVE2FW-1.2\0AppleAVE2FW-3.4\0";
 assert(sfave_find_identity(conflict,sizeof conflict,"AppleAVE2FW-",version,sizeof version)==EINVAL);
 assert(sfave_find_identity(image,sizeof image,"Absent-",version,sizeof version)==ENOENT);
 assert(sfave_find_identity(image,sizeof image,"AppleAVE2FW-",version,8)==EINVAL);
 struct sfave_firmware_desc described;
 assert(!sfave_describe_firmware(image,sizeof image,&described));
 assert(described.kind==SFAVE_FW_DASH&&!strcmp(described.text,"AppleAVE2FW-6070.11.1"));
 assert(sfave_describe_firmware(conflict,sizeof conflict,&described)==EINVAL);
 unsigned char u16[64];memset(u16,0,sizeof u16);
 const char *tag="AppleAVE2FW-6070.11.1";
 for(size_t i=0;tag[i];i++){u16[2*i]=(unsigned char)tag[i];u16[2*i+1]=0;}
 assert(!sfave_describe_firmware(u16,sizeof u16,&described));
 assert(described.kind==SFAVE_FW_UTF16&&!strcmp(described.text,"AppleAVE2FW-6070.11.1"));
 const char src[]="zz\0AppleAVE2FW/Firmware/H13G\0AppleAVE2FW/other\0";
 assert(!sfave_describe_firmware(src,sizeof src,&described));
 assert(described.kind==SFAVE_FW_SOURCE&&!strcmp(described.text,"AppleAVE2FW/Firmware/H13G"));
 assert(described.path_hits==2&&described.firmware_path==1);
 const char both[]="AppleAVE2FW/Firmware/H13G\0" "6070.11.1";
 assert(!sfave_describe_firmware(both,sizeof both,&described));
 assert(described.kind==SFAVE_FW_VERSION&&!strcmp(described.text,"6070.11.1"));
 const char bare[]="6070.11.1";
 assert(sfave_describe_firmware(bare,sizeof bare,&described)==ENOENT&&described.kind==SFAVE_FW_NONE&&!described.text[0]);
 struct sfave_preload p={.soc=0x8103,.preloaded=1,.segment_count=2,.cold_reserved=1,
  .segment={{0x100000,0,0x100000,0xcc000,3},{0x300000,0xcc000,0x400000,0x128000,0}},
  .iboot="iBoot-8422.141.2",.firmware="AppleAVE2FW-6070.11.1",.rtkit="RTKit-2062.141.1"};
 /* Synthetic addresses and register values only; no captured table/image. */
 assert(!sfave_validate_preload(&p));p.cold_reserved=0;assert(sfave_validate_preload(&p)==ENODEV);p.cold_reserved=1;
 p.firmware="AppleAVE2FW-UNKNOWN";assert(sfave_validate_preload(&p)==ENOTSUP);assert(sfave_preload_bootable(&p)==ENOTSUP);
 p.firmware="AppleAVE2FW/Firmware/H13G";assert(sfave_validate_preload(&p)==ENOTSUP);assert(!sfave_preload_bootable(&p));
 p.firmware="6070.11.1";assert(sfave_validate_preload(&p)==ENOTSUP);assert(!sfave_preload_bootable(&p));
 p.firmware="AppleAVE2FW-6070.11.1";assert(!sfave_validate_preload(&p)&&!sfave_preload_bootable(&p));
 p.segment[1].physical=p.segment[0].physical;assert(sfave_validate_preload(&p)==EINVAL);p.segment[1].physical=0x300000;
 p.segment[0].physical=UINT64_MAX-0x3fff;assert(sfave_validate_preload(&p)==EINVAL);
 unsigned char table[504]={0};memcpy(table,"AVEDPE01",8);put32(table+12,1);put32(table+16,39);
 for(unsigned i=0;i<40;i++){put32(table+24+12*i,(i%39+1)*4);put32(table+28+12*i,0xff);put32(table+32+12*i,i%39);}
 struct bank b={0};struct sfave_register_io io={&b,rd,wr};
 for(unsigned n=0;n<sizeof(table);n++)assert(sfave_program_dpe(table,n,&io)==EINVAL);
 assert(!b.reads && !b.writes);
 put32(table+24+39*12,0x400);assert(sfave_program_dpe(table,sizeof(table),&io)==EINVAL);assert(!b.reads&&!b.writes);
 put32(table+24+39*12,4);
 assert(!sfave_program_dpe(table,sizeof(table),&io));assert(b.writes==42);
 assert((b.reg[0xdc400/4-0xdc000/4]&3)==3 && (b.reg[0]&1)==1);
 memset(&b,0,sizeof b);b.fail_write=5;assert(sfave_program_dpe(table,sizeof(table),&io)==EIO);assert(b.writes==5);
 memset(&b,0,sizeof b);b.mismatch=1;assert(sfave_program_dpe(table,sizeof(table),&io)==EIO);
 puts("AVE host preload/DPE: exact ABI/reservation rejection, truncation, late malformed entry before any I/O, masked RMW+enable/readback, fault propagation PASS; synthetic only");
}
