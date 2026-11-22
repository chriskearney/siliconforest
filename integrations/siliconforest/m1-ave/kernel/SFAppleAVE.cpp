// SPDX-License-Identifier: GPL-2.0-only
/* T8103 AVE service. The first INFO ioctl maps preloaded TEXT and DATA,
 * snapshots cold DATA, then boots the coprocessor. start() does not.
 * Copyright (c) 2026 SiliconForest contributors. See ../NOTICE.
 */
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/IODeviceTreeSupport.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOLocks.h>
#include <IOKit/IOMemoryDescriptor.h>
#include <IOKit/IOService.h>
#include <libkern/c++/OSString.h>
#include <pexpert/pexpert.h>
#include <pexpert/arm64/boot.h>
#include <miscfs/devfs/devfs.h>
#include <stddef.h>
#include <sys/conf.h>
#include <sys/errno.h>
#include <sys/systm.h>
#include "sfave/sfave_ioctl.h"
#include "sfave_bringup.h"
extern "C" {
#include "sfave/sfave_identity.h"
#include "sfave/sfave_preload.h"
}
#define LOG(fmt,...) IOLog("SFAppleAVE: " fmt "\n",##__VA_ARGS__)
class SFAppleAVE:public IOService {
 OSDeclareDefaultStructors(SFAppleAVE);
 public:bool start(IOService *) APPLE_KEXT_OVERRIDE;
};
OSDefineMetaClassAndStructors(SFAppleAVE,IOService);
struct Segment {uint64_t physical,iova,remap;uint32_t size,flags;};
static_assert(sizeof(Segment)==32,"ADT segment");
static_assert(sizeof(sfave_info)==232,"INFO ABI");
static_assert(offsetof(sfave_info,handshake)==28,"handshake slot");
static_assert(offsetof(sfave_info,text_crc)==192,"crc slot");
static_assert(offsetof(sfave_info,phys_base)==208,"phys slot");
static sfave_info gInfo;
static IOLock *gInfoLock;
static bool gInventoried;
static IOBufferMemoryDescriptor *gColdMD;
static int inventory();
static int openNode(dev_t,int,int,proc_t){return 0;}
// Last close ends a stream its owner left open (a crashed recorder).
static int closeNode(dev_t,int,int,proc_t) {
 IOLockLock(gInfoLock);int e=gInventoried?sfave_enc_stop():0;IOLockUnlock(gInfoLock);
 if(e)LOG("close: stream stop failed: %d",e);
 return 0;
}
static int ioctlNode(dev_t,u_long command,caddr_t data,int,proc_t) {
 if(command!=SFAVE_IOC_INFO&&command!=SFAVE_IOC_ENC_START&&command!=SFAVE_IOC_ENC_FRAME&&
    command!=SFAVE_IOC_ENC_STOP)return ENOTTY;
 int err=0;
 IOLockLock(gInfoLock);
 if(!gInventoried){gInfo.error=inventory();gInventoried=true;}
 if(command==SFAVE_IOC_INFO)memcpy(data,&gInfo,sizeof(gInfo));
 else if(!(gInfo.flags&SFAVE_INFO_HANDSHAKE))err=ENXIO;
 else if(command==SFAVE_IOC_ENC_START) {
  err=sfave_enc_start((struct sfave_enc_start *)data);
  if(!err)gInfo.flags|=SFAVE_INFO_ENCODER_READY;
 }
 else if(command==SFAVE_IOC_ENC_FRAME)err=sfave_enc_frame((struct sfave_enc_frame *)data);
 else err=sfave_enc_stop();
 IOLockUnlock(gInfoLock);return err;
}
static struct cdevsw methods={.d_open=openNode,.d_close=closeNode,.d_read=eno_rdwrt,
 .d_write=eno_rdwrt,.d_ioctl=ioctlNode,.d_stop=eno_stop,.d_reset=eno_reset,
 .d_ttys=nullptr,.d_select=eno_select,.d_mmap=eno_mmap,.d_strategy=eno_strat,
 .d_reserved_1=eno_getc,.d_reserved_2=eno_putc,.d_type=0};
static uint32_t textCrc32(const void *bytes,size_t size) {
 const unsigned char *p=(const unsigned char *)bytes;uint32_t c=0xffffffffu;
 for(size_t i=0;i<size;i++){c^=p[i];for(int b=0;b<8;b++)c=(c>>1)^(0xedb88320u&-(c&1));}
 return ~c;
}
static const OSData *property(IORegistryEntry *node,const char *key) {
 return node?OSDynamicCast(OSData,node->getProperty(key)):nullptr;
}
static bool number(IORegistryEntry *node,const char *key,void *out,size_t size) {
 const OSData *d=property(node,key);if(!d||d->getLength()!=size)return false;
 memcpy(out,d->getBytesNoCopy(),size);return true;
}
static bool text(IORegistryEntry *node,const char *key,char *out,size_t size) {
 if(!node)return false;
 const OSObject *value=node->getProperty(key);
 const OSString *string=OSDynamicCast(OSString,value);
 if(string)return sfave_copy_metadata_text(string->getCStringNoCopy(),string->getLength(),out,size)==0;
 const OSData *data=OSDynamicCast(OSData,value);
 return data&&sfave_copy_metadata_text(data->getBytesNoCopy(),data->getLength(),out,size)==0;
}
static void copyText(char *dst,size_t cap,const char *src) {
 size_t n=0;if(!dst||!cap)return;if(!src){dst[0]=0;return;}
 while(src[n]&&n+1<cap)n++;memcpy(dst,src,n);dst[n]=0;
}
static int mapReadOnly(uint64_t phys,uint32_t size,IOMemoryDescriptor **md,IOMemoryMap **map,const void **va) {
 *md=IOMemoryDescriptor::withPhysicalAddress(phys,size,kIODirectionIn);
 if(!*md)return ENOMEM;
 *map=(*md)->map(kIOMapCopybackCache|kIOMapReadOnly);
 if(!*map||!(*va=(const void *)(*map)->getVirtualAddress())) {
  OSSafeReleaseNULL(*map);OSSafeReleaseNULL(*md);return ENOMEM;
 }
 return 0;
}
static void unmapReadOnly(IOMemoryDescriptor **md,IOMemoryMap **map) {
 OSSafeReleaseNULL(*map);OSSafeReleaseNULL(*md);
}
static int snapshotCold(const void *src,uint32_t size,uint32_t *crc,uint32_t *pages,uint32_t *nonzero,uint32_t *soc) {
 gColdMD=IOBufferMemoryDescriptor::inTaskWithPhysicalMask(kernel_task,kIODirectionInOut,size,0xfffffffffffff000ULL);
 if(!gColdMD||gColdMD->prepare()!=kIOReturnSuccess){OSSafeReleaseNULL(gColdMD);return ENOMEM;}
 uint8_t *dst=(uint8_t *)gColdMD->getBytesNoCopy();
 if(!dst)return ENOMEM;
 memcpy(dst,src,size);
 *crc=textCrc32(dst,size);*pages=size/0x4000;*nonzero=0;*soc=0;
 for(uint32_t off=0;off+0x4000<=size;off+=0x4000) {
  const uint8_t *page=dst+off;
  for(uint32_t i=0;i<0x4000;i++) if(page[i]){*nonzero+=1;break;}
 }
 for(uint32_t i=0;i+8<=size;i++) {
  if(dst[i]=='S'&&dst[i+1]=='O'&&dst[i+2]=='C'&&dst[i+3]=='_') {
   *soc=(uint32_t)dst[i+4]|((uint32_t)dst[i+5]<<8)|((uint32_t)dst[i+6]<<16)|((uint32_t)dst[i+7]<<24);
   break;
  }
 }
 return 0;
}
static int inventory() {
 IORegistryEntry *chosen=IORegistryEntry::fromPath("/chosen",gIODTPlane);
 IORegistryEntry *ave=IORegistryEntry::fromPath("/arm-io/ave",gIODTPlane);
 uint64_t dram=0;uint32_t preloaded=0;Segment segment[2];
 const char *rejected=nullptr;
 if(!number(chosen,"chip-id",&gInfo.soc,4)||gInfo.soc!=0x8103)rejected="chosen.chip-id";
 else if(!text(chosen,"firmware-version",gInfo.iboot,sizeof(gInfo.iboot)))rejected="chosen.firmware-version";
 else if(!number(chosen,"dram-base",&dram,8))rejected="chosen.dram-base";
 else if(!number(ave,"pre-loaded",&preloaded,4)||preloaded!=1)rejected="ave.pre-loaded";
 else if(!number(ave,"segment-ranges",segment,sizeof(segment)))rejected="ave.segment-ranges";
 OSSafeReleaseNULL(chosen);OSSafeReleaseNULL(ave);
 if(rejected){LOG("metadata rejected at %s (before TEXT mapping)",rejected);return ENODEV;}
 gInfo.flags|=SFAVE_INFO_PRELOADED;gInfo.segments=2;
 const boot_args *boot=(const boot_args *)PE_state.bootArgs;
 if(!boot||!dram||dram>=boot->physBase)return EINVAL;
 for(unsigned i=0;i<2;i++) {
  const Segment &s=segment[i];gInfo.segment_size[i]=s.size;gInfo.segment_flags[i]=s.flags;
  if(s.size!=(i?0x128000u:0xcc000u)||s.flags!=(i?0u:3u)||s.iova!=(i?0xcc000u:0u)||
     (s.physical&0x3fff)||s.physical<dram||s.physical>=boot->physBase||
     s.size>boot->physBase-s.physical)return EINVAL;
 }
 if(segment[0].physical<segment[1].physical+segment[1].size&&
    segment[1].physical<segment[0].physical+segment[0].size)return EINVAL;
 gInfo.flags|=SFAVE_INFO_OUTSIDE_VM;
 gInfo.phys_base=boot->physBase;gInfo.text_phys=segment[0].physical;gInfo.data_phys=segment[1].physical;
 // This proves exclusion from XNU's allocator. The copy below is this boot's
 // cold image; it is not written back over DRAM.
 LOG("placement physBase=0x%llx text=0x%llx/0x%x data=0x%llx/0x%x dataEnd=0x%llx",
     (unsigned long long)boot->physBase,(unsigned long long)segment[0].physical,segment[0].size,
     (unsigned long long)segment[1].physical,segment[1].size,
     (unsigned long long)(segment[1].physical+segment[1].size));
 IOMemoryDescriptor *textMd=nullptr,*dataMd=nullptr;IOMemoryMap *textMap=nullptr,*dataMap=nullptr;
 const void *textVa=nullptr,*dataVa=nullptr;
 int err=mapReadOnly(segment[0].physical,segment[0].size,&textMd,&textMap,&textVa);
 if(err)return err;
 gInfo.text_crc=textCrc32(textVa,segment[0].size);
 LOG("TEXT crc32=0x%08x",gInfo.text_crc);
 sfave_firmware_desc fw={};int fwe=sfave_describe_firmware(textVa,segment[0].size,&fw);
 int rt=sfave_find_identity(textVa,segment[0].size,"RTKit-",gInfo.rtkit,sizeof(gInfo.rtkit));
 LOG("firmware kind=%d path_hits=%u firmware_path=%u",fw.kind,fw.path_hits,fw.firmware_path);
 if(!fwe)copyText(gInfo.firmware,sizeof(gInfo.firmware),fw.text);
 uint64_t literal=0;
 if(segment[0].size>=0x4244)memcpy(&literal,(const uint8_t *)textVa+0x423c,8);
 err=mapReadOnly(segment[1].physical,segment[1].size,&dataMd,&dataMap,&dataVa);
 if(err){unmapReadOnly(&textMd,&textMap);return err;}
 uint32_t socTag=0;
 err=snapshotCold(dataVa,segment[1].size,&gInfo.data_crc,&gInfo.cold_pages,&gInfo.cold_nonzero,&socTag);
 unmapReadOnly(&textMd,&textMap);unmapReadOnly(&dataMd,&dataMap);
 if(err)return err;
 gInfo.flags|=SFAVE_INFO_COLD_RESERVED;gInfo.handshake=SFAVE_HS_COLD;
 LOG("DATA cold crc32=0x%08x pages=%u/74 nonzero=%u soc_tag=%u",gInfo.data_crc,gInfo.cold_pages,gInfo.cold_nonzero,socTag);
 LOG("DATA literal TEXT+0x423c=0x%llx remap=0x%llx",(unsigned long long)literal,(unsigned long long)segment[1].remap);
 if(fwe==EINVAL||rt==EINVAL)return EINVAL;
 if(!rt&&!strcmp(gInfo.rtkit,"RTKit-2062.141.1")&&fw.kind!=SFAVE_FW_NONE)gInfo.flags|=SFAVE_INFO_TEXT_IDENTITY;
 if(literal!=segment[1].remap||segment[1].remap!=0xf000cc000ULL) {
  LOG("preload address mismatch; not powering");return ENOTSUP;
 }
 if(fwe)return fwe;
 if(rt)return rt;
 if(strcmp(gInfo.rtkit,"RTKit-2062.141.1"))return ENOTSUP;
 sfave_boot_in bootIn={};
 bootIn.text_phys=segment[0].physical;bootIn.data_phys=segment[1].physical;bootIn.data_remap=segment[1].remap;
 bootIn.text_size=segment[0].size;bootIn.data_size=segment[1].size;
 bootIn.firmware=gInfo.firmware;bootIn.rtkit=gInfo.rtkit;bootIn.iboot=gInfo.iboot;
 sfave_preload pre={};
 pre.soc=0x8103;pre.preloaded=1;pre.segment_count=2;pre.cold_reserved=1;
 pre.iboot=gInfo.iboot;pre.firmware=gInfo.firmware;pre.rtkit=gInfo.rtkit;
 pre.segment[0].physical=segment[0].physical;pre.segment[0].size=segment[0].size;pre.segment[0].flags=3;
 pre.segment[1].physical=segment[1].physical;pre.segment[1].iova=0xcc000;pre.segment[1].remap=segment[1].remap;
 pre.segment[1].size=segment[1].size;
 err=sfave_preload_bootable(&pre);
 if(err)return err;
 uint32_t hs=gInfo.handshake,caps=0;
 err=sfave_bringup(&bootIn,&hs,&caps);
 gInfo.handshake=hs;gInfo.caps=caps;
 if(!err&&hs==SFAVE_HS_READY&&caps)gInfo.flags|=SFAVE_INFO_HANDSHAKE;
 else if(!err)err=ENXIO;
 LOG("INFO caps=0x%x handshake=%u error=%d",gInfo.caps,gInfo.handshake,err);
 return err;
}
bool SFAppleAVE::start(IOService *provider) {
 if(!IOService::start(provider))return false;
 uint32_t mode=0;PE_parse_boot_argn("sfave",&mode,sizeof(mode));
 if(mode>1)return false;
 gInfoLock=IOLockAlloc();if(!gInfoLock)return false;
 bzero(&gInfo,sizeof(gInfo));gInfo.abi=SFAVE_ABI_VERSION;gInfo.size=sizeof(gInfo);
 int major=cdevsw_add(-1,&methods);if(major<0){IOLockFree(gInfoLock);gInfoLock=nullptr;return false;}
 void *node=devfs_make_node(makedev(major,0),DEVFS_CHAR,0,0,0600,"sfave");
 if(!node){cdevsw_remove(major,&methods);IOLockFree(gInfoLock);gInfoLock=nullptr;return false;}
 LOG("published /dev/sfave; coprocessor boot runs on the first INFO ioctl");
 registerService();return true;
}
