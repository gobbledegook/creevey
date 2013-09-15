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
 * $Id: casio.c,v 1.11 2003/08/06 02:26:42 ejohnst Exp $
 */

/*
 * Exif tag definitions for Casio maker notes.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "makers.h"


/* Recording mode. */

static struct descrip casio_record[] = {
	{ 1,	"Single Shutter" },
	{ 7,	"Panorama" },
	{ 10,	"Night Scene" },
	{ 15,	"Portrait" },
	{ 16,	"Landscape" },
	{ -1,	"Unknown" },
};


/* Quality. */

static struct descrip casio_qual[] = {
	{ 1,	"Economy" },
	{ 2,	"Normal" },
	{ 3,	"Fine" },
	{ -1,	"Unknown" },
};


/* Focus mode. */

static struct descrip casio_focus[] = {
	{ 2,	"Macro" },
	{ 3,	"Auto" },
	{ 4,	"Manual" },
	{ 5,	"Infinity" },
	{ -1,	"Unknown" },
};


/* Flash mode. */

static struct descrip casio_flash[] = {
	{ 1,	"Auto" },
	{ 2,	"On" },
	{ 4,	"Off" },
	{ 5,	"Red Eye Reduction" },
	{ -1,	"Unknown" },
};


/* Flash intensity. */

static struct descrip casio_intense[] = {
	{ 11,	"Weak" },
	{ 13,	"Normal" },
	{ 15,	"Strong" },
	{ -1,	"Unknown" },
};


/* White balance. */

static struct descrip casio_whiteb[] = {
	{ 1,	"Auto" },
	{ 2,	"Tungsten" },
	{ 3,	"Daylight" },
	{ 4,	"Fluorescent" },
	{ 5,	"Shade" },
	{ 129,	"Manual" },
	{ -1,	"Unknown" },
};


/* Sharpness. */

static struct descrip casio_sharp[] = {
	{ 0,	"Normal" },
	{ 1,	"Soft" },
	{ 2,	"Hard" },
	{ -1,	"Unknown" },
};


/* Contrast & saturation. */

static struct descrip casio_range[] = {
	{ 0,	"Normal" },
	{ 1,	"Low" },
	{ 2,	"High" },
	{ -1,	"Unknown" },
};


/* Sensitivity. */

static struct descrip casio_sensitive[] = {
	{ 64,	"Normal" },
	{ 80,	"Normal" },
	{ 100,	"High" },
	{ 125,	"+1.0" },
	{ 244,	"+3.0" },
	{ 250,	"+2.0" },
	{ -1,	"Unknown" },
};


/* Maker note IFD tags. */

static struct exiftag casio_tags0[] = {
	{ 0x0001, TIFF_SHORT, 1, ED_IMG, "CasioRecord",
	  "Recording Mode", casio_record },
	{ 0x0002, TIFF_SHORT, 1, ED_IMG, "CasioQuality",
	  "Quality Setting", casio_qual },
	{ 0x0003, TIFF_SHORT, 1, ED_IMG, "CasioFocus",
	  "Focusing Mode", casio_focus },
	{ 0x0004, TIFF_SHORT, 1, ED_IMG, "CasioFlash",
	  "Flash Mode", casio_flash },
	{ 0x0005, TIFF_SHORT, 1, ED_IMG, "CasioIntensity",
	  "Flash Intensity", casio_intense },
	{ 0x0006, TIFF_LONG, 1, ED_VRB, "CasioDistance",
	  "Object Distance", NULL },
	{ 0x0007, TIFF_SHORT, 1, ED_IMG, "CasioWhiteB",
	  "White Balance", casio_whiteb },
	{ 0x000a, TIFF_LONG, 1, ED_UNK, "CasioDZoom",
	  "Digital Zoom", NULL },
	{ 0x000b, TIFF_SHORT, 1, ED_IMG, "CasioSharp",
	  "Sharpness", casio_sharp },
	{ 0x000c, TIFF_SHORT, 1, ED_IMG, "CasioContrast",
	  "Contrast", casio_range },
	{ 0x000d, TIFF_SHORT, 1, ED_IMG, "CasioSaturate",
	  "Saturation", casio_range },
	{ 0x0014, TIFF_SHORT, 1, ED_IMG, "CasioSensitive",
	  "Sensitivity", casio_sensitive },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "CasioUnknown",
	  "Casio Unknown", NULL },
};


static struct exiftag casio_tags1[] = {
	{ 0x2001, TIFF_ASCII, 1, ED_UNK, "CasioASCII1",
	  "Casio ASCII Val 1", NULL },
	{ 0x2002, TIFF_ASCII, 1, ED_UNK, "CasioASCII2",
	  "Casio ASCII Val 2", NULL },
	{ 0x3006, TIFF_ASCII, 1, ED_UNK, "CasioASCII3",
	  "Casio ASCII Val 3", NULL },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "CasioUnknown",
	  "Casio Unknown", NULL },
};


/*
 * Try to read a Casio maker note IFD.
 */
struct ifd *
casio_ifd(u_int32_t offset, struct tiffmeta *md)
{
	struct ifd *myifd;

	/*
	 * It appears that there are two different types of maker notes
	 * for Casio cameras: one, for older cameras, uses a standard IFD
	 * format; the other starts at offset + 6 ("QVC\0\0\0").
	 */

	if (!memcmp("QVC\0\0\0", md->btiff + offset, 6)) {
		readifd(offset + strlen("QVC") + 3, &myifd, casio_tags1, md);
		exifwarn("Casio maker note version not supported");
	} else
		readifd(offset, &myifd, casio_tags0, md);

	return (myifd);
}
