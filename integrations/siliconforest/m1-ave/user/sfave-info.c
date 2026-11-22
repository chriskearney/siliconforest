/* SPDX-License-Identifier: MIT */
#include "sfave/sfave_ioctl.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
int main(void) {
 static const char *handshake_name[]={"none","cold","power","dapf","started","ready"};
 int fd=open("/dev/sfave",O_RDONLY);
 if(fd<0){fprintf(stderr,"SFAVE_INFO open: %s; hardware encode unqualified\n",strerror(errno));return errno==ENOENT?77:1;}
 struct sfave_info info={0};int result=ioctl(fd,SFAVE_IOC_INFO,&info);close(fd);
 if(result<0){perror("SFAVE_INFO ioctl");return 1;}
 if(info.abi!=SFAVE_ABI_VERSION||info.size!=sizeof info){fputs("SFAVE_INFO ABI mismatch\n",stderr);return 1;}
 info.firmware[47]=info.rtkit[47]=info.iboot[47]=0;
 const char *hs=info.handshake<6?handshake_name[info.handshake]:"?";
 printf("SFAVE_INFO abi=%u bytes=%u flags=0x%x caps=0x%x soc=0x%x segments=%u error=%u handshake=%u (%s)\n",
  info.abi,info.size,info.flags,info.caps,info.soc,info.segments,info.error,info.handshake,hs);
 printf("PRELOAD TEXT=0x%x flags=%u DATA=0x%x flags=%u\n",info.segment_size[0],info.segment_flags[0],info.segment_size[1],info.segment_flags[1]);
 printf("IDENTITY iboot=%s firmware=%s rtkit=%s\n",info.iboot,info.firmware,info.rtkit);
 printf("PLACEMENT physBase=0x%llx text=0x%llx data=0x%llx\n",(unsigned long long)info.phys_base,(unsigned long long)info.text_phys,(unsigned long long)info.data_phys);
 printf("CRC text=0x%08x data=0x%08x cold_pages=%u nonzero=%u\n",info.text_crc,info.data_crc,info.cold_pages,info.cold_nonzero);
 printf("QUALIFICATION encoder-ready=%u cold-reserved=%u handshake-flag=%u\n",
  !!(info.flags&SFAVE_INFO_ENCODER_READY),!!(info.flags&SFAVE_INFO_COLD_RESERVED),!!(info.flags&SFAVE_INFO_HANDSHAKE));
 return (info.error||info.handshake!=SFAVE_HS_READY||!info.caps)?1:0;
}
