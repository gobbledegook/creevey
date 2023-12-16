#ifndef _EPEG_PRIVATE_H
#define _EPEG_PRIVATE_H

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <time.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <setjmp.h>
#include <jpeglib.h>

typedef struct _epeg_error_mgr *emptr;

struct _epeg_error_mgr
{
      struct     jpeg_error_mgr pub;
      jmp_buf    setjmp_buffer;
};

struct _Epeg_Image
{
   struct _epeg_error_mgr          jerr;
   struct stat                     stat_info;
   unsigned char                  *pixels;
   unsigned char                 **lines;
   
   char                            scaled;
   
   int                             error;
   
   Epeg_Colorspace                 color_space;
   
   struct {
      char                          *file;
      int                            w, h;
      char                          *comment;
      FILE                          *f;
      J_COLOR_SPACE                  color_space;
      struct jpeg_decompress_struct  jinfo;
      struct {
	 char                       *uri;
	 unsigned long long int      mtime;
	 int                         w, h;
	 char                       *mime;
      } thumb_info;
   } in;
   struct {
      char                        *file;
      struct {
	 unsigned char           **data;
	 int                      *size;
      } mem;
      int                          x, y;
      int                          w, h;
      char                        *comment;
      FILE                        *f;
      struct jpeg_compress_struct  jinfo;
      int                          quality;
      char                         thumbnail_info;
   } out;
   //BEGIN DY ADDITIONS
   unsigned char *thumbStart;
   unsigned long thumbLength;
   //END
};

#endif
