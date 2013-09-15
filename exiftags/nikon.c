/*
 * Copyright (c) 2001-2005, Eric M. Johnston <emj@postal.net>
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
 * $Id: nikon.c,v 1.27 2005/01/04 23:29:31 ejohnst Exp $
 */

/*
 * Exif tag definitions for Nikon maker notes.
 *
 * Some information for Nikon D1X support obtained from JoJoThumb, version
 * 2.7.2 (http://www.jojosoftware.de/jojothumb/).
 *
 * Updated with data from
 * http://www.ozhiker.com/electronics/pjmt/jpeg_info/nikon_mn.html.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "makers.h"


/* Quality. */

static struct descrip nikon_quality[] = {
	{ 1,	"VGA Basic" },
	{ 2,	"VGA Normal" },
	{ 3,	"VGA Fine" },
	{ 4,	"SXGA Basic" },
	{ 5,	"SXGA Normal" },
	{ 6,	"SXGA Fine" },
	{ 10,	"UXGA Basic" },
	{ 11,	"UXGA Normal" },
	{ 12,	"UXGA Fine" },
	{ -1,	"Unknown" },
};


/* Color. */

static struct descrip nikon_color[] = {
	{ 1,	"Color" },
	{ 2,	"Monochrome" },
	{ -1,	"Unknown" },
};


/* Image adjustment. */

static struct descrip nikon_adjust[] = {
	{ 0,	"Normal" },
	{ 1,	"Bright(+)" },
	{ 2,	"Bright(-)" },
	{ 3,	"Contrast(+)" },
	{ 4,	"Contrast(-)" },
	{ -1,	"Unknown" },
};


/* CCD sensitivity. */

static struct descrip nikon_ccd[] = {
	{ 0,	"ISO 80" },
	{ 2,	"ISO 160" },
	{ 4,	"ISO 320" },
	{ 5,	"ISO 100" },
	{ -1,	"Unknown" },
};


/* White balance. */

static struct descrip nikon_white[] = {
	{ 0,	"Auto" },
	{ 1,	"Preset" },
	{ 2,	"Daylight" },
	{ 3,	"Incandescent" },
	{ 4,	"Fluorescent" },
	{ 5,	"Cloudy" },
	{ 6,	"Speedlight" },
	{ -1,	"Unknown" },
};


/* Converter. */

static struct descrip nikon_convert[] = {
	{ 0,	"None" },
	{ 2,	"Fisheye" },
	{ -1,	"Unknown" },
};


/* Flash. */

static struct descrip nikon_flash[] = {
	{ 0,	"No" },
	{ 9,	"Fired" },
	{ -1,	"Unknown" },
};


/* Lens type. */

static struct descrip nikon_lenstype[] = {
	{ 6,	"Nikon D Series" },
	{ 14,	"Nikon G Series" },
	{ -1,	"Unknown" },
};


/* Shooting mode. */

static struct descrip nikon_shoot[] = {
	{ 0,	"Single Frame" },
	{ 1,	"Continuous" },
	{ 2,	"Timer" },
	{ 3,	"Remote Timer" },
	{ 4,	"Remote" },
	{ -1,	"Unknown" },
};


/* Auto focus position. */

static struct descrip nikon_afpos[] = {
	{ 0,	"Center" },
	{ 1,	"Top" },
	{ 2,	"Bottom" },
	{ 3,	"Left" },
	{ 4,	"Right" },
	{ -1,	"Unknown" },
};


/* Auto focus mode. */

static struct descrip nikon_afmode[] = {
	{ 0,	"Single Area" },
	{ 1,	"Dynamic Area" },
	{ 2,	"Closest Subject" },
	{ -1,	"Unknown" },
};


/* Old school Nikon "lookup" maker note IFD tags. */

static struct exiftag nikon_tags0[] = {
	{ 0x0003, TIFF_SHORT, 1, ED_IMG, "NikonQuality",
	  "Image Quality", nikon_quality },
	{ 0x0004, TIFF_SHORT, 1, ED_IMG, "NikonColor",
	  "Color Mode", nikon_color },
	{ 0x0005, TIFF_SHORT, 1, ED_IMG, "NikonImgAdjust",
	  "Image Adjustment", nikon_adjust },
	{ 0x0006, TIFF_SHORT, 1, ED_IMG, "NikonCCDSensitive",
	  "CCD Sensitivity", nikon_ccd },
	{ 0x0007, TIFF_SHORT, 1, ED_IMG, "NikonWhiteBal",
	  "White Balance", nikon_white },
	{ 0x0008, TIFF_RTNL, 1, ED_UNK, "NikonFocus",
	  "Focus", NULL },
	{ 0x000a, TIFF_RTNL, 1, ED_IMG, "NikonDigiZoom",
	  "Digital Zoom", NULL },
	{ 0x000b, TIFF_SHORT, 1, ED_IMG, "NikonAdapter",
	  "Lens Adapter", nikon_convert },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "Unknown",
	  "Nikon Unknown", NULL },
};


/* Newer Nikon ASCII maker note IFD tags. */

static struct exiftag nikon_tags1[] = {
	{ 0x0001, TIFF_UNDEF, 4, ED_VRB, "NikonVersion",
	  "Nikon Note Version", NULL },
	{ 0x0002, TIFF_SHORT, 2, ED_IMG, "NikonISOUsed",
	  "ISO Speed Used", NULL },
	{ 0x0003, TIFF_ASCII, 0, ED_IMG, "NikonColorMode1",
	  "Color Mode", NULL },
	{ 0x0004, TIFF_ASCII, 0, ED_IMG, "NikonQuality",
	  "Image Quality", NULL },
	{ 0x0005, TIFF_ASCII, 0, ED_IMG, "NikonWhiteBal",
	  "White Balance", NULL },
	{ 0x0006, TIFF_ASCII, 0, ED_IMG, "NikonImgSharp",
	  "Image Sharpening", NULL },
	{ 0x0007, TIFF_ASCII, 0, ED_IMG, "NikonFocusMode",
	  "Focus Mode", NULL },
	{ 0x0008, TIFF_ASCII, 0, ED_IMG, "NikonFlashSet",
	  "Flash Setting", NULL },
	{ 0x0009, TIFF_ASCII, 0, ED_IMG, "NikonAutoFlash",
	  "Auto Flash Mode", NULL },
	{ 0x000b, TIFF_SSHORT, 1, ED_UNK, "NikonWhiteBalBias",
	  "White Balance Bias", NULL },
	{ 0x000f, TIFF_ASCII, 0, ED_IMG, "NikonISOSelect",
	  "ISO Selection", NULL },
	{ 0x0012, TIFF_UNDEF, 4, ED_IMG, "NikonFlashComp",
	  "Flash Compensation", NULL },
	{ 0x0013, TIFF_SHORT, 2, ED_IMG, "NikonISOReq",
	  "ISO Speed Requested", NULL },
	{ 0x0018, TIFF_UNDEF, 4, ED_IMG, "NikonFlashBrackComp",
	  "Flash Bracket Compensation", NULL },
	{ 0x0019, TIFF_SRTNL, 1, ED_IMG, "NikonAEBrackComp",
	  "AE Bracket Compensation", NULL },
	{ 0x0080, TIFF_ASCII, 0, ED_IMG, "NikonImgAdjust",
	  "Image Adjustment", NULL },
	{ 0x0081, TIFF_ASCII, 0, ED_IMG, "NikonToneComp",
	  "Tone Compensation", NULL },
	{ 0x0082, TIFF_ASCII, 0, ED_IMG, "NikonLensAdapter",
	  "Lens Adapter", NULL },
	{ 0x0083, TIFF_BYTE, 1, ED_IMG, "NikonLensType",
	  "Lens Type", NULL },
	{ 0x0084, TIFF_RTNL, 4, ED_IMG, "NikonLensRange",
	  "Lens Range", NULL },
	{ 0x0085, TIFF_RTNL, 1, ED_IMG, "NikonFocusDist",
	  "Focus Distance", NULL },
	{ 0x0086, TIFF_RTNL, 1, ED_IMG, "NikonDigiZoom",
	  "Digital Zoom", NULL },
	{ 0x0087, TIFF_BYTE, 1, ED_VRB, "NikonFlashUsed",
	  "Flash Used", nikon_flash },
	{ 0x0088, TIFF_UNDEF, 4, ED_IMG, "NikonAutoFocus",
	  "Auto Focus", NULL },
	/* Is either BYTE (D100) or SHORT (D70). */
	{ 0x0089, TIFF_UNKN, 1, ED_IMG, "NikonShootBrack",
	  "Shooting/Bracketing Mode", NULL },
	{ 0x008d, TIFF_ASCII, 0, ED_IMG, "NikonColorMode2",
	  "Color Mode", NULL },
	{ 0x008f, TIFF_ASCII, 0, ED_IMG, "NikonSceneMode",
	  "Scene Mode", NULL },
	{ 0x0090, TIFF_ASCII, 0, ED_IMG, "NikonLighting",
	  "Lighting Type", NULL },
	{ 0x0092, TIFF_SSHORT, 1, ED_UNK, "NikonHueAdjust",
	  "Hue Adjustment", NULL },
	{ 0x0094, TIFF_SSHORT, 1, ED_IMG, "NikonSaturate",
	  "Saturation", NULL },
	{ 0x0095, TIFF_ASCII, 0, ED_IMG, "NikonNoiseReduce",
	  "Noise Reduction", NULL },
	{ 0x00a0, TIFF_ASCII, 0, ED_CAM, "NikonSerial",
	  "Serial Number", NULL },
	{ 0x00a7, TIFF_LONG, 1, ED_IMG, "NikonAcuations",
	  "Camera Actuations", NULL },
	{ 0x00a9, TIFF_ASCII, 0, ED_IMG, "NikonImageOpt",
	  "Image Optimization", NULL },
	{ 0x00aa, TIFF_ASCII, 0, ED_IMG, "NikonSaturate2",
	  "Saturation 2", NULL },
	{ 0x00ab, TIFF_ASCII, 0, ED_IMG, "NikonDigiProg",
	  "Digital Vari-Program", NULL },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "Unknown",
	  "Nikon Unknown", NULL },
};


/*
 * Process older Nikon maker note tags.
 */
static void
nikon_prop0(struct exifprop *prop, struct exiftags *t)
{
	u_int32_t a, b;

	switch (prop->tag) {

	/* Digital zoom. */

	case 0x000a:
		a = exif4byte(t->mkrmd.btiff + prop->value, t->mkrmd.order);
		b = exif4byte(t->mkrmd.btiff + prop->value + 4, t->mkrmd.order);

		if (!a) {
			snprintf(prop->str, 31, "None");
			prop->lvl = ED_VRB;
		} else
			snprintf(prop->str, 31, "x%.1f", (float)a / (float)b);
		break;
	}
}


/*
 * Process newer Nikon maker note tags.
 */
static void
nikon_prop1(struct exifprop *prop, struct exiftags *t)
{
	int i;
	u_int32_t v[8];
	char *c1, *c2, *c3;
	int32_t sn, sd;
	char buf[5];

	switch (prop->tag) {

	/*
	 * Nikon maker note version.
	 * XXX Note that earlier versions aren't ASCII, and that we
	 * don't handle them yet.
	 */

	case 0x0001:
		byte4exif(prop->value, (unsigned char *)buf, t->mkrmd.order);
		buf[4] = '\0';
		v[1] = atoi(buf + 2);
		buf[2] = '\0';
		v[0] = atoi(buf);

		exifstralloc(&prop->str, 8);
		snprintf(prop->str, 7, "%d.%d", v[0], v[1]);
		break;

	/*
	 * ISO values.  Two shorts stuffed into the value; we only care
	 * about the second one.  (First is always zero?)
	 */

	case 0x0002:
	case 0x0013:
		/*
		 * XXX Well, this is messy.  Nikon stuffs the two shorts into
		 * into the tag value, rather than referencing an offset.
		 * Byte order screws with us here...  (Need to fix!)
		 */
		if (t->mkrmd.order == LITTLE)
			v[0] = (prop->value >> 16) & 0xffff;
		else
			v[0] = prop->value & 0xffff;

		exifstralloc(&prop->str, 32);
		snprintf(prop->str, 31, "%d", (u_int16_t)v[0]);
		if (!v[0]) prop->lvl = ED_VRB;
		break;

	/* White balance. */

	case 0x0005:
		prop->override = EXIF_T_WHITEBAL;
		break;

	/* Flash [bracket] compensation.  Four values here; we only know one. */

	case 0x0012:
	case 0x0018:
		exifstralloc(&prop->str, 10);
		snprintf(prop->str, 9, "%.1f EV",
		    (int16_t)(prop->value >> 24) / 6.0);
		break;

	/* AE bracket compensation. */

	case 0x0019:
		sn = exif4byte(t->mkrmd.btiff + prop->value, t->mkrmd.order);
		sd = exif4byte(t->mkrmd.btiff + prop->value + 4,
		    t->mkrmd.order);

		if (sn && !sd) {
			snprintf(prop->str, 31, "n/a");
			prop->lvl = ED_VRB;
		} else
			snprintf(prop->str, 31, "%.1f EV", (float)sn /
			    (float)sd);
		break;

	/* Lens type. */

	case 0x0083:
		prop->str = finddescr(nikon_lenstype,
		    (u_int16_t)((prop->value >> 24) & 0xff));
		break;

	/* Lens range. */

	case 0x0084:
		if (prop->value + prop->count * 8 >
		    (u_int32_t)(t->mkrmd.etiff - t->mkrmd.btiff))
			break;

		for (i = 0; i < 8; i++)
			v[i] = exif4byte(t->mkrmd.btiff + prop->value + (i * 4),
			    t->mkrmd.order);

		if ((v[0] && !v[1]) || (v[2] && !v[3]) ||
		    (v[4] && !v[5]) || (v[6] && !v[7])) {
			snprintf(prop->str, 31, "n/a");
			prop->lvl = ED_VRB;
			break;
		}

		/* XXX Err, kind of a mess. */
		if (v[0] == v[2] && v[1] == v[3]) {
			if (v[4] == v[6] && v[5] == v[7]) {
				snprintf(prop->str, 31, "%.1f mm; f/%.1f",
				    (float)v[0] / (float)v[1], 
				    (float)v[4] / (float)v[5]);
				break;
			}

			snprintf(prop->str, 31, "%.1f mm; f/%.1f - f/%.1f",
			    (float)v[0] / (float)v[1], (float)v[4] /
			    (float)v[5], (float)v[6] / (float)v[7]);
			break;
		}

		if (v[4] == v[6] && v[5] == v[7]) {
			snprintf(prop->str, 31, "%.1f - %.1f mm; f/%.1f",
			    (float)v[0] / (float)v[1], (float)v[2] /
			    (float)v[3], (float)v[4] / (float)v[5]);
			break;
		}

		snprintf(prop->str, 31, "%.1f - %.1f mm; f/%.1f - f/%.1f",
		    (float)v[0] / (float)v[1], (float)v[2] / (float)v[3],
		    (float)v[4] / (float)v[5], (float)v[6] / (float)v[7]);
		break;

	/* Manual focus distance. */

	case 0x0085:
		v[0] = exif4byte(t->mkrmd.btiff + prop->value, t->mkrmd.order);
		v[1] = exif4byte(t->mkrmd.btiff + prop->value + 4,
		    t->mkrmd.order);

		if (v[0] == v[1] || (v[0] && !v[1])) {
			snprintf(prop->str, 31, "n/a");
			prop->lvl = ED_VRB;
		} else
			snprintf(prop->str, 31, "x%.1f m", (float)v[0] /
			    (float)v[1]);
		break;

	/* Digital zoom. */

	case 0x0086:
		v[0] = exif4byte(t->mkrmd.btiff + prop->value, t->mkrmd.order);
		v[1] = exif4byte(t->mkrmd.btiff + prop->value + 4,
		    t->mkrmd.order);

		if (v[0] == v[1] || !v[0] || (v[0] && !v[1])) {
			snprintf(prop->str, 31, "None");
			prop->lvl = ED_VRB;
		} else
			snprintf(prop->str, 31, "x%.1f", (float)v[0] /
			    (float)v[1]);
		break;

	/*
	 * Auto focus position.
	 * XXX Need some feedback from users here -- guessing somewhat.
	 */

	case 0x0088:
		/*
		 * An older/simpler method?  (Byte 3 only.)
		 * Note that cameras using the newer method will get caught
		 * here on Single Area, Center (and just show Center).
		 */
		if (!(prop->value & 0xffff00ff)) {
			if (prop->str) printf("err, hello?  overwriting?\n");
			prop->str = finddescr(nikon_afpos,
			    (u_int16_t)((prop->value >> 8) & 0xff));
			break;
		}

		/* Byte 1, mode. */
		c1 = finddescr(nikon_afmode,
		    (u_int16_t)((prop->value >> 24) & 0xff));

		/* Byte 2, area selected; byte 4, area focused. */
		c2 = finddescr(nikon_afpos, (u_int16_t)(prop->value & 0xff));

		if ((prop->value & 0xff) == ((prop->value >> 16) & 0xff)) {
			exifstralloc(&prop->str, strlen(c1) + strlen(c2) + 3);
			sprintf(prop->str, "%s, %s", c1, c2);

		} else {
			c3 = finddescr(nikon_afpos,
			    (u_int16_t)((prop->value >> 16) & 0xff));
			exifstralloc(&prop->str, strlen(c1) + strlen(c2) +
			    strlen(c3) + 24);
			sprintf(prop->str, "%s, %s Selected, %s Focused",
			    c1, c3, c2);
			free(c3);
		}
		free(c1);
		free(c2);
		break;

	/*
	 * Bracketing/shooting mode.
	 * XXX I've probably made this a lot more complicated than it
	 * needs to be.  Would be nice to be able to experiment...
	 */

	case 0x0089:
		/* XXX Shouldn't be necessary. */
		if (prop->type == TIFF_BYTE)
			prop->value = (prop->value >> 24) & 0xff;
		else if (prop->type == TIFF_SHORT)
			prop->value = (prop->value >> 8) & 0xff;

		/* Bits 0 & 1. */
		c1 = finddescr(nikon_shoot, (u_int16_t)(prop->value & 0x03));

		/* Bit 4 = bracketing, bit 6 = white balance bracketing. */
		if (prop->value & 0x40) {
			if (prop->value & 0x10)
				c2 = "On, White Balance";
			else
				c2 = "Off, White Balance";
		} else {
			if (prop->value & 0x10)
				c2 = "On";
			else
				c2 = "Off";
		}

		exifstralloc(&prop->str, strlen(c1) + strlen(c2) + 2);
		sprintf(prop->str, "%s/%s", c1, c2);
		free(c1);
		break;

	/* Color mode. */

	case 0x008d:
		if (!(c1 = prop->str)) break;

		if (!strncmp(c1, "MODE1a", 6)) {
			free(c1);
			prop->str = NULL;
			c1 = "Portrait sRGB";
			exifstralloc(&prop->str, strlen(c1) + 1);
			strcpy(prop->str, c1);
			break;
		}

		if (!strncmp(c1, "MODE2", 5)) {
			free(c1);
			prop->str = NULL;
			c1 = "Adobe RGB";
			exifstralloc(&prop->str, strlen(c1) + 1);
			strcpy(prop->str, c1);
			break;
		}

		if (!strncmp(c1, "MODE3a", 6)) {
			free(c1);
			prop->str = NULL;
			c1 = "Landscape sRGB";
			exifstralloc(&prop->str, strlen(c1) + 1);
			strcpy(prop->str, c1);
			break;
		}
		break;

	/* Saturation.  (Signed, so can't just do lookup table.) */

	case 0x0094:
		c1 = NULL;
		switch (prop->value) {
		case -3:
			c1 = "Black & White";
			exifstralloc(&prop->str, strlen(c1) + 1);
			strcpy(prop->str, c1);
			break;

		case 0:
			c1 = "Normal";
			exifstralloc(&prop->str, strlen(c1) + 1);
			strcpy(prop->str, c1);
			break;
		}

		if (!c1) {
			prop->lvl = ED_VRB;
			break;
		}
		/* FALLTHROUGH */

	case 0x00aa:
		prop->override = EXIF_T_SATURATION;
		break;

	/* Serial number. */

	case 0x00a0:
		/* Remove prefix. */
		if (!strncmp(prop->str, "NO= ", 4))
			memmove(prop->str, prop->str + 4,
			    strlen(prop->str + 4) + 1);

		/* Remove leading whitespace. */
		for (c1 = prop->str; *c1 && *c1 == (unsigned char)' '; c1++);
		if (*c1 && c1 > prop->str)
			memmove(prop->str, c1, strlen(c1) + 1);
		break;
	}
}


/*
 * Process Nikon maker note tags.
 */
void
nikon_prop(struct exifprop *prop, struct exiftags *t)
{
	int i;

	for (i = 0; prop->tagset[i].tag < EXIF_T_UNKNOWN &&
	    prop->tagset[i].tag != prop->tag; i++);

	if (prop->tagset[i].type && prop->tagset[i].type != prop->type)
		exifwarn2("field type mismatch", prop->name);

	/*
	 * Check the field count.
	 * XXX For whatever the reason, Sigma doesn't follow the
	 * spec on count for FileSource.
	 */

	if (prop->tagset[i].count && prop->tagset[i].count != prop->count)
		exifwarn2("field count mismatch", prop->name);

	if (prop->tagset == nikon_tags0) {
		nikon_prop0(prop, t);
		return;
	}

	if (prop->tagset == nikon_tags1) {
		nikon_prop1(prop, t);
		return;
	}
}


/*
 * Try to read a Nikon maker note IFD.
 */
struct ifd *
nikon_ifd(u_int32_t offset, struct tiffmeta *md)
{
	struct ifd *myifd;
	unsigned char *b;

	b = md->btiff + offset;

	/*
	 * Seems that some Nikon maker notes start with an ID string and
	 * a version of some sort.
	 */

	if (!strcmp((const char *)b, "Nikon")) {
		b += 6;
		switch (exif2byte(b, BIG)) {
		case 0x0100:
			readifd(offset + 8, &myifd, nikon_tags0, md);
			return (myifd);

		case 0x0200:
		case 0x0210:
			b += 4;

			/*
			 * So, this is interesting: they've put a full-fledged
			 * TIFF header here.
			 */

			/* Determine endianness of the TIFF data. */

			if (!memcmp(b, "MM", 2))
				md->order = BIG;
			else if (!memcmp(b, "II", 2))
				md->order = LITTLE;
			else {
				exifwarn("invalid Nikon TIFF header");
				return (NULL);
			}
			md->btiff = b;		/* Beginning of maker. */
			b += 2;

			/* Verify the TIFF header. */

			if (exif2byte(b, md->order) != 42) {
				exifwarn("invalid Nikon TIFF header");
				return (NULL);
			}
			b += 2;

			readifd(exif4byte(b, md->order), &myifd,
			    nikon_tags1, md);
			return (myifd);

		default:
			exifwarn("Nikon maker note version not supported");
			return (NULL);
		}
	}

	/*
	 * Others are just normal IFDs.
	 */

	readifd(offset, &myifd, nikon_tags1, md);
	return (myifd);
}
