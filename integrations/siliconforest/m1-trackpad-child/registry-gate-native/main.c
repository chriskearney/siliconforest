/* Real tiny-IOKit MIG adapter, using the pinned generated prototypes. */
#include <SFIOKitLib.h>
#include "device_user.h"
#include <CommonCrypto/CommonDigest.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include "gate.h"
#include "trackpad_reference.h"

static int32_t master(void *ctx,uint32_t *p)
{ (void)ctx; return IOMasterPort(MACH_PORT_NULL,p); }
static int32_t matching(void *ctx,uint32_t p,const char *name,uint32_t *it)
{ (void)ctx; return IOServiceGetMatchingServices(p,IOServiceMatching(name),it); }
static int32_t next_object(void *ctx,uint32_t it,uint32_t *p)
{ (void)ctx; return io_iterator_next(it,p); }
static int32_t iterator_valid(void *ctx,uint32_t it,int32_t *v)
{ boolean_t b=0; kern_return_t kr; (void)ctx; kr=io_iterator_is_valid(it,&b); *v=b; return kr; }
static int32_t class_name(void *ctx,uint32_t p,char name[NG_NAME_BYTES])
{ (void)ctx; return io_object_get_class(p,name); }
static int32_t entry_id(void *ctx,uint32_t p,uint64_t *id)
{ (void)ctx; return io_registry_entry_get_registry_entry_id(p,id); }
static int32_t parents(void *ctx,uint32_t p,uint32_t *it)
{ io_name_t plane={0}; (void)ctx; strcpy(plane,"IOService"); return io_registry_entry_get_parent_iterator(p,plane,it); }
static int32_t property(void *ctx,uint32_t p,const char *name,uint8_t b[NG_PROPERTY_CAP],uint32_t *n)
{
 io_name_t key={0}; mach_msg_type_number_t count=*n; kern_return_t kr;
 (void)ctx; if(strlen(name)>=sizeof(key)) return KERN_INVALID_ARGUMENT;
 strcpy(key,name); kr=io_registry_entry_get_property_bytes(p,key,(char *)b,&count); *n=count; return kr;
}
static int32_t release_object(void *ctx,uint32_t p)
{ (void)ctx; return IOObjectRelease(p); }
static int32_t node(void *ctx,const char *path,int32_t *detail)
{
 struct stat s; (void)ctx;
 if(lstat(path,&s)!=0) { *detail=errno; return errno==ENOENT?0:-1; }
 *detail=0; return S_ISCHR(s.st_mode)?1:2;
}
static const struct ng_ops operations={master,matching,next_object,iterator_valid,class_name,entry_id,parents,property,release_object,node};

static int export_record(const char *nonce,const uint8_t r[NG_BYTES],int result)
{
 uint8_t digest[CC_SHA256_DIGEST_LENGTH]; size_t i,j;
 if(!CC_SHA256(r,NG_BYTES,digest)) return 1;
 printf("DL16_GATE_BEGIN_%s bytes=%u physical_input_proven=false device_opened=false\n",nonce,NG_BYTES);
 printf("{\"event\":\"DL16_GATE\",\"nonce\":\"%s\",\"result\":%d,\"reason\":%u,\"detail\":%d,\"query_errors\":%u,\"release_errors\":%u,\"hid_count\":%u,\"physical_input_proven\":false,\"device_opened\":false,\"non_atomic_observation\":true}\n",
  nonce,result,ng_u32(r+NG_REASON),(int32_t)ng_u32(r+NG_DETAIL),ng_u32(r+NG_QUERY_ERRORS),ng_u32(r+NG_RELEASE_ERRORS),ng_u32(r+NG_HIDS));
 for(i=0;i<NG_BYTES;i+=64) {
  printf("DL16_GATE_HEX_%s index=%zu ",nonce,i/64);
  for(j=i;j<i+64 && j<NG_BYTES;j++) printf("%02x",r[j]);
  putchar('\n');
 }
 printf("DL16_GATE_END_%s chunks=%u bytes=%u sha256=",nonce,(NG_BYTES+63)/64,NG_BYTES);
 for(i=0;i<sizeof(digest);i++) printf("%02x",digest[i]);
 printf(" result=%d\n",result);
 return ferror(stdout)||fflush(stdout)!=0;
}
int main(int argc,char **argv)
{
 uint8_t record[NG_BYTES]; int result;
 /* Reject usage before constructing an observation or invoking any RPC/stat. */
 if(argc!=3 || strcmp(argv[1],"--nonce") || !ng_nonce_valid(argv[2])) return 2;
 result=ng_collect(&operations,NULL,sf_trackpad_descriptor_sha256,record);
 if(export_record(argv[2],record,result)) return 1;
 return result;
}
