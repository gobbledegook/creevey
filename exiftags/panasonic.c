/*
 * Copyright (c) 2004, Tom Hughes <tom@compton.nu>
 * Copyright (c) 2004, Eric M. Johnston <emj@postal.net>
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
 * $Id: panasonic.c,v 1.6 2004/12/28 17:33:22 ejohnst Exp $
 *
 */ 

/*
 * Exif tag definitions for Panasonic Lumix maker notes.
 * Tags deciphered by Tom Hughes <tom@compton.nu>; updated for FZ20
 * by Laurent Monin <zas@norz.org> & Lee Kindness <lkindness@csl.co.uk>.
 *
 * Tested models: DMC-FZ10, DMC-FZ20.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "makers.h"


/* Image quality. */

static struct descrip panasonic_quality[] = {
	{ 2,	"Fine" },
	{ 3,	"Standard" },
	{ -1,	"Unknown" },
};


/* White balance. */

static struct descrip panasonic_whitebal[] = {
	{ 1,	"Auto" },
	{ 2,	"Daylight" },
	{ 3,	"Cloudy" },
	{ 4,	"Halogen" },
	{ 5,	"Manual" },
	{ 8,	"Flash" },
	{ -1,	"Unknown" },
};


/* Focus mode. */

static struct descrip panasonic_focus[] = {
	{ 1,	"Auto" },
	{ 2,	"Manual" },
	{ -1,	"Unknown" },
};


/* Spot mode. */

static struct descrip panasonic_spot[] = {
	{ 256,	"On" },
	{ 4096,	"Off" },
	{ -1,	"Unknown" },
};


/* Optical Image Stabilizer mode. */

static struct descrip panasonic_ois[] = {
	{ 2,	"Mode 1" },
	{ 3,	"Off" },
	{ 4,	"Mode 2" },
	{ -1,	"Unknown" },
};


/* Macro. */

static struct descrip panasonic_macro[] = {
	{ 1,	"Macro" },
	{ 2,	"Normal" },
	{ -1,	"Unknown" },
};


/* Shooting mode. */

static struct descrip panasonic_shoot[] = {
	{ 2,	"Portrait" },
	{ 3,	"Scenery" },
	{ 4,	"Sports" },
	{ 5,	"Night Portrait" },
	{ 6,	"Program" },
	{ 7,	"Aperture Priority" },
	{ 8,	"Shutter Priority" },
	{ 9,	"Macro" },
	{ 11,	"Manual" },
	{ 13,	"Panning" },
	{ 18,	"Fireworks" },
	{ 19,	"Party" },
	{ 20,	"Snow" },
	{ 21,	"Night Scenery" },
	{ -1,	"Unknown" },
};


/* Audio. */

static struct descrip panasonic_audio[] = {
	{ 1,	"Yes" },
	{ 2,	"No" },
	{ -1,	"Unknown" },
};


/* Color effect. */

static struct descrip panasonic_color[] = {
	{ 1,	"Off" },
	{ 2,	"Warm" },
	{ 3,	"Cool" },
	{ 4,	"Black & White" },
	{ 5,	"Sepia" },
	{ -1,	"Unknown" },
};


/* Contrast & noise. */

static struct descrip panasonic_range[] = {
	{ 0,	"Standard" },
	{ 1,	"Low" },
	{ 2,	"High" },
	{ -1,	"Unknown" },
};


/* Maker note IFD tags. */

static struct exiftag panasonic_tags0[] = {
	{ 0x0001, TIFF_SHORT, 1, ED_IMG, "PanasonicQuality",
	  "Image Quality", panasonic_quality },
	{ 0x0003, TIFF_SHORT, 1, ED_IMG, "PanasonicWhiteB",
	  "White Balance", panasonic_whitebal },
	{ 0x0007, TIFF_SHORT, 1, ED_IMG, "PanasonicFocus",
	  "Focus Mode", panasonic_focus },
	{ 0x000f, TIFF_BYTE, 1, ED_IMG, "PanasonicSpotMode",
	  "Spot Mode", panasonic_spot },
	{ 0x001a, TIFF_SHORT, 1, ED_IMG, "PanasonicOIS",
	  "Image Stabilizer", panasonic_ois },
	{ 0x001c, TIFF_SHORT, 1, ED_IMG, "PanasonicMacroMode",
	  "Macro Mode", panasonic_macro },
	{ 0x001f, TIFF_SHORT, 1, ED_IMG, "PanasonicShootMode",
	  "Shooting Mode", panasonic_shoot },
	{ 0x0020, TIFF_SHORT, 1, ED_IMG, "PanasonicAudio",
	  "Audio", panasonic_audio },
	{ 0x0023, TIFF_SHORT, 1, ED_UNK, "PanasonicWBAdjust",
	  "White Balance Adjust", NULL },
	{ 0x0024, TIFF_SSHORT, 1, ED_IMG, "PanasonicFlashBias",
	  "Flash Bias", NULL },
	{ 0x0028, TIFF_SHORT, 1, ED_IMG, "PanasonicColorEffect",
	  "Color Effect", panasonic_color },
	{ 0x002c, TIFF_SHORT, 1, ED_IMG, "PanasonicContrast",
	  "Contrast", panasonic_range },
	{ 0x002d, TIFF_SHORT, 1, ED_IMG, "PanasonicNoiseReduce",
	  "Noise Reduction", panasonic_range },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "PanasonicUnknown",
	  "Panasonic Unknown", NULL },
};


/*
 * Process Panasonic maker note tags.
 */
void
panasonic_prop(struct exifprop *prop, struct exiftags *t)
{

	switch (prop->tag) {

	/* White balance. */

	case 0x0003:
		prop->override = EXIF_T_WHITEBAL;
		break;

	/* White balance adjust (unknown). */

	case 0x0023:
		exifstralloc(&prop->str, 10);
		snprintf(prop->str, 9, "%d", (int16_t)prop->value);
		break;

	/* Flash bias. */

	case 0x0024:
		exifstralloc(&prop->str, 10);
		snprintf(prop->str, 9, "%.2f EV", (int16_t)prop->value / 3.0);
		break;

	/* Contrast. */

	case 0x002c:
		prop->override = EXIF_T_CONTRAST;
		break;
	}
}


/*
 * Try to read a Panasonic maker note IFD.
 */
struct ifd *
panasonic_ifd(u_int32_t offset, struct tiffmeta *md)
{

	if (memcmp("Panasonic\0\0\0", md->btiff + offset, 12)) {
		exifwarn("Maker note format not supported");
		return (NULL);
	}

	return (readifds(offset + 12, panasonic_tags0, md));
}
