/*
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
 * $Id: leica.c,v 1.4 2004/04/20 22:12:51 ejohnst Exp $
 */

/*
 * Exif tag definitions for Leica maker notes.  Values were derived from
 * a Digilux 2.
 *
 * Note that the Digilux 4.3's maker notes are identical to Fuji's.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "makers.h"


/* White balance. */

static struct descrip leica_white[] = {
	{ 1,	"Auto" },
	{ 2,	"Sunshine" },
	{ 3,	"Cloudy" },
	{ 4,	"Halogen" },
	{ 5,	"Manual" },
	{ 8,	"Electronic Flash" },
	{ 10,	"Black & White" },
	{ -1,	"Unknown" },
};


/* Compression rate. */

static struct descrip leica_compress[] = {
	{ 2,	"Low" },
	{ 3,	"Normal" },
	{ 6,	"Very Low" },
	{ 7,	"Raw" },
	{ -1,	"Unknown" },
};


/* Generic boolean. */

static struct descrip leica_bool[] = {
	{ 1,	"On" },
	{ 2,	"Off" },
	{ -1,	"Unknown" },
};


/* Focus mode. */

static struct descrip leica_focus[] = {
	{ 1,	"Auto" },
	{ 2,	"Manual" },
	{ -1,	"Unknown" },
};


/* Flash exposure compensation. */

static struct descrip leica_flashev[] = {
	{ 0,		"0 EV" },
	{ 1,		"0.33 EV" },
	{ 2,		"0.67 EV" },
	{ 3,		"1 EV" },
	{ 4,		"1.33 EV" },
	{ 5,		"1.67 EV" },
	{ 6,		"2 EV" },
	{ 0xfffa,	"-2 EV" },
	{ 0xfffb,	"-1.67 EV" },
	{ 0xfffc,	"-1.33 EV" },
	{ 0xfffd,	"-1 EV" },
	{ 0xfffe,	"-0.67 EV" },
	{ 0xffff,	"-0.33 EV" },
	{ -1,		"Unknown" },
};


/* Contrast. */

static struct descrip leica_contrast[] = {
	{ 0x100,	"Low" },
	{ 0x110,	"Standard" },
	{ 0x120,	"High" },
	{ -1,		"Unknown" },
};


/* Aperture mode. */

static struct descrip leica_aperture[] = {
	{ 6,	"Auto" },
	{ 7,	"Manual" },
	{ -1,	"Unknown" },
};


/* Spot autofocus. */

static struct descrip leica_spotaf[] = {
	{ 256,	"On" },
	{ 4096,	"Off" },
	{ -1,	"Unknown" },
};


/* Maker note IFD tags. */

static struct exiftag leica_tags[] = {
	{ 0x0001, TIFF_ASCII, 8, ED_IMG, "LeicaCompress",
	  "Compression Rate", leica_compress },
	{ 0x0003, TIFF_SHORT, 1, ED_IMG, "LeicaWhiteBal",
	  "White Balance", leica_white },
	{ 0x0007, TIFF_SHORT, 1, ED_IMG, "LeicaFocusMode",
	  "Focus Mode", leica_focus },
	{ 0x000f, TIFF_SHORT, 1, ED_IMG, "LeicaSpotAF",
	  "Spot Autofocus", leica_spotaf },
	{ 0x001c, TIFF_SHORT, 1, ED_IMG, "LeicaMacro",
	  "Macro Mode", leica_bool },
	{ 0x001f, TIFF_SHORT, 1, ED_IMG, "LeicaAperture",
	  "Aperture Mode", leica_aperture },
	{ 0x0024, TIFF_SHORT, 1, ED_IMG, "LeicaFlashEV",
	  "Flash Compensation", leica_flashev },
	{ 0x002c, TIFF_SHORT, 1, ED_IMG, "LeicaContrast",
	  "Contrast", leica_contrast },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "LeicaUnknown",
	  "Leica Unknown", NULL },
};


/*
 * Process Leica maker note tags.
 */
void
leica_prop(struct exifprop *prop, struct exiftags *t)
{

	/*
	 * Assume that if the property's tag set is not our Leica one,
	 * it must be Fuji's.
	 */

	if (prop->tagset != leica_tags) {
		fuji_prop(prop, t);
		return;
	}

	/* Override a couple of standard tags. */

	switch (prop->tag) {

	/* White balance. */

	case 0x0003:
		prop->override = EXIF_T_WHITEBAL;
		break;

	/* Contrast. */

	case 0x002c:
		prop->override = EXIF_T_CONTRAST;
		break;
	}
}


/*
 * Try to read a Leica maker note IFD.
 */
struct ifd *
leica_ifd(u_int32_t offset, struct tiffmeta *md)
{

	/*
	 * Leica maker notes start with an ID string, followed by an IFD
	 * offset relative to the MakerNote tag.
	 *
	 * The Digilux 4.3 seems to just spit out Fuji maker notes.  So,
	 * go ahead and use the Fuji functions...
	 */

	if (!strncmp((const char *)(md->btiff + offset), "FUJIFILM", 8))
		return (fuji_ifd(offset, md));

	if (!strncmp((const char *)(md->btiff + offset), "LEICA", 5))
		return (readifds(offset + 8, leica_tags, md));

	return (readifds(offset, leica_tags, md));
}
