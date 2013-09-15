#ifndef _EPEG_PRIVATE_H
#define _EPEG_PRIVATE_H

#define _GNU_SOURCE /* need this for fmemopen & open_memstream */
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

#include "config.h"

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
   
   char                            scaled : 1;
   
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
      char                         thumbnail_info : 1;
   } out;
};

FILE *_epeg_memfile_read_open   (void *data, size_t size);
void  _epeg_memfile_read_close  (FILE *f);
FILE *_epeg_memfile_write_open  (void **data, size_t *size);
void  _epeg_memfile_write_close (FILE *f);
    
#endif
