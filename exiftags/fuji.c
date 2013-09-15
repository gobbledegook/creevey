/*
 * Copyright (c) 2002, 2003, Eric M. Johnston <emj@postal.net>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *      This product includes software developed by Eric M. Johnston.
 * 4. Neither the name of the author nor the names of any co-contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * $Id: fuji.c,v 1.15 2004/12/23 20:38:52 ejohnst Exp $
 */

/*
 * Exif tag definitions for Fuji maker notes.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "makers.h"


/* Sharpness. */

static struct descrip fuji_sharp[] = {
	{ 1,	"Soft" },
	{ 2,	"Soft" },
	{ 3,	"Normal" },
	{ 4,	"Hard" },
	{ 5,	"Hard" },
	{ -1,	"Unknown" },
};


/* White balance. */

static struct descrip fuji_white[] = {
	{ 0,	"Auto" },
	{ 256,	"Daylight" },
	{ 512,	"Cloudy" },
	{ 768,	"Daylight Color Fluorescence" },
	{ 769,	"Daywhite Color Fluorescence" },
	{ 769,	"White Fluorescence" },
	{ 1024,	"Incandescence" },
	{ 3840,	"Custom" },
	{ -1,	"Unknown" },
};


/* Color & tone settings. */

static struct descrip fuji_color[] = {
	{ 0,	"Normal" },
	{ 256,	"High" },
	{ 512,	"Low" },
	{ -1,	"Unknown" },
};


/* Flash mode. */

static struct descrip fuji_flmode[] = {
	{ 0,	"Auto" },
	{ 1,	"On" },
	{ 2,	"Off" },
	{ 3,	"Red Eye Reduction" },
	{ -1,	"Unknown" },
};


/* Generic boolean. */

static struct descrip fuji_bool[] = {
	{ 0,	"Off" },
	{ 1,	"On" },
	{ -1,	"Unknown" },
};


/* Focus mode. */

static struct descrip fuji_focus[] = {
	{ 0,	"Auto" },
	{ 1,	"Manual" },
	{ -1,	"Unknown" },
};


/* Picture mode. */

static struct descrip fuji_picture[] = {
	{ 0,	"Auto" },
	{ 1,	"Portrait" },
	{ 2,	"Landscape" },
	{ 4,	"Sports Scene" },
	{ 5,	"Night Scene" },
	{ 6,	"Program AE" },
	{ 256,	"Aperture Prior AE" },
	{ 512,	"Shutter Prior AE" },
	{ 768,	"Manual Exposure" },
	{ -1,	"Unknown" },
};


/* Blur warning. */

static struct descrip fuji_blurw[] = {
	{ 0,	"OK" },
	{ 1,	"Blur Warning" },
	{ -1,	"Unknown" },
};


/* Focus warning. */

static struct descrip fuji_focusw[] = {
	{ 0,	"OK" },
	{ 1,	"Out of Focus" },
	{ -1,	"Unknown" },
};


/* Auto exposure warning. */

static struct descrip fuji_aew[] = {
	{ 0,	"OK" },
	{ 1,	"Over Exposed" },
	{ -1,	"Unknown" },
};


/* Maker note IFD tags. */

static struct exiftag fuji_tags[] = {
	{ 0x0000, TIFF_UNDEF, 4, ED_CAM, "FujiVersion",
	  "Maker Note Version", NULL },
	{ 0x1000, TIFF_ASCII, 8, ED_UNK, "FujiQuality",
	  "Quality Setting", NULL },
	{ 0x1001, TIFF_SHORT, 1, ED_IMG, "FujiSharpness",
	  "Sharpness", fuji_sharp },
	{ 0x1002, TIFF_SHORT, 1, ED_IMG, "FujiWhiteBal",
	  "White Balance", fuji_white },
	{ 0x1003, TIFF_SHORT, 1, ED_IMG, "FujiColor",
	  "Chroma Saturation", fuji_color },
	{ 0x1004, TIFF_SHORT, 1, ED_IMG, "FujiTone",
	  "Contrast", fuji_color },
	{ 0x1010, TIFF_SHORT, 1, ED_IMG, "FujiFlashMode",
	  "Flash Mode", fuji_flmode },
	{ 0x1011, TIFF_SRTNL, 1, ED_UNK, "FujiFlashStrength",
	  "Flash Strength", NULL },
	{ 0x1020, TIFF_SHORT, 1, ED_IMG, "FujiMacro",
	  "Macro Mode", fuji_bool },
	{ 0x1021, TIFF_SHORT, 1, ED_IMG, "FujiFocusMode",
	  "Focus Mode", fuji_focus },
	{ 0x1030, TIFF_SHORT, 1, ED_IMG, "FujiSlowSync",
	  "Slow Synchro Mode", fuji_bool },
	{ 0x1031, TIFF_SHORT, 1, ED_IMG, "FujiPicMode",
	  "Picture Mode", fuji_picture },
	{ 0x1100, TIFF_SHORT, 1, ED_IMG, "FujiBracket",
	  "Continuous/Bracketing Mode", fuji_bool },
	{ 0x1300, TIFF_SHORT, 1, ED_IMG, "FujiBlurWarn",
	  "Blur Status", fuji_blurw },
	{ 0x1301, TIFF_SHORT, 1, ED_IMG, "FujiFocusWarn",
	  "Focus Status", fuji_focusw },
	{ 0x1302, TIFF_SHORT, 1, ED_IMG, "FujiAEWarn",
	  "Auto Exposure Status", fuji_aew },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "FujiUnknown",
	  "Fuji Unknown", NULL },
};


/*
 * Process Fuji maker note tags.
 */
void
fuji_prop(struct exifprop *prop, struct exiftags *t)
{

	switch (prop->tag) {

	/* Maker note version. */

	case 0x0000:
		if (prop->count != 4)
			break;
		exifstralloc(&prop->str, prop->count + 1);
		byte4exif(prop->value, (unsigned char *)prop->str, LITTLE);
		break;
	}
}


/*
 * Try to read a Fuji maker note IFD.
 */
struct ifd *
fuji_ifd(u_int32_t offset, struct tiffmeta *md)
{
	struct ifd *myifd;
	int fujilen, fujioff;

	fujilen = strlen("FUJIFILM");

	/*
	 * The Fuji maker note appears to be in Intel byte order
	 * regardless of the rest of the file (!).  Also, it seems that
	 * Fuji maker notes start with an ID string, followed by an IFD
	 * offset relative to the MakerNote tag.
	 */

	if (!strncmp((const char *)(md->btiff + offset), "FUJIFILM", fujilen)) {
		fujioff = exif2byte(md->btiff + offset + fujilen, LITTLE);
		md->order = LITTLE;
		readifd(offset + fujioff, &myifd, fuji_tags, md);
	} else
		readifd(offset, &myifd, fuji_tags, md);

	return (myifd);
}
