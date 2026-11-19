#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
int main(int argc,char **argv) {
 if(argc!=3)return 2;
 void *image=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
 if(!image){fprintf(stderr,"SwiftUI dlopen: %s\n",dlerror());return 3;}
 FILE *f=fopen(argv[2],"r");if(!f)return 4;
 char name[2048];unsigned found=0,missing=0;
 while(fgets(name,sizeof(name),f)){name[strcspn(name,"\r\n")]=0;if(!name[0])continue;dlerror();void *p=dlsym(image,name[0]=='_'?name+1:name);if(!p){fprintf(stderr,"missing %s\n",name);missing++;}else found++;}
 fclose(f);printf("SwiftUI native exports found=%u missing=%u\n",found,missing);return missing?5:0;
}
