/*
 * Copyright (c) 2004 Eric M. Johnston <emj@postal.net>
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
 * $Id: asahi.c,v 1.5 2004/12/23 20:38:52 ejohnst Exp $
 */

/*
 * Exif tag definitions for Asahi Optical Co. (Pentax) maker notes.
 * Note that the format is similar to Casio's, though has byte order
 * weirdness like Fuji.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "makers.h"


/* Quality. */

static struct descrip asahi_qual[] = {
	{ 0,	"Economy" },
	{ 1,	"Fine" },
	{ 2,	"Super Fine" },
	{ -1,	"Unknown" },
};


/* Resolution. */

static struct descrip asahi_res[] = {
	{ 0,	"640x480" },
	{ 2,	"1024x768" },
	{ 4,	"1600x1200" },
	{ 22,	"2304x1728" },
	{ -1,	"Unknown" },
};


/* Focus mode. */

static struct descrip asahi_focus[] = {
	{ 0,	"Normal" },
	{ 1,	"Macro" },
	{ 2,	"Macro" },
	{ 3,	"Infinity" },
	{ -1,	"Unknown" },
};


/* White balance. */

static struct descrip asahi_whiteb[] = {
	{ 0,	"Auto" },
	{ 1,	"Daylight" },
	{ 2,	"Shade" },
	{ 3,	"Fluorescent" },
	{ 4,	"Tungsten" },
	{ 5,	"Manual" },
	{ -1,	"Unknown" },
};


/* Saturation, contrast, & sharpness. */

static struct descrip asahi_range[] = {
	{ 0,	"Soft" },
	{ 1,	"Normal" },
	{ 2,	"Hard" },
	{ 3,	"Medium Soft" },
	{ 4,	"Medium Hard" },
	{ -1,	"Unknown" },
};


/* Maker note IFD tags. */

static struct exiftag asahi_tags[] = {
	{ 0x0008, TIFF_SHORT, 1, ED_IMG, "AsahiQuality",
	  "Quality Level", asahi_qual },
	{ 0x0009, TIFF_SHORT, 1, ED_VRB, "AsahiRes",
	  "Recorded Pixels", asahi_res },
	{ 0x000d, TIFF_SHORT, 1, ED_IMG, "AsahiFocus",
	  "Focusing Mode", asahi_focus },
	{ 0x0019, TIFF_SHORT, 1, ED_IMG, "AsahiWhiteB",
	  "White Balance", asahi_whiteb },
	{ 0x001f, TIFF_SHORT, 1, ED_IMG, "AsahiSaturate",
	  "Saturation", asahi_range },
	{ 0x0020, TIFF_SHORT, 1, ED_IMG, "AsahiContrast",
	  "Contrast", asahi_range },
	{ 0x0021, TIFF_SHORT, 1, ED_IMG, "AsahiSharp",
	  "Sharpness", asahi_range },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "AsahiUnknown",
	  "Asahi Unknown", NULL },
};


/*
 * Process Asahi maker note tags.
 */
void
asahi_prop(struct exifprop *prop, struct exiftags *t)
{

	/* Override a couple of standard tags. */

	switch (prop->tag) {

	case 0x0019:
		prop->override = EXIF_T_WHITEBAL;
		break;

	case 0x001f:
		prop->override = EXIF_T_SATURATION;
		break;

	case 0x0020:
		prop->override = EXIF_T_CONTRAST;
		break;

	case 0x0021:
		prop->override = EXIF_T_SHARPNESS;
		break;
	}
}


/*
 * Try to read an Asahi maker note IFD.
 */
struct ifd *
asahi_ifd(u_int32_t offset, struct tiffmeta *md)
{

	/*
	 * It appears that there are a couple of maker note schemes for
	 * for Asahi cameras, most with a 6 byte offset.  ("AOC" stands
	 * for "Asahi Optical Co.")
	 */

	if (!memcmp("AOC\0", md->btiff + offset, 4)) {

		/*
		 * If the prefix includes two spaces, fix at big-endian.
		 * E.g., Optio 230, 330GS, 33L.
		 */

		if (!memcmp("  ", md->btiff + offset + 4, 2)) {
			md->order = BIG;
			return (readifds(offset + 6, asahi_tags, md));
		}

		/*
		 * With two zero bytes, try file byte order (?).
		 * E.g., Optio 330RS, 33WR, 430RS, 450, 550, 555, S, S4.
		 */

		if (!memcmp("\0\0", md->btiff + offset + 4, 2))
			return (readifds(offset + 6, asahi_tags, md));

		/*
		 * Two M's seems to be a different tag set we don't grok.
		 * E.g., *ist D.
		 */

		if (!memcmp("MM", md->btiff + offset + 4, 2)) {
			exifwarn("Asahi maker note version not supported");
			return (NULL);
		}

		exifwarn("Asahi maker note version not supported");
		return (NULL);
	}

	/*
	 * The EI-200 seems to have a non-IFD note; we'll use the heuristic
	 * of a minimum 10 tags before we look at it as an IFD.
	 */

	if (exif2byte(md->btiff + offset, md->order) < 10) {
		exifwarn("Asahi maker note version not supported");
		return (NULL);
	}

	/* E.g., Optio 330, 430. */

	md->order = BIG;
	return (readifds(offset, asahi_tags, md));
}
