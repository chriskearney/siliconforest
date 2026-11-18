#ifdef NDEBUG
#error assertion-based host tests require assertions
#endif
#include "gate.h"
#include "descriptor_guard.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

/* Fake getter only: exercises policy and port ownership, never device facts. */
struct fixture {
 int calls,fail_at,release_fail,releases,acquired,released[32],owned[32];
 int hid_n,serial_n,parent_n,position[6],null_hid,null_serial,null_parent;
 int invalid,wrong_class,unterminated,duplicate_id,duplicate_class,wrong_parent,zero_id;
 int short_property,property_error,nonready,node_kind,invalid_node,error_port,null_next,eof_with_port;
};
static uint8_t descriptor[110];
static uint8_t descriptor_digest[32];
static int32_t call(struct fixture *f) { return ++f->calls==f->fail_at?-123:0; }
static void acquired(struct fixture *f,uint32_t p)
{ assert(p<32); f->owned[p]++; f->acquired++; }
static int32_t master(void *ctx,uint32_t *p)
{ struct fixture *f=ctx; int32_t kr=call(f); if(!kr||f->error_port) { *p=1; acquired(f,*p); } return kr; }
static int32_t matching(void *ctx,uint32_t master_port,const char *name,uint32_t *it)
{
 struct fixture *f=ctx; int32_t kr=call(f); assert(master_port==1);
 if(!kr||f->error_port) { *it=!strcmp(name,"IOHIDDevice")?(f->null_hid?0:2):(f->null_serial?0:3); if(*it) acquired(f,*it); }
 return kr;
}
static int32_t next_object(void *ctx,uint32_t it,uint32_t *p)
{
 struct fixture *f=ctx; int n,total; int32_t kr=call(f);
 if(kr) { if(f->error_port) { *p=23; acquired(f,*p); } return kr; }
 if(f->null_next) return 0;
 if(f->eof_with_port) { *p=23; acquired(f,*p); return NG_NO_DEVICE; }
 assert(it==2||it==3||it==4); n=f->position[it]++;
 total=it==2?f->hid_n:it==3?f->serial_n:f->parent_n;
 if(n>=total) return NG_NO_DEVICE;
 *p=it==2?(uint32_t)(10+n):it==3?20u:(uint32_t)(10+n);
 acquired(f,*p); return 0;
}
static int32_t valid(void *ctx,uint32_t it,int32_t *v)
{ struct fixture *f=ctx; (void)it; *v=f->invalid?0:1; return call(f); }
static int32_t class_name(void *ctx,uint32_t p,char name[128])
{
 struct fixture *f=ctx; int32_t kr=call(f); if(kr) return kr;
 if(f->unterminated) memset(name,'x',128);
 else strcpy(name,f->wrong_class?"Unrelated":p==10||f->duplicate_class?"SFM1SPIHID":"SFM1SPITrackpad");
 return 0;
}
static int32_t entry_id(void *ctx,uint32_t p,uint64_t *id)
{
 struct fixture *f=ctx; int32_t kr=call(f); if(kr) return kr;
 /* Same low32, different high32: a truncating implementation must fail. */
 *id=f->zero_id?0:p==10?UINT64_C(0x100000007):UINT64_C(0x200000007);
 if(f->duplicate_id) *id=UINT64_C(0x100000007);
 if(f->wrong_parent && f->position[4]) *id=UINT64_C(0x300000007);
 return 0;
}
static int32_t parents(void *ctx,uint32_t p,uint32_t *it)
{ struct fixture *f=ctx; int32_t kr=call(f); assert(p==11); if(!kr||f->error_port) { *it=f->null_parent?0:4; if(*it) acquired(f,*it); } return kr; }
static int32_t property(void *ctx,uint32_t p,const char *key,uint8_t b[4096],uint32_t *n)
{
 struct fixture *f=ctx; int32_t kr=call(f); assert(p==11 && *n==4096); if(kr) return kr;
 if(f->property_error) return (int32_t)0xe00002beu;
 if(!strcmp(key,"ReportDescriptor")) { memcpy(b,descriptor,110); *n=110; }
 else if(!strcmp(key,"SFM1SPIInterfaceID")) { ng_put32(b,2); *n=4; }
 else { memset(b,0,32); ng_put32(b,1); ng_put32(b+4,32); ng_put32(b+8,1); ng_put32(b+12,f->nonready?0:1); *n=32; }
 if(f->short_property) (*n)--;
 return 0;
}
static int32_t release(void *ctx,uint32_t p)
{
 struct fixture *f=ctx; assert(p<32 && f->owned[p]>f->released[p]);
 f->released[p]++; f->releases++;
 return f->release_fail==f->releases?-456:0;
}
static int32_t node(void *ctx,const char *path,int32_t *detail)
{ struct fixture *f=ctx; (void)path; *detail=0; if(f->invalid_node) { *detail=13; return -1; } return f->node_kind; }
static const struct ng_ops ops={master,matching,next_object,valid,class_name,entry_id,parents,property,release,node};
static struct fixture fresh(void)
{ struct fixture f; memset(&f,0,sizeof(f)); f.hid_n=2; f.parent_n=1; f.node_kind=1; return f; }
static int run(struct fixture *f,uint8_t r[NG_BYTES])
{
 int result=ng_collect(&ops,f,descriptor_digest,r); unsigned i;
 assert(f->acquired==f->releases);
 for(i=0;i<32;i++) assert(f->owned[i]==f->released[i]);
 assert(result==(int)ng_u32(r+NG_RESULT)); return result;
}
int main(void)
{
 struct fixture f; uint8_t r[NG_BYTES],good[NG_BYTES]; int calls,rights,i; unsigned mask;
 for(i=0;i<110;i++) descriptor[i]=(uint8_t)i;
 assert(sf_trackpad_descriptor_digest(descriptor,sizeof(descriptor),descriptor_digest));
 f=fresh(); assert(run(&f,good)==0); calls=f.calls; rights=f.releases;
 for(i=1;i<=calls;i++) { f=fresh(); f.fail_at=i; assert(run(&f,r)==1); assert(ng_u32(r+NG_QUERY_ERRORS)==1); }
 for(i=1;i<=calls;i++) { f=fresh(); f.fail_at=i; f.error_port=1; assert(run(&f,r)==1); assert(ng_u32(r+NG_QUERY_ERRORS)==1); }
 for(i=1;i<=rights;i++) { f=fresh(); f.release_fail=i; assert(run(&f,r)==1); assert(f.releases==rights); }
#define CASE(field,value,result) do { f=fresh(); f.field=(value); assert(run(&f,r)==(result)); } while(0)
 CASE(hid_n,0,77); CASE(hid_n,1,77); CASE(null_hid,1,77); CASE(null_serial,1,0);
 CASE(hid_n,3,1); CASE(serial_n,1,1); CASE(parent_n,0,1); CASE(parent_n,2,1); CASE(null_parent,1,1);
 CASE(invalid,1,1); CASE(wrong_class,1,1); CASE(unterminated,1,1); CASE(duplicate_id,1,1);
 CASE(duplicate_class,1,1); CASE(wrong_parent,1,1); CASE(zero_id,1,1);
 CASE(short_property,1,1); CASE(property_error,1,1); CASE(nonready,1,77);
 CASE(null_next,1,1); CASE(eof_with_port,1,1);
 CASE(node_kind,0,77); CASE(node_kind,2,1); CASE(invalid_node,1,1);
 /* All boolean states, plus errors at zero, positive and signed extrema. */
 for(mask=0;mask<16;mask++) for(i=0;i<4;i++) {
  static const uint32_t errors[]={0,1,0x80000000u,0xffffffffu};
  uint32_t c=mask&1,route=(mask>>1)&1,fault=(mask>>2)&1,stop=(mask>>3)&1,e=errors[i];
  int expected;
  memcpy(r,good,sizeof(r)); ng_put32(r+NG_STATE+8,c); ng_put32(r+NG_STATE+12,route);
  ng_put32(r+NG_STATE+16,fault); ng_put32(r+NG_STATE+20,stop); ng_put32(r+NG_STATE+24,e);
  expected=(route&&(!c||fault||stop||e))||(fault&&!e)||(e&&!fault&&!stop)?1:!c||!route||fault||stop||e?77:0;
  assert(ng_classify(r,descriptor_digest)==expected);
 }
 /* No field removal may turn a contradictory ready receipt into admission. */
 for(i=0;i<6;i++) { memcpy(r,good,sizeof(r)); ng_put32(r+NG_ITER_VALID+4*i,0); assert(ng_classify(r,descriptor_digest)==1); }
 memcpy(r,good,sizeof(r)); r[NG_DESCRIPTOR]^=1; assert(ng_classify(r,descriptor_digest)==1);
 memcpy(r,good,sizeof(r)); ng_put64(r+NG_PROVIDER_ID,UINT64_C(0x200000007)); assert(ng_classify(r,descriptor_digest)==1);
 assert(ng_nonce_valid("0123456789abcdef0123456789abcdef0123456789abcdef"));
 assert(!ng_nonce_valid("0123456789ABCDEF0123456789abcdef0123456789abcdef")); assert(!ng_nonce_valid(NULL));
 printf("PASS: %d RPC failure boundaries, %d release boundaries, policy/ownership cases\n",calls,rights);
 return 0;
}
