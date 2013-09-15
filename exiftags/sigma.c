/*
 * Copyright (c) 2004, 2005, Eric M. Johnston <emj@postal.net>
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
 * $Id: sigma.c,v 1.6 2005/01/04 23:37:57 ejohnst Exp $
 */

/*
 * Exif tag definitions for Sigma/Foveon maker notes.
 * Developed from http://www.x3f.info/technotes/FileDocs/MakerNoteDoc.html.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "makers.h"


/* Maker note IFD tags. */

static struct exiftag sigma_tags[] = {
	{ 0x0002, TIFF_ASCII, 0, ED_CAM, "SigmaSerial",
	  "Serial Number", NULL },
	{ 0x0003, TIFF_ASCII, 0, ED_IMG, "SigmaDrive",
	  "Drive Mode", NULL },
	{ 0x0004, TIFF_ASCII, 0, ED_IMG, "SigmaResolution",
	  "Resolution", NULL },
	{ 0x0005, TIFF_ASCII, 0, ED_IMG, "SigmaAutofocus",
	  "Autofocus Mode", NULL },
	{ 0x0006, TIFF_ASCII, 0, ED_IMG, "SigmaFocusSet",
	  "Focus Setting", NULL },
	{ 0x0007, TIFF_ASCII, 0, ED_IMG, "SigmaWhiteBal",
	  "White Balance", NULL },
	{ 0x0008, TIFF_ASCII, 0, ED_IMG, "SigmaExpMode",
	  "Exposure Mode", NULL },
	{ 0x0009, TIFF_ASCII, 0, ED_IMG, "SigmaMeterMode",
	  "Metering Mode", NULL },
	{ 0x000a, TIFF_ASCII, 0, ED_CAM, "SigmaLensRange",
	  "Focal Length Range", NULL },
	{ 0x000b, TIFF_ASCII, 0, ED_VRB, "SigmaColor",
	  "Color Space", NULL },
	{ 0x000c, TIFF_ASCII, 0, ED_IMG, "SigmaExposure",
	  "Exposure", NULL },
	{ 0x000d, TIFF_ASCII, 0, ED_IMG, "SigmaContrast",
	  "Contrast", NULL },
	{ 0x000e, TIFF_ASCII, 0, ED_IMG, "SigmaShadow",
	  "Shadow", NULL },
	{ 0x000f, TIFF_ASCII, 0, ED_IMG, "SigmaHighlight",
	  "Highlight", NULL },
	{ 0x0010, TIFF_ASCII, 0, ED_IMG, "SigmaSaturate",
	  "Saturation", NULL },
	{ 0x0011, TIFF_ASCII, 0, ED_IMG, "SigmaSharp",
	  "Sharpness", NULL },
	{ 0x0012, TIFF_ASCII, 0, ED_IMG, "SigmaFill",
	  "Fill Light", NULL },
	{ 0x0014, TIFF_ASCII, 0, ED_IMG, "SigmaColorAdj",
	  "Color Adjustment", NULL },
	{ 0x0015, TIFF_ASCII, 0, ED_IMG, "SigmaAdjMode",
	  "Adjustment Mode", NULL },
	{ 0x0016, TIFF_ASCII, 0, ED_IMG, "SigmaQuality",
	  "Quality", NULL },
	{ 0x0017, TIFF_ASCII, 0, ED_CAM, "SigmaFirmware",
	  "Firmware Version", NULL },
	{ 0x0018, TIFF_ASCII, 0, ED_CAM, "SigmaSoftware",
	  "Camera Software", NULL },
	{ 0x0019, TIFF_ASCII, 0, ED_IMG, "SigmaAutoBrack",
	  "Auto Bracket", NULL },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "SigmaUnknown",
	  "Sigma Unknown", NULL },
};


static void
sigma_deprefix(char *str, const char *prefix)
{
	int l;

	l = strlen(prefix);
	if (!strncmp(str, prefix, l))
		memmove(str, str + l, strlen(str + l) + 1);
}


/*
 * Process Sigma maker note tags.
 */
void
sigma_prop(struct exifprop *prop, struct exiftags *t)
{

	/* Couldn't grok the value somewhere upstream, so nevermind. */

	if (prop->type == TIFF_ASCII && !prop->str)
		return;

	/*
	 * For these, I suppose it's safe to assume that the value prefix
	 * will always be the same.  But, for safety's sake...
	 */
	switch (prop->tag) {

	case 0x000c:
		sigma_deprefix(prop->str, "Expo:");
		break;
	case 0x000d:
		sigma_deprefix(prop->str, "Cont:");
		break;
	case 0x000e:
		sigma_deprefix(prop->str, "Shad:");
		break;
	case 0x000f:
		sigma_deprefix(prop->str, "High:");
		break;
	case 0x0010:
		sigma_deprefix(prop->str, "Satu:");
		break;
	case 0x0011:
		sigma_deprefix(prop->str, "Shar:");
		break;
	case 0x0012:
		sigma_deprefix(prop->str, "Fill:");
		break;
	case 0x0014:
		sigma_deprefix(prop->str, "CC:");
		break;
	case 0x0016:
		sigma_deprefix(prop->str, "Qual:");
		break;
	}
}


/*
 * Try to read a Sigma maker note IFD.
 */
struct ifd *
sigma_ifd(u_int32_t offset, struct tiffmeta *md)
{

	/*
	 * The IFD starts after an 10 byte ID string offset.  The first
	 * 8 bytes are a usual offset, but the next two bytes might be a
	 * version of some sort.  For now, we'll ignore it...
	 */

	if (memcmp("SIGMA\0\0\0", md->btiff + offset, 8) ||
	    memcmp("FOVEON\0\0", md->btiff + offset, 8))
		return (readifds(offset + 10, sigma_tags, md));

	exifwarn("Sigma maker note version not supported");
	return (NULL);
}
