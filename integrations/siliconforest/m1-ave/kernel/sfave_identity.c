/* SPDX-License-Identifier: MIT */
#include "sfave/sfave_identity.h"
#ifdef KERNEL
#include <sys/errno.h>
#include <libkern/libkern.h>
#else
#include <errno.h>
#include <string.h>
#endif
int sfave_copy_metadata_text(const void *bytes,size_t size,char *out,size_t capacity) {
 const unsigned char *p=bytes;
 if(!out||!capacity)return EINVAL;
 out[0]=0;
 if(!p||!size||size>4096)return EINVAL;
 size_t n=0;
 while(n<size&&p[n]) {
  if(n>=capacity-1||p[n]<32||p[n]>126)return EINVAL;
  n++;
 }
 if(!n)return EINVAL;
 memcpy(out,p,n);out[n]=0;return 0;
}
int sfave_find_identity(const void *bytes,size_t size,const char *prefix,char *out,size_t capacity) {
 const unsigned char *p=bytes;
 if(!p||!prefix||!out||!capacity)return EINVAL;
 out[0]=0;
 size_t n=strlen(prefix);if(!n||n>=capacity||size>4*1024*1024)return EINVAL;
 int found=0;
 for(size_t i=0;i<size;i++) {
  if(size-i<n || memcmp(p+i,prefix,n))continue;
  size_t end=i+n;
  while(end<size && ((p[end]>='0'&&p[end]<='9') || (p[end]=='.'&&end+1<size&&p[end+1]>='0'&&p[end+1]<='9')))end++;
  if(end==i+n || p[i+n]<'0'||p[i+n]>'9'||p[end-1]=='.')continue;
  size_t count=end-i;
  if(end==size || count>=capacity)return EINVAL;
  if(found && (strlen(out)!=count || memcmp(out,p+i,count)))return EINVAL;
  memcpy(out,p+i,count);out[count]=0;found=1;
 }
 return found?0:ENOENT;
}
static int utf16_dash(const unsigned char *p,size_t size,size_t i,char *out,size_t cap) {
 static const char pref[]="AppleAVE2FW-";
 size_t n=sizeof pref-1;
 if(i+n*2+2>size)return 0;
 for(size_t k=0;k<n;k++) if(p[i+2*k]!=(unsigned char)pref[k]||p[i+2*k+1])return 0;
 if(p[i+n*2]<'0'||p[i+n*2]>'9'||p[i+n*2+1])return 0;
 size_t e=i+n*2;
 while(e+1<size) {
  unsigned char c=p[e],hi=p[e+1];
  int ok=hi==0 && ((c>='0'&&c<='9') || (c=='.'&&e+3<size&&p[e+3]==0&&p[e+2]>='0'&&p[e+2]<='9'));
  if(!ok)break;
  e+=2;
 }
 if((e-i)/2==n || p[e-2]=='.')return 0;
 if(e+1>=size)return -1;
 size_t chars=(e-i)/2;
 if(chars>=cap)return -1;
 for(size_t k=0;k<chars;k++)out[k]=(char)p[i+2*k];
 out[chars]=0;return 1;
}
int sfave_describe_firmware(const void *bytes,size_t size,struct sfave_firmware_desc *out) {
 const unsigned char *p=bytes;
 if(!out)return EINVAL;
 memset(out,0,sizeof *out);
 if(!p||size>4*1024*1024)return EINVAL;
 static const char slash[]="AppleAVE2FW/";
 static const char firm[]="AppleAVE2FW/Firmware";
 size_t pn=sizeof slash-1,fn=sizeof firm-1;
 char source[48];source[0]=0;
 int source_ok=0,have_fw=0,landmark=0;
 for(size_t i=0;i<size;i++) {
  if(i+pn<=size && !memcmp(p+i,slash,pn))landmark=1;
  if(i+pn>=size || memcmp(p+i,slash,pn))continue;
  size_t e=i+pn;
  while(e<size && p[e]>=32 && p[e]<=126)e++;
  if(e>=size || p[e])continue;
  out->path_hits++;
  int is_fw=e-i>=fn && !memcmp(p+i,firm,fn);
  if(is_fw)out->firmware_path=1;
  if(is_fw) {
   if(have_fw)continue;
   have_fw=1;
  } else if(source_ok)continue;
  size_t n=e-i;if(n>47)n=47;
  memcpy(source,p+i,n);source[n]=0;source_ok=1;
 }
 int dash=sfave_find_identity(p,size,"AppleAVE2FW-",out->text,sizeof out->text);
 if(!dash){out->kind=SFAVE_FW_DASH;return 0;}
 if(dash!=ENOENT)return dash;
 char u16[48];int u16_found=0;
 for(size_t i=0;i<size;i++) {
  char one[48];int r=utf16_dash(p,size,i,one,sizeof one);
  if(!r)continue;
  if(r<0)return EINVAL;
  if(u16_found && strcmp(u16,one))return EINVAL;
  memcpy(u16,one,strlen(one)+1);u16_found=1;
 }
 if(u16_found){memcpy(out->text,u16,strlen(u16)+1);out->kind=SFAVE_FW_UTF16;return 0;}
 static const char ver[]="6070.11.1";
 size_t vn=sizeof ver-1;int exact=0;
 for(size_t i=0;i+vn<size;i++)
  if((!i || !p[i-1]) && !memcmp(p+i,ver,vn) && !p[i+vn])exact=1;
 if(exact && landmark){memcpy(out->text,ver,vn+1);out->kind=SFAVE_FW_VERSION;return 0;}
 if(source_ok){memcpy(out->text,source,strlen(source)+1);out->kind=SFAVE_FW_SOURCE;return 0;}
 return ENOENT;
}
