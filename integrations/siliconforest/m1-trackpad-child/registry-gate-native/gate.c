/* Finite observation only. No service opens, report I/O, or registry writes. */
#include "gate.h"
#include "descriptor_guard.h"
#include <string.h>

uint32_t ng_u32(const uint8_t *p)
{ return (uint32_t)p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24; }
uint64_t ng_u64(const uint8_t *p) { return ng_u32(p) | (uint64_t)ng_u32(p+4)<<32; }
void ng_put32(uint8_t *p, uint32_t v)
{ unsigned i; for (i=0;i<4;i++) p[i]=(uint8_t)(v>>(8*i)); }
void ng_put64(uint8_t *p, uint64_t v)
{ ng_put32(p,(uint32_t)v); ng_put32(p+4,(uint32_t)(v>>32)); }
int ng_nonce_valid(const char *s)
{ size_t i; if (!s || strlen(s)!=48) return 0; for(i=0;i<48;i++) if(!((s[i]>='0'&&s[i]<='9')||(s[i]>='a'&&s[i]<='f'))) return 0; return 1; }

static int exact_name(const uint8_t *p, const char *name)
{ const void *z=memchr(p,0,NG_NAME_BYTES); return z && strcmp((const char *)p,name)==0; }

int ng_classify(const uint8_t r[NG_BYTES], const uint8_t descriptor_digest[32])
{
 uint32_t n=ng_u32(r+NG_HIDS),i,j; uint64_t parent=0,child=0;
 const uint8_t *s=r+NG_STATE;
 uint32_t commit,route,fault,stop,error;
 if(ng_u32(r)!=1 || ng_u32(r+NG_SIZE)!=NG_BYTES) return 1;
 if(ng_u32(r+NG_REASON)||ng_u32(r+NG_QUERY_ERRORS)||ng_u32(r+NG_RELEASE_ERRORS)) return 1;
 if(n>2 || ng_u32(r+NG_HID_DONE)!=1 || ng_u32(r+NG_SERIAL_DONE)!=1 || ng_u32(r+NG_SERIALS)!=0) return 1;
 for(i=0;i<4;i++) if(ng_u32(r+NG_ITER_VALID+4*i)!=1) return 1;
 for(i=0;i<n;i++) {
  const uint8_t *c=r+NG_CLASSES+NG_NAME_BYTES*i;
  uint64_t id=ng_u64(r+NG_IDS+8*i);
  if(!id) return 1;
  for(j=0;j<i;j++) if(id==ng_u64(r+NG_IDS+8*j)) return 1;
  if(exact_name(c,"SFM1SPIHID")) { if(parent) return 1; parent=id; }
  else if(exact_name(c,"SFM1SPITrackpad")) { if(child) return 1; child=id; }
  else return 1;
 }
 if(!parent || !child) return 77;
 if(parent==child || ng_u64(r+NG_PARENT_ID)!=parent || ng_u64(r+NG_CHILD_ID)!=child) return 1;
 if(ng_u32(r+NG_PARENTS)!=1 || ng_u32(r+NG_PARENT_DONE)!=1 || ng_u32(r+NG_ITER_VALID+16)!=1 || ng_u32(r+NG_ITER_VALID+20)!=1) return 1;
 if(ng_u64(r+NG_PROVIDER_ID)!=parent || ng_u64(r+NG_PROVIDER_IDS)!=parent) return 1;
 if(ng_u32(r+NG_COMPLETE)!=1 || ng_u32(r+NG_DESCRIPTOR_LEN)!=110 || ng_u32(r+NG_INTERFACE_LEN)!=4 || ng_u32(r+NG_STATE_LEN)!=32) return 1;
 if(!sf_trackpad_descriptor_matches(r+NG_DESCRIPTOR,110,descriptor_digest) || ng_u32(r+NG_INTERFACE)!=2) return 1;
 if(ng_u32(s)!=1 || ng_u32(s+4)!=32 || ng_u32(s+28)!=0) return 1;
 commit=ng_u32(s+8); route=ng_u32(s+12); fault=ng_u32(s+16); stop=ng_u32(s+20); error=ng_u32(s+24);
 if(commit>1||route>1||fault>1||stop>1) return 1;
 if(route && (!commit||fault||stop||error)) return 1;
 if(fault && !error) return 1;
 if(error && !fault && !stop) return 1;
 for(i=0;i<2;i++) if(ng_u32(r+NG_KBD_NODE+4*i)>1) return 1;
 if(!commit||!route||fault||stop||error||!ng_u32(r+NG_KBD_NODE)||!ng_u32(r+NG_MOUSE_NODE)) return 77;
 return 0;
}

struct observation {
 const struct ng_ops *ops; void *ctx; uint8_t *r;
 uint32_t owned[16]; size_t n;
};
static void bad(struct observation *o, uint32_t reason, int32_t detail)
{ if(!ng_u32(o->r+NG_REASON)) { ng_put32(o->r+NG_REASON,reason); ng_put32(o->r+NG_DETAIL,(uint32_t)detail); } }
static int keep(struct observation *o, uint32_t port)
{
 if(!port) return 1;
 if(o->n==16) { /* unreachable with the finite walk bounds; still consume it */
  int32_t kr=o->ops->release(o->ctx,port);
  bad(o,NG_OWNERSHIP,kr); if(kr) ng_put32(o->r+NG_RELEASE_ERRORS,ng_u32(o->r+NG_RELEASE_ERRORS)+1);
  return 0;
 }
 o->owned[o->n++]=port; return 1;
}
static int rpc(struct observation *o,int32_t kr)
{ if(!kr) return 1; bad(o,NG_RPC,kr); ng_put32(o->r+NG_QUERY_ERRORS,ng_u32(o->r+NG_QUERY_ERRORS)+1); return 0; }
static int valid(struct observation *o,uint32_t it,unsigned slot)
{
 int32_t v=0;
 if(!rpc(o,o->ops->valid(o->ctx,it,&v))) return 0;
 if(v!=1) { bad(o,NG_INVALID_ITERATOR,v); return 0; }
 ng_put32(o->r+NG_ITER_VALID+4*slot,1); return 1;
}
static int matching(struct observation *o,uint32_t master,const char *name,uint32_t *it)
{
 int32_t kr; *it=0; kr=o->ops->matching(o->ctx,master,name,it);
 if(!keep(o,*it)) return 0;
 return rpc(o,kr);
}
static int next(struct observation *o,uint32_t it,uint32_t *p,int *end)
{
 int32_t kr; *p=0; *end=0; kr=o->ops->next(o->ctx,it,p);
 if(!keep(o,*p)) return 0;
 if(kr==NG_NO_DEVICE && !*p) { *end=1; return 1; }
 if(!rpc(o,kr)) return 0;
 if(!*p) { bad(o,NG_NULL_PORT,0); return 0; }
 return 1;
}
static int props(struct observation *o,uint32_t child)
{
 static const char *const keys[]={"ReportDescriptor","SFM1SPIInterfaceID","SFM1TrackpadChildStateV1"};
 static const unsigned lengths[]={110,4,32}, offsets[]={NG_DESCRIPTOR,NG_INTERFACE,NG_STATE};
 uint8_t buf[NG_PROPERTY_CAP]; unsigned i;
 for(i=0;i<3;i++) {
  uint32_t len=NG_PROPERTY_CAP; int32_t kr;
  memset(buf,0,sizeof(buf)); kr=o->ops->property(o->ctx,child,keys[i],buf,&len);
  ng_put32(o->r+NG_DESCRIPTOR_LEN+4*i,len);
  if(!rpc(o,kr)) return 0;
  if(len>NG_PROPERTY_CAP) { bad(o,NG_PROPERTY,0); return 0; }
  memcpy(o->r+offsets[i],buf,len<lengths[i]?len:lengths[i]);
  if(len!=lengths[i]) { bad(o,NG_PROPERTY,0); return 0; }
 }
 return 1;
}

int ng_collect(const struct ng_ops *ops,void *ctx,const uint8_t descriptor_digest[32],uint8_t r[NG_BYTES])
{
 struct observation o={ops,ctx,r,{0},0};
 uint32_t master=0,hidit=0,serialit=0,parentit=0,child=0,p=0; int end=0;
 unsigned n=0; int32_t kr;
 memset(r,0,NG_BYTES); ng_put32(r,1); ng_put32(r+NG_SIZE,NG_BYTES);
 ng_put32(r+NG_KBD_NODE,(uint32_t)-2); ng_put32(r+NG_MOUSE_NODE,(uint32_t)-2);
 kr=ops->master(ctx,&master); if(!keep(&o,master)||!rpc(&o,kr)) goto done;
 if(!master) { bad(&o,NG_NULL_PORT,0); goto done; }
 if(!matching(&o,master,"IOHIDDevice",&hidit)) goto done;
 if(hidit) {
  if(!valid(&o,hidit,0)) goto done;
  for(n=0;n<3;n++) {
   uint64_t id=0; char name[NG_NAME_BYTES];
   if(!next(&o,hidit,&p,&end)) goto done;
   if(end) break;
   ng_put32(r+NG_HIDS,n+1);
   if(n==2) { bad(&o,NG_EXCESS,0); goto done; }
   memset(name,0xff,sizeof(name));
   if(!rpc(&o,ops->class_name(ctx,p,name))) goto done;
   memcpy(r+NG_CLASSES+NG_NAME_BYTES*n,name,sizeof(name));
   if(!memchr(name,0,sizeof(name))) { bad(&o,NG_CLASS,0); goto done; }
   if(!rpc(&o,ops->entry_id(ctx,p,&id))) goto done;
   ng_put64(r+NG_IDS+8*n,id);
   if(!id) { bad(&o,NG_ID,0); goto done; }
   if(!strcmp(name,"SFM1SPIHID")) ng_put64(r+NG_PARENT_ID,id);
   if(!strcmp(name,"SFM1SPITrackpad")) { child=p; ng_put64(r+NG_CHILD_ID,id); }
  }
  if(!valid(&o,hidit,1)) goto done;
 } else { ng_put32(r+NG_ITER_VALID,1); ng_put32(r+NG_ITER_VALID+4,1); }
 ng_put32(r+NG_HID_DONE,1);
 if(!matching(&o,master,"SFSerialHID",&serialit)) goto done;
 if(serialit) {
  if(!valid(&o,serialit,2)) goto done;
  if(!next(&o,serialit,&p,&end)) goto done;
  if(!end) { ng_put32(r+NG_SERIALS,1); bad(&o,NG_EXCESS,0); goto done; }
  if(!valid(&o,serialit,3)) goto done;
 } else { ng_put32(r+NG_ITER_VALID+8,1); ng_put32(r+NG_ITER_VALID+12,1); }
 ng_put32(r+NG_SERIAL_DONE,1);
 /* Reject unknown/duplicate entries before reading child properties. A clean
  * missing member is classified only after the SFSerialHID exclusion above. */
 for(n=0;n<ng_u32(r+NG_HIDS);n++) {
  unsigned j; const uint8_t *c=r+NG_CLASSES+NG_NAME_BYTES*n;
  if(!exact_name(c,"SFM1SPIHID")&&!exact_name(c,"SFM1SPITrackpad")) { bad(&o,NG_CLASS,0); goto done; }
  for(j=0;j<n;j++) if(ng_u64(r+NG_IDS+8*n)==ng_u64(r+NG_IDS+8*j) || !strcmp((const char *)c,(const char *)(r+NG_CLASSES+NG_NAME_BYTES*j))) { bad(&o,NG_ID,0); goto done; }
 }
 if(!child || !ng_u64(r+NG_PARENT_ID)) goto done;
 kr=ops->parents(ctx,child,&parentit); if(!keep(&o,parentit)||!rpc(&o,kr)) goto done;
 if(!parentit) { bad(&o,NG_PARENT,0); goto done; }
 if(!valid(&o,parentit,4)) goto done;
 for(n=0;n<2;n++) {
  uint64_t id=0;
  if(!next(&o,parentit,&p,&end)) goto done;
  if(end) break;
  ng_put32(r+NG_PARENTS,n+1);
  if(!rpc(&o,ops->entry_id(ctx,p,&id))) goto done;
  ng_put64(r+NG_PROVIDER_IDS+8*n,id);
  if(n==1) { bad(&o,NG_PARENT,0); goto done; }
  ng_put64(r+NG_PROVIDER_ID,id);
 }
 if(!valid(&o,parentit,5)) goto done;
 ng_put32(r+NG_PARENT_DONE,1);
 if(n!=1 || ng_u64(r+NG_PROVIDER_ID)!=ng_u64(r+NG_PARENT_ID)) { bad(&o,NG_PARENT,0); goto done; }
 if(!props(&o,child)) goto done;
 for(n=0;n<2;n++) {
  int32_t detail=0; int32_t result=ops->node(ctx,n?"/dev/usb_hid_mouse":"/dev/usb_hid_kbd",&detail);
  ng_put32(r+NG_KBD_NODE+4*n,(uint32_t)result);
  if(result<0||result>1) { bad(&o,NG_NODE,detail); goto done; }
 }
 ng_put32(r+NG_COMPLETE,1);
done:
 while(o.n) {
  kr=ops->release(ctx,o.owned[--o.n]);
  if(kr) { ng_put32(r+NG_RELEASE_ERRORS,ng_u32(r+NG_RELEASE_ERRORS)+1); bad(&o,NG_OWNERSHIP,kr); }
 }
 { int result=ng_classify(r,descriptor_digest); ng_put32(r+NG_RESULT,(uint32_t)result); return result; }
}
