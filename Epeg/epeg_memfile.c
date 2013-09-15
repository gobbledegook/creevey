#include "Epeg.h"
#include "epeg_private.h"

FILE *
_epeg_memfile_read_open(void *data, size_t size)
{
#ifdef HAVE_FMEMOPEN
   return (FILE *)fmemopen(data, size, "r");
#else
   FILE *f;
   
   f = tmpfile();
   if (!f) return NULL;
   fwrite(data, size, 1, f);
   rewind(f);
   return f;
#endif
}

void
_epeg_memfile_read_close(FILE *f)
{
#ifdef HAVE_FMEMOPEN
   fclose(f);
#else
   fclose(f);
#endif   
}


typedef struct _Eet_Memfile_Write_Info Eet_Memfile_Write_Info;
struct _Eet_Memfile_Write_Info
{
   FILE *f;
   void **data;
   size_t *size;
};

static int                     _epeg_memfile_info_alloc_num = 0;
static int                     _epeg_memfile_info_num       = 0;
static Eet_Memfile_Write_Info *_epeg_memfile_info           = NULL;

FILE *
_epeg_memfile_write_open(void **data, size_t *size)
{
#ifdef HAVE_OPEN_MEMSTREAM
   return open_memstream((char **)data, size);
#else   
   FILE *f;
   
   _epeg_memfile_info_num++;
   if (_epeg_memfile_info_num > _epeg_memfile_info_alloc_num)
     {
	Eet_Memfile_Write_Info *tmp;
	
	_epeg_memfile_info_alloc_num += 16;
	tmp = realloc(_epeg_memfile_info, 
		      _epeg_memfile_info_alloc_num * 
		      sizeof(Eet_Memfile_Write_Info));
	if (!tmp)
	  {
	     _epeg_memfile_info_alloc_num -= 16;
	     _epeg_memfile_info_num--;
	     return NULL;
	  }
	_epeg_memfile_info = tmp;
     }
   f = tmpfile();
   if (!f) 
     {
	_epeg_memfile_info_num--;
	return NULL;
     }
   _epeg_memfile_info[_epeg_memfile_info_num - 1].f = f;
   _epeg_memfile_info[_epeg_memfile_info_num - 1].data = data;
   _epeg_memfile_info[_epeg_memfile_info_num - 1].size = size;
   return f;
#endif
}

void
_epeg_memfile_write_close(FILE *f)
{
#ifdef HAVE_OPEN_MEMSTREAM
   fclose(f);   
#else
   int i;
   
   for (i = 0; i < _epeg_memfile_info_num; i++)
     {
	if (_epeg_memfile_info[i].f == f)
	  {
	     int j;

	     fseek(f, 0, SEEK_END);
	     (*(_epeg_memfile_info[i].size)) = ftell(f);
	     rewind(f);
	     (*(_epeg_memfile_info[i].data)) = malloc(*(_epeg_memfile_info[i].size));
	     if (!(*(_epeg_memfile_info[i].data)))
	       {
		  fclose(f);
		  (*(_epeg_memfile_info[i].size)) = 0;
		  return;
	       }
	     fread((*(_epeg_memfile_info[i].data)), (*(_epeg_memfile_info[i].size)), 1, f);
	     for (j = i + 1; j < _epeg_memfile_info_num; j++)
	       _epeg_memfile_info[j - 1] = _epeg_memfile_info[j];
	     _epeg_memfile_info_num--;
	     fclose(f);
	     return;
	  }
     }
   fclose(f);
#endif
}
