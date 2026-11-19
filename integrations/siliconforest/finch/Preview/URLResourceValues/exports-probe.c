/* SPDX-License-Identifier: MIT */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv) {
 if(argc!=2)return 2;
 FILE *f=fopen(argv[1],"r");if(!f)return 3;
 void *foundation=dlopen("/usr/lib/swift/libswiftFoundation.dylib",RTLD_NOW|RTLD_LOCAL);
 void *uti=dlopen("/usr/lib/swift/libswiftUniformTypeIdentifiers.dylib",RTLD_NOW|RTLD_LOCAL);
 if(!foundation||!uti){fprintf(stderr,"dlopen: %s\n",dlerror());return 4;}
 char line[8192];size_t found=0,missing=0;
 while(fgets(line,sizeof line,f)) {
  char *tab=strchr(line,'\t');if(!tab)return 5;*tab++='\0';tab[strcspn(tab,"\r\n")]='\0';
  void *handle=!strcmp(line,"Foundation")?foundation:uti;
  const char *lookup=tab[0]=='_'?tab+1:tab;
  if(dlsym(handle,lookup))found++;
  else{fprintf(stderr,"MISSING %s %s\n",line,tab);missing++;}
 }
 fclose(f);printf("PASS native exports found=%zu missing=%zu\n",found,missing);return missing?1:0;
}
