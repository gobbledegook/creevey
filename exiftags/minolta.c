/*
 * Copyright (c) 2003, Javier Crespo <jcrespoc@dsland.org>
 * Copyright (c) 2003-2007, Eric M. Johnston <emj@postal.net>
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
 * $Id: minolta.c,v 1.29 2007/12/15 21:01:23 ejohnst Exp $
 *
 */ 

/*
 * Exif tag definitions for Minolta DiMAGE maker notes.
 * Tags deciphered by Javier Crespo <jcrespoc@dsland.org>.
 *
 * Mostly supported models: DiMAGE 5, 7, 7i, and 7Hi.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "makers.h"


/* Bracketing mode. */

static struct descrip minolta_brackmode[] = {
	{ 0,	"Exposure" },
	{ 1,	"Contrast" },
	{ 2,	"Saturation" },
	{ 3,	"Filter" },
	{ -1,	"Unknown" },
};


/* Bracketing step. */

static struct descrip minolta_brackstep[] = {
	{ 0,	"1/3" },
	{ 1,	"1/2" },
	{ 2,	"1" },
	{ -1,	"Unknown" },
};


/* Sharpness. */

static struct descrip minolta_sharp[] = {
	{ 0,	"Hard" },
	{ 1,	"Normal" },
	{ 2,	"Soft" },
	{ -1,	"Unknown" },
};


/* Color mode. */

static struct descrip minolta_color[] = {
	{ 0,	"Natural Color" },
	{ 1,	"Black & White" },
	{ 2,	"Vivid Color" },
	{ 3,	"Solarization" },
	{ 4,	"Adobe RGB" },
	{ -1,	"Unknown" },
};


/* ISO. */

static struct descrip minolta_iso[] = {
	{ 0,	"100" },
	{ 1,	"200" },
	{ 2,	"400" },
	{ 3,	"800" },
	{ 4,	"Auto" },
	{ -1,	"Unknown" },
};


/* Generic boolean. */

static struct descrip minolta_bool[] = {
	{ 0,	"No" },
	{ 1,	"Yes" },
	{ -1,	"Unknown" },
};


/* Focus mode. */

static struct descrip minolta_focusmode[] = {
	{ 0,	"Auto" },
	{ 1,	"Manual" },
	{ -1,	"Unknown" },
};


/* Focus area. */

static struct descrip minolta_focusarea[] = {
	{ 0,	"Wide Area" },
	{ 1,	"Spot Focus Point" },
	{ -1,	"Unknown" },
};


/* Wide area focus zone. */

static struct descrip minolta_widefocus[] = {
	{ 0,	"No Zone" },
	{ 1,	"Center" },
	{ 3,	"Left" },
	{ 4,	"Right" },
	{ -1,	"Unknown" },
};


/* Drive mode. */

static struct descrip minolta_drive[] = {
	{ 0,	"Single Frame" },
	{ 1,	"Continous Advance" },
	{ 2,	"Self Timer" },
	{ 4,	"Bracketing" },
	{ 5,	"Interval" },
	{ 6,	"UHS" },
	{ 7,	"HS" },
	{ -1,	"Unknown" },
};


/* White balance. */

static struct descrip minolta_whitebal[] = {
	{ 0,	"Auto" },
	{ 1,	"Daylight" },
	{ 2,	"Cloudy" },
	{ 3,	"Tungsten" },
	{ 5,	"Custom" },
	{ 7,	"Fluorescent" },
	{ 8,	"Fluorescent 2" },
	{ 11,	"Custom 2" },
	{ 12,	"Custom 3" },
	{ -1,	"Unknown" },
};


/* Flash mode. */

static struct descrip minolta_flash[] = {
	{ 0,	"Fill Flash" },
	{ 1,	"Red-Eye Reduction" },
	{ 2,	"Rear Sync" },
	{ 3,	"Remote" },
	{ -1,	"Unknown" },
};


/* Capture scene. */

static struct descrip minolta_scene[] = {
	{ 0,	"Normal" },
	{ 1,	"Portrait" },
	{ 2,	"Text" },
	{ 3,	"Night Portrait" },
	{ 4,	"Sunset" },
	{ 5,	"Sports Action" },
	{ -1,	"Unknown" },
};


/* Image quality. */

static struct descrip minolta_quality[] = {
	{ 0,	"Raw" },
	{ 1,	"Super Fine" },
	{ 2,	"Fine" },
	{ 3,	"Standard" },
	{ 4,	"Economy" },
	{ 5,	"Extra Fine" },
	{ -1,	"Unknown" },
};


/* Exposure program. */

static struct descrip minolta_prog[] = {
	{ 0,	"Program AE" },
	{ 1,	"Aperture Priority" },
	{ 2,	"Shutter Priority" },
	{ 3,	"Manual" },
	{ -1,	"Unknown" },
};


/*
 * Image size.
 * Valid only for 5 megapixel cameras (D7's), wrong for D5.
 */

static struct descrip minolta_size[] = {
	{ 0,	"2560x1920" },
	{ 1,	"1600x1200" },
	{ 2,	"1280x960" },
	{ 3,	"640x480" },
	{ -1,	"Unknown" },
};


/* Folder name. */

static struct descrip minolta_folder[] = {
	{ 0,	"Standard" },
	{ 1,	"Date" },
	{ -1,	"Unknown" },
};


/* Data imprinting. */

static struct descrip minolta_imprint[] = {
	{ 0,	"None" },
	{ 1,	"DataTime Y/M/D" },
	{ 2,	"DataTime M/D H:M" },
	{ 3,	"Text" },
	{ 4,	"Text + ID" },
	{ -1,	"Unknown" },
};


/* Camera model. */

static struct descrip minolta_model[] = {
	{ 0,	"DiMAGE 7" },
	{ 1,	"DiMAGE 5" },
	{ 4,	"DiMAGE 7i" },
	{ 5,	"DiMAGE 7Hi" },
	{ -1,	"Unknown" },
};


/* Metering mode. */

static struct descrip minolta_metermode[] = {
	{ 0,	"Multi-Segment" },
	{ 1,	"Center Weighted Average" },
	{ 2,	"Spot" },
	{ -1,	"Unknown" },
};


/* Maker note IFD tags. */

static struct exiftag minolta_tags[] = {
	{ 0x0000, TIFF_UNDEF, 4, ED_UNK, "MinoltaMakerType",
	  "Minolta Maker Note Type", NULL },
	{ 0x0001, TIFF_UNDEF, 0, ED_UNK, "Minolta1Tag",
	  "Minolta Tag1 Offset", NULL },
	{ 0x0003, TIFF_UNDEF, 0, ED_UNK, "Minolta3Tag",
	  "Minolta Tag3 Offset", NULL },
	{ 0x0040, TIFF_LONG, 1, ED_UNK, "MinoltaCompImgSz",
	  "Minolta Compressed Image Size", NULL },
	{ 0x0088, TIFF_LONG, 1, ED_UNK, "MinoltaThumbOff",
	  "Minolta Thumbnail Offset", NULL },
	{ 0x0089, TIFF_LONG, 1, ED_UNK, "MinoltaThumbLen",
	  "Minolta Thumbnail Length", NULL },
	{ 0x0e00, TIFF_UNDEF, 0, ED_UNK, "MinoltaPIM",
	  "Minolta Print Image Management", NULL },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "Unknown",
	  "Minolta Unknown", NULL },
};


/* Fields under tags 0x0001 and 0x0003. */

static struct exiftag minolta_MLT0[] = {
	{ 1,  TIFF_LONG, 1, ED_IMG, "MinoltaExpProg",
	  "Exposure Program", minolta_prog },
	{ 2,  TIFF_LONG, 1, ED_IMG, "MinoltaFlashMode",
	  "Flash Mode", minolta_flash },
	{ 3,  TIFF_LONG, 1, ED_IMG, "MinoltaWhiteB",
	  "White Balance", minolta_whitebal },
	{ 4,  TIFF_LONG, 1, ED_UNK, "MinoltaSize",
	  "Image Size", minolta_size },
	{ 5,  TIFF_LONG, 1, ED_IMG, "MinoltaQuality",
	  "Image Quality", minolta_quality },
	{ 6,  TIFF_LONG, 1, ED_IMG, "MinoltaDriveMode",
	  "Drive Mode", minolta_drive },
	{ 7,  TIFF_LONG, 1, ED_IMG, "MinoltaMeterMode",
	  "Metering Mode", minolta_metermode },
	{ 8,  TIFF_LONG, 1, ED_UNK, "MinoltaFilmSpeed",
	  "Film Speed", NULL },
	{ 9,  TIFF_LONG, 1, ED_VRB, "MinoltaExpTime",
	  "Exposure Time", NULL },
	{ 10, TIFF_LONG, 1, ED_UNK, "MinoltaAperture",
	  "Lens Aperture", NULL },
	{ 11, TIFF_LONG, 1, ED_IMG, "MinoltaMacro",
	  "Macro", minolta_bool },
	{ 12, TIFF_LONG, 1, ED_IMG, "MinoltaDigiZoom",
	  "Digital Zoom", minolta_bool },
	{ 13, TIFF_LONG, 1, ED_UNK, "MinoltaExpComp",
	  "Exposure Compensation", NULL },
	{ 14, TIFF_LONG, 1, ED_IMG, "MinoltaBracketStep",
	  "Bracketing Step", minolta_brackstep },
	{ 16, TIFF_LONG, 1, ED_VRB, "MinoltaIntrvlTime",
	  "Interval Time", NULL },
	{ 17, TIFF_LONG, 1, ED_VRB, "MinoltaIntrvlPics",
	  "Interval Pics", NULL },
	{ 18, TIFF_LONG, 1, ED_UNK, "MinoltaFocalLen",
	  "Focal Length", NULL },
	{ 19, TIFF_LONG, 1, ED_IMG, "MinoltaFocusDist",
	  "Focus Distance", NULL },
	{ 20, TIFF_LONG, 1, ED_VRB, "MinoltaFlash",
	  "Flash Fired", minolta_bool },
	{ 21, TIFF_LONG, 1, ED_VRB, "MinoltaDate",
	  "Date", NULL },
	{ 22, TIFF_LONG, 1, ED_VRB, "MinoltaTime",
	  "Time", NULL },
	{ 23, TIFF_LONG, 1, ED_UNK, "MinoltaMaxAperture",
	  "Maximum Lens Aperture", NULL },
	{ 26, TIFF_LONG, 1, ED_VRB, "MinoltaRmbrFileNum",
	  "File Number Memory", minolta_bool },
	{ 27, TIFF_LONG, 1, ED_VRB, "MinoltaSequence",
	  "Sequence Number", NULL },
	{ 31, TIFF_LONG, 1, ED_IMG, "MinoltaSaturate",
	  "Saturation", NULL },
	{ 32, TIFF_LONG, 1, ED_IMG, "MinoltaContrast",
	  "Contrast", NULL },
	{ 33, TIFF_LONG, 1, ED_IMG, "MinoltaSharpness",
	  "Sharpness", minolta_sharp },
	{ 34, TIFF_LONG, 1, ED_IMG, "MinoltaScene",
	  "Scene Capture Type", minolta_scene },
	{ 35, TIFF_LONG, 1, ED_IMG, "MinoltaFlashComp",
	  "Flash Compensation", NULL },
	{ 36, TIFF_LONG, 1, ED_VRB, "MinoltaISO",
	  "ISO Speed Rating", minolta_iso },
	{ 37, TIFF_LONG, 1, ED_UNK, "MinoltaModel",
	  "Camera Model", minolta_model },
	{ 38, TIFF_LONG, 1, ED_VRB, "MinoltaIntervalMode",
	  "Interval Mode", minolta_bool },
	{ 39, TIFF_LONG, 1, ED_VRB, "MinoltaFolder",
	  "Folder Name", minolta_folder },
	{ 40, TIFF_LONG, 1, ED_IMG, "MinoltaColorMode",
	  "Color Mode", minolta_color },
	{ 41, TIFF_LONG, 1, ED_IMG, "MinoltaColorFilt",
	  "Color Warming", NULL },
	{ 42, TIFF_LONG, 1, ED_IMG, "MinoltaBWFilt",
	  "Black & White Tone", NULL },
	{ 43, TIFF_LONG, 1, ED_VRB, "MinoltaIntFlash",
	  "Internal Flash", minolta_bool },
	{ 45, TIFF_LONG, 1, ED_VRB, "MinoltaFocusX",
	  "AF Point X", NULL },
	{ 46, TIFF_LONG, 1, ED_VRB, "MinoltaFocusY",
	  "AF Point Y", NULL },
	{ 47, TIFF_LONG, 1, ED_VRB, "MinoltaWFocusZone",
	  "AF Zone", minolta_widefocus },
	{ 48, TIFF_LONG, 1, ED_IMG, "MinoltaFocusMode",
	  "Focus Mode", minolta_focusmode },
	{ 49, TIFF_LONG, 1, ED_IMG, "MinoltaAFArea",
	  "Wide Focus Area", minolta_focusarea },
	{ 50, TIFF_LONG, 1, ED_IMG, "MinoltaBracketMode",
	  "Bracketing Mode", minolta_brackmode },
	{ 51, TIFF_LONG, 1, ED_VRB, "MinoltaDataImprint",
	  "Data Imprint", minolta_imprint },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "MinoltaUnknown",
	  "Minolta Field Unknown", NULL },
};


/* Stub to display unknown fields for some models. */

static struct exiftag minolta_unkn[] = {
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "MinoltaUnknown",
	  "Minolta Field Unknown", NULL },
};


/*
 * Process maker note tag 0x0001 and 0x0003 fields.
 */
void
minolta_cprop(struct exifprop *prop, unsigned char *off, struct exiftags *t,
    struct exiftag *thetags)
{
	unsigned int i, j, k;
	u_int32_t v;
	int32_t model;
	double d;
	char *valbuf;
	unsigned char buf[8];
	struct exifprop *aprop;

	valbuf = NULL;
	model = -1;

	for (i = 0; i * 4 < prop->count; i++) {

		/*
		 * XXX It appears that the 7Hi oddly inserts a value at
		 * position 51, pushing everything down one.  We'll just
		 * skip #51.
		 */

		if (thetags == minolta_MLT0 && i >= 51 && model == 5) {
			if (i == 51) continue;
			k = i - 1;
		} else
			k = i;

		aprop = childprop(prop);
		aprop->tag = i;
		aprop->tagset = thetags;

		/* Note: these are big-endian regardless. */
		aprop->value = exif4byte(off + (4 * i), BIG);

		/* Lookup property name and description. */

		for (j = 0; thetags[j].tag < EXIF_T_UNKNOWN &&
			thetags[j].tag != k; j++);
		aprop->name = thetags[j].name;
		aprop->descr = thetags[j].descr;
		aprop->lvl = thetags[j].lvl;
		if (thetags[j].table)
			aprop->str = finddescr(thetags[j].table,
			    (u_int16_t)aprop->value);

		dumpprop(aprop, NULL);

		/*
		 * Further process known properties.
		 * XXX If currently unsupported fields are implemented,
		 * this section will have to be specific to the set of
		 * tags passed in.
		 */

		if (thetags != minolta_MLT0)
			continue;

		if (!valbuf)
			exifstralloc(&valbuf, 16);

		switch (k) {

		/* Interval time and sequence number. */

		case 16:
		case 27:
			aprop->value += 1;
			break;

		/* Exposure and flash compensation. */

		case 13:
		case 35:
			aprop->str = valbuf;
			valbuf = NULL;
			if (aprop->value != 6)
				snprintf(aprop->str, 15, "%+0.1f EV",
				    ((double)aprop->value - 6) / 3);
			else
				snprintf(aprop->str, 15, "Normal");
			break;

		/* Camera model (saved for 7Hi stupidity). */

		case 37:
			model = aprop->value;
			break;

		/* Focal length. */

		case 18:
			aprop->str = valbuf;
			valbuf = NULL;
			snprintf(aprop->str, 15, "%02f",
			    (double)aprop->value / 256);
			break;

		/* Still unknown. */

		case 28:
		case 29:
		case 30:
			aprop->str = valbuf;
			valbuf = NULL;
			snprintf(aprop->str, 15, "%0.6f",
			    (double)aprop->value / 256);
			break;

		/* Film speed. */

		case 8:
			aprop->str = valbuf;
			valbuf = NULL;
			v = (u_int16_t)(pow(2, ((double)aprop->value / 8) -
			    1) * (double)3.125);
			snprintf(aprop->str, 15, "%d", v);
			break;

		/* Aperture and max aperture. */

		case 10:
		case 23:
			aprop->str = valbuf;
			valbuf = NULL;
			d = pow(2, ((double)aprop->value / 16) - 0.5);
			snprintf(aprop->str, 15, "%0.1f", d);
			break;

		/* Exposure time. */

		case 9:
			aprop->str = valbuf;
			valbuf = NULL;
			d = (double)pow(2,
			    ((double)abs(48 - (int)aprop->value)) / 8); // the compiler is apparently too stupid to know that 48 - (unsigned) might be negative

			/* 1 sec limit. */
			if (aprop->value < 56)
				snprintf(aprop->str, 15, "%0.1f", d);
			else
				snprintf(aprop->str, 15, "1/%d",
				    (unsigned int)d);
#if 0
			/*
			 * Bulb mode D7i bug: always recorded as 30 sec in
			 * EXIF_T_EXPOSURE, so override.
			 */
			if (aprop->value < 32) {
				aprop->override = EXIF_T_EXPOSURE;
				aprop->lvl = ED_IMG;
			}
#endif
			break;

		/* Focus distance. */

		case 19:
			aprop->str = valbuf;
			valbuf = NULL;
			if (!aprop->value)
				strcpy(aprop->str, "Infinite");
			else
				snprintf(aprop->str, 15, "%.1f",
				    (float)(aprop->value / (float)1000));
			aprop->value /= 100;
			break;

		/* Exposure program. */

		case 1:
			aprop->override = EXIF_T_EXPPROG;
			break;

		/* Date. */

		case 21:
			aprop->str = valbuf;
			valbuf = NULL;
			byte4exif(aprop->value, buf, LITTLE);
			snprintf(aprop->str, 15, "%02d/%02d/%04d",
			    buf[0], buf[1], buf[3] << 8 | buf[2]);
			break;

		/* Time. */

		case 22:
			aprop->str = valbuf;
			valbuf = NULL;
			byte4exif(aprop->value, buf, LITTLE);
			snprintf(aprop->str, 9, "%02d:%02d:%02d",
			    buf[2], buf[1], buf[0]);
			break;

		/* White balance. */

		case 3:
			aprop->override = EXIF_T_WHITEBAL;
			break;

		/* Sharpness. */

		case 33:
			aprop->override = EXIF_T_SHARPNESS;
			break;

		/* Metering mode. */

		case 7:
			aprop->override = EXIF_T_METERMODE;
			break;

		/* Saturation, contrast, & color filter. */

		case 31:
		case 32:
			aprop->override = (i == 31 ? EXIF_T_SATURATION :
			    EXIF_T_CONTRAST);
			/* FALLTHROUGH */
		case 41:
			aprop->str = valbuf;
			valbuf = NULL;
			aprop->value -= 3;
			if (aprop->value)
				snprintf(aprop->str, 15, "%+d", aprop->value);
			else
				strcpy(aprop->str, "Normal");
			break;

		/* Scene. */

		case 34:
			aprop->override = EXIF_T_SCENECAPTYPE;
			break;
		}
	}
	if (valbuf)
		free(valbuf);
}


/*
 * Make sure meaningless values are meaningless.
 */
static void
minolta_naval(struct exifprop *props, struct exiftag *t, int16_t tag)
{
	struct exifprop *prop;
	const char *na = "n/a";

	if (!(prop = findprop(props, t, tag)))
		return;

	free(prop->str);
	prop->str = NULL;
	exifstralloc(&prop->str, strlen(na) + 1);
	strcpy(prop->str, na);
	if (!(prop->lvl & ED_UNK))
		prop->lvl = ED_VRB;
}


/*
 * Process Minolta maker note tags.
 */
void
minolta_prop(struct exifprop *prop, struct exiftags *t)
{
	struct exiftag *fielddefs = NULL;
	struct exifprop *tmpprop;

	if (debug) {
		static int once = 0;	/* XXX Breaks on multiple files. */

		if (!once) {
			printf("Processing Minolta Maker Note\n");
			once = 1;
		}
		dumpprop(prop, NULL);
	}

	switch (prop->tag) {

	/* Maker note type. */

	case 0x0000:
		if (prop->count < 4)
			break;
		exifstralloc(&prop->str, prop->count + 1);
		byte4exif(prop->value, (unsigned char *)prop->str,
		    t->mkrmd.order);

		/* We recognize two types: MLT0 and mlt0. */

		if (strcmp(prop->str, "MLT0") && strcmp(prop->str, "mlt0"))
			exifwarn2("Minolta maker note version not supported",
			    prop->str);
		break;

	/*
	 * Various image data.
	 * For now, we only trust specifically-sized tags.
	 */

	case 0x0001:
		if (prop->count != 39 * 4) {
			exifwarn("Minolta maker note not fully supported");
			fielddefs = minolta_unkn;
		} else
			fielddefs = minolta_MLT0;
		minolta_cprop(prop, t->mkrmd.btiff + prop->value, t, fielddefs);
		break;

	case 0x0003:
		if (prop->count != 56 * 4 && prop->count != 57 * 4) {
			exifwarn("Minolta maker note not fully supported");
			fielddefs = minolta_unkn;
		} else
			fielddefs = minolta_MLT0;
		minolta_cprop(prop, t->mkrmd.btiff + prop->value, t, fielddefs);
		break;
	}

	/* Override meaningless values. */

	if (fielddefs) {

		/* Drive mode (bracketing step & mode). */

		if ((tmpprop = findprop(t->props, fielddefs, 6)))
			if (tmpprop->value != 4) {
				minolta_naval(t->props, fielddefs, 14);
				minolta_naval(t->props, fielddefs, 50);
			}

		/* Focus mode (wide focus area, AF zone, point X & Y). */

		if ((tmpprop = findprop(t->props, fielddefs, 48)))
			if (tmpprop->value == 1) {
				minolta_naval(t->props, fielddefs, 45);
				minolta_naval(t->props, fielddefs, 46);
				minolta_naval(t->props, fielddefs, 47);
				minolta_naval(t->props, fielddefs, 49);
			}

		/* Flash fired (flash comp, mode, & internal flash). */

		if ((tmpprop = findprop(t->props, fielddefs, 20)))
			if (tmpprop->value != 1) {
				minolta_naval(t->props, fielddefs, 2);
				minolta_naval(t->props, fielddefs, 35);
				minolta_naval(t->props, fielddefs, 43);
			}

		/* Exposure mode (meter mode, exposure comp). */

		if ((tmpprop = findprop(t->props, tags, EXIF_T_EXPMODE)))
			if (tmpprop->value == 1) {
				minolta_naval(t->props, fielddefs, 7);
				minolta_naval(t->props, fielddefs, 13);
			}

		/* Exposure prog (scene capture type). */

		if ((tmpprop = findprop(t->props, fielddefs, 1)))
			if (tmpprop->value != 0)
				minolta_naval(t->props, fielddefs, 34);

		/* Interval mode (interval pics, time). */

		if ((tmpprop = findprop(t->props, fielddefs, 38)))
			if (tmpprop->value != 1) {
				minolta_naval(t->props, fielddefs, 16);
				minolta_naval(t->props, fielddefs, 17);
			}
	}
}


/*
 * Try to read a Minolta maker note IFD, which differs by model.
 */
struct ifd *
minolta_ifd(u_int32_t offset, struct tiffmeta *md)
{

	/* DiMAGE E201. */

	if (!strcmp((const char *)(md->btiff + offset), "+M")) {
		exifwarn("Minolta maker note version not supported");
		return (NULL);
	}

	/*
	 * Assume that if IFD num > 255 or < 2, this isn't a real IFD.
	 * Takes care of the unfortunate DiMAGE 2300 & EX.
	 */

	if (exif2byte(md->btiff + offset, md->order) > 0xff ||
	    exif2byte(md->btiff + offset, md->order) < 0x02) {
		exifwarn("Minolta maker note version not supported");
		return (NULL);
	}

	return (readifds(offset, minolta_tags, md));
}
