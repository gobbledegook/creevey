/*
 * Copyright (c) 2003, Eric M. Johnston <emj@postal.net>
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
 * $Id: sanyo.c,v 1.4 2004/12/23 20:38:52 ejohnst Exp $
 */

/*
 * Exif tag definitions for Sanyo maker notes.
 * Developed from http://www.exif.org/makernotes/SanyoMakerNote.html.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "makers.h"


/* Macro mode. */

static struct descrip sanyo_macro[] = {
	{ 0,	"Normal" },
	{ 1,	"Macro" },
	{ -1,	"Unknown" },
};


/* Quality. */

static struct descrip sanyo_quality[] = {
	{ 0,	"Normal" },
	{ 1,	"Fine" },
	{ 2,	"Superfine" },
	{ -1,	"Unknown" },
};


/* Resolution. */

static struct descrip sanyo_res[] = {
	{ 0,	"Very Low Resolution" },
	{ 1,	"Low Resolution" },
	{ 2,	"Medium Low Resolution" },
	{ 3,	"Medium Resolution" },
	{ 4,	"Medium High Resolution" },
	{ 5,	"High Resolution" },
	{ 6,	"Very High Resolution" },
	{ 7,	"Super High Resolution" },
	{ -1,	"Unknown Resolution" },
};


/* Sequential shot method. */

static struct descrip sanyo_seqshot[] = {
	{ 0,	"None" },
	{ 1,	"Standard" },
	{ 2,	"Best" },
	{ 3,	"Adjust Exposure" },
	{ -1,	"Unknown" },
};


/* Boolean value. */

static struct descrip sanyo_offon[] = {
	{ 0,	"Off" },
	{ 1,	"On" },
	{ -1,	"Unknown" },
};


/* Record shutter release. */

static struct descrip sanyo_shutter[] = {
	{ 0,	"Record While Held" },
	{ 1,	"Press to Start, Stop" },
	{ -1,	"Unknown" },
};


/* Enabled/disabled value. */

static struct descrip sanyo_toggle[] = {
	{ 0,	"Disabled" },
	{ 1,	"Enabled" },
	{ -1,	"Unknown" },
};


/* Yes/no value. */

static struct descrip sanyo_noyes[] = {
	{ 0,	"No" },
	{ 1,	"Yes" },
	{ -1,	"Unknown" },
};


/* Scene selection. */

static struct descrip sanyo_scene[] = {
	{ 0,	"Off" },
	{ 1,	"Sport" },
	{ 2,	"TV" },
	{ 3,	"Night" },
	{ 4,	"User 1" },
	{ 5,	"User 2" },
	{ -1,	"Unknown" },
};


/* Sequential shot interval. */

static struct descrip sanyo_interval[] = {
	{ 0,	"5 frames/sec" },
	{ 1,	"10 frames/sec" },
	{ 2,	"15 frames/sec" },
	{ 3,	"20 frames/sec" },
	{ -1,	"Unknown" },
};


/* Flash mode. */

static struct descrip sanyo_flash[] = {
	{ 0,	"Auto" },
	{ 1,	"Force" },
	{ 2,	"Disabled" },
	{ 3,	"Red-Eye" },
	{ -1,	"Unknown" },
};


/* Maker note IFD tags. */

static struct exiftag sanyo_tags[] = {
	{ 0x0100, TIFF_UNKN, 0, ED_UNK, "SanyoThumb",
	  "JPEG Thumbnail", NULL },
	{ 0x0200, TIFF_LONG, 3, ED_VRB, "SanyoShootMode",
	  "Shooting Mode", NULL },
	{ 0x0201, TIFF_SHORT, 1, ED_IMG, "SanyoQuality",
	  "Quality Setting", NULL },
	{ 0x0202, TIFF_SHORT, 1, ED_IMG, "SanyoMacroMode",
	  "Macro Mode", sanyo_macro },
	{ 0x0204, TIFF_RTNL, 1, ED_IMG, "SanyoDigiZoom",
	  "Digital Zoom", NULL },
	{ 0x0207, TIFF_ASCII, 5, ED_IMG, "SanyoFirmware",
	  "Firmware Version", NULL },
	{ 0x0208, TIFF_ASCII, 52, ED_IMG, "SanyoPicInfo",
	  "Picture Info", NULL },
	{ 0x0209, TIFF_UNKN, 32, ED_UNK, "SanyoCameraID",
	  "Camera ID", NULL },
	{ 0x020e, TIFF_SHORT, 1, ED_IMG, "SanyoSeqShot",
	  "Sequential Shot Method", sanyo_seqshot },
	{ 0x020f, TIFF_SHORT, 1, ED_IMG, "SanyoWideRange",
	  "Wide Range", sanyo_offon },
	{ 0x0210, TIFF_SHORT, 1, ED_IMG, "SanyoColorAdjust",
	  "Color Adjustment", NULL },
	{ 0x0213, TIFF_SHORT, 1, ED_IMG, "SanyoQuickShot",
	  "Quick Shot", sanyo_offon },
	{ 0x0214, TIFF_SHORT, 1, ED_IMG, "SanyoSelfTime",
	  "Self Timer", sanyo_offon },
	{ 0x0216, TIFF_SHORT, 1, ED_IMG, "SanyoVoiceMemo",
	  "Voice Memo", sanyo_offon },
	{ 0x0217, TIFF_SHORT, 1, ED_IMG, "SanyoRecShutter",
	  "Record Shutter Release", sanyo_shutter },
	{ 0x0218, TIFF_SHORT, 1, ED_IMG, "SanyoFlicker",
	  "Flicker Reduce", sanyo_offon },
	{ 0x0219, TIFF_SHORT, 1, ED_IMG, "SanyoOpticalZoom",
	  "Optical Zoom", sanyo_toggle },
	{ 0x021b, TIFF_SHORT, 1, ED_IMG, "SanyoDigiZoom",
	  "Digital Zoom", sanyo_toggle },
	{ 0x021d, TIFF_SHORT, 1, ED_IMG, "SanyoLightSrc",
	  "Special Light Source", sanyo_offon },
	{ 0x021e, TIFF_SHORT, 1, ED_IMG, "SanyoResaved",
	  "Image Re-saved", sanyo_noyes },
	{ 0x021f, TIFF_SHORT, 1, ED_IMG, "SanyoScene",
	  "Scene Selection", sanyo_scene },
	{ 0x0223, TIFF_SHORT, 1, ED_IMG, "SanyoFocalDist",
	  "Focal Distance", NULL },
	{ 0x0224, TIFF_SHORT, 1, ED_IMG, "SanyoSeqInterval",
	  "Sequential Shot Interval", sanyo_interval },
	{ 0x0225, TIFF_SHORT, 1, ED_IMG, "SanyoFlash",
	  "Flash Mode", sanyo_flash },
	{ 0x0e00, TIFF_UNKN, 0, ED_UNK, "SanyoPrintIM",
	  "Print IM Flags", NULL },
	{ 0x0f00, TIFF_UNKN, 0, ED_UNK, "SanyoDump",
	  "Data Dump", NULL },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "SanyoUnknown",
	  "Sanyo Unknown", NULL },
};


/* Picture mode. */

static struct descrip sanyo_picmode[] = {
	{ 0,	"Normal" },
	{ 2,	"Fast" },
	{ 3,	"Panorama" },
	{ -1,	"Unknown" },
};


/* Panoramic direction. */

static struct descrip sanyo_pandir[] = {
	{ 1,	"Left to Right" },
	{ 2,	"Right to Left" },
	{ 3,	"Bottom to Top" },
	{ 4,	"Top to Bottom" },
	{ -1,	"Unknown" },
};


/* Shooting mode subtags. */

static struct exiftag sanyo_shoottags[] = {
	{ 0x0000, TIFF_UNKN, 0, ED_IMG, "SanyoPicMode",
	  "Picture Mode", sanyo_picmode },
	{ 0x0001, TIFF_UNKN, 0, ED_IMG, "SanyoSeqNum",
	  "Sequence Number", NULL },
	{ 0x0002, TIFF_UNKN, 0, ED_IMG, "SanyoPanDir",
	  "Panoramic Direction", sanyo_pandir },
	{ 0xffff, TIFF_UNKN, 0, ED_UNK, "SanyoShootUnknown",
	  "Sanyo Shooting Unknown", NULL },
};


/*
 * Process Sanyo maker note tags.
 */
void
sanyo_prop(struct exifprop *prop, struct exiftags *t)
{
	int i, j;
	u_int32_t a, b;
	char *c1, *c2;
	struct exifprop *aprop;

	switch (prop->tag) {

	/* Various image data. */

	case 0x0200:
		if (debug)
			printf("Processing %s (0x%04X) directory, %d entries\n",
			    prop->name, prop->tag, prop->count);

		for (i = 0; i < (int)prop->count; i++) {
			a = exif4byte(t->mkrmd.btiff + prop->value + i * 2,
			    t->mkrmd.order);

			aprop = childprop(prop);
			aprop->value = a;
			aprop->tag = i;
			aprop->tagset = sanyo_shoottags;
			aprop->type = prop->type;
			aprop->count = 1;

			/* Lookup property name and description. */

			for (j = 0; sanyo_shoottags[j].tag < EXIF_T_UNKNOWN &&
			    sanyo_shoottags[j].tag != i; j++);
			aprop->name = sanyo_shoottags[j].name;
			aprop->descr = sanyo_shoottags[j].descr;
			aprop->lvl = sanyo_shoottags[j].lvl;
			if (sanyo_shoottags[j].table)
				aprop->str =
				    finddescr(sanyo_shoottags[j].table,
				    (u_int16_t)a);

			switch (aprop->tag) {
			case 0x0001:
				if (!aprop->value)
					aprop->lvl = ED_VRB;
				aprop->value += 1;
				break;
			}

			dumpprop(aprop, NULL);
		}
		break;

	/* Image quality & resolution. */

	case 0x0201:
		c1 = finddescr(sanyo_quality,
		    (u_int16_t)((prop->value >> 8) & 0xff));
		c2 = finddescr(sanyo_res, (u_int16_t)(prop->value & 0xff));
		exifstralloc(&prop->str, strlen(c1) + strlen(c2) + 3);
		sprintf(prop->str, "%s, %s", c1, c2);
		free(c1);
		free(c2);
		break;

	/* Digital zoom. */

	case 0x0204:
		a = exif4byte(t->mkrmd.btiff + prop->value, t->mkrmd.order);
		b = exif4byte(t->mkrmd.btiff + prop->value + 4, t->mkrmd.order);

		if (!a || !b || a == b)
			snprintf(prop->str, 31, "None");
		else
			snprintf(prop->str, 31, "x%.1f", (float)a / (float)b);
		break;

	/* Color adjust. */

	case 0x0210:
		prop->str = finddescr(sanyo_offon, (u_int16_t)(!!prop->value));
		break;
	}
}


/*
 * Try to read a Sanyo maker note IFD.
 */
struct ifd *
sanyo_ifd(u_int32_t offset, struct tiffmeta *md)
{
	struct ifd *myifd;

	/*
	 * Seems that Sanyo maker notes start with an ID string.  Therefore,
	 * try reading the IFD starting at offset + 8 ("SANYO" + 3).
	 */

	if (!strcmp((const char *)(md->btiff + offset), "SANYO"))
		readifd(offset + strlen("SANYO") + 3, &myifd, sanyo_tags, md);
	else
		readifd(offset, &myifd, sanyo_tags, md);

	return (myifd);
}
