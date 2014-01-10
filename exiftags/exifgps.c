/*
 * Copyright (c) 2003-2005, Eric M. Johnston <emj@postal.net>
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
 * $Id: exifgps.c,v 1.14 2007/12/15 20:57:10 ejohnst Exp $
 */

/*
 * Exif GPS information tags.
 *
 * Note: things aren't quite complete.  Waiting on additional examples
 * that include the tags marked unknown.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "exif.h"
#include "exifint.h"

#define DEGREE "°"


/* Speed. */

static struct descrip gps_speed[] = {
	{ 'K',	"km/h" },
	{ 'M',	"mph" },
	{ 'N',	"knots" },
	{ -1,	"" },
};


/* Status. */

static struct descrip gps_status[] = {
	{ 'A',	"Measurement In Progress" },
	{ 'V',	"Measurement Interoperability" },
	{ -1,	"Unknown" },
};


/* Distance. */

static struct descrip gps_dist[] = {
	{ 'K',	"km" },
	{ 'M',	"mi" },
	{ 'N',	"knots" },
	{ -1,	"" },
};


/* Differential correction. */

static struct descrip gps_diff[] = {
	{ 0,	"No Correction" },
	{ 1,	"Correction Applied" },
	{ -1,	"Unknown" },
};


/* Bearing reference. */

static struct descrip gps_bear[] = {
	{ 'M',	"Magnetic North" },
	{ 'T',	"True North" },
	{ -1,	"Unknown" },
};


/* GPS info version 2.2.0.0 tags. */

struct exiftag gpstags[] = {
	{ 0x0000, TIFF_BYTE,  4,  ED_VRB,
	    "GPSVersionID", "GPS Info Version", NULL },
	{ 0x0001, TIFF_ASCII, 2,  ED_VRB,
	    "GPSLatitudeRef", "Latitude Reference", NULL },
	{ 0x0002, TIFF_RTNL,  3,  ED_IMG,
	    "GPSLatitude", "Latitude", NULL },
	{ 0x0003, TIFF_ASCII, 2,  ED_VRB,
	    "GPSLongitudeRef", "Longitude Reference", NULL },
	{ 0x0004, TIFF_RTNL,  3,  ED_IMG,
	    "GPSLongitude", "Longitude", NULL },
	{ 0x0005, TIFF_BYTE,  1,  ED_VRB,
	    "GPSAltitudeRef", "Altitude Reference", NULL },
	{ 0x0006, TIFF_RTNL,  1,  ED_IMG,		/* meters */
	    "GPSAltitude", "Altitude", NULL },
	{ 0x0007, TIFF_RTNL,  3,  ED_IMG,
	    "GPSTimeStamp", "Time (UTC)", NULL },
	{ 0x0008, TIFF_ASCII, 0,  ED_IMG,
	    "GPSSatellites", "GPS Satellites", NULL },
	{ 0x0009, TIFF_ASCII, 2,  ED_IMG,
	    "GPSStatus", "GPS Status", gps_status },
	{ 0x000a, TIFF_ASCII, 2,  ED_IMG,
	    "GPSMeasureMode", "GPS Measurement Mode", NULL },
	{ 0x000b, TIFF_RTNL,  1,  ED_UNK,
	    "GPSDOP", "GPS Degree of Precision", NULL },
	{ 0x000c, TIFF_ASCII, 2,  ED_VRB,
	    "GPSSpeedRef", "GPS Speed Reference", gps_speed },
	{ 0x000d, TIFF_RTNL,  1,  ED_UNK,
	    "GPSSpeed", "Movement Speed", NULL },
	{ 0x000e, TIFF_ASCII, 2,  ED_VRB,
	    "GPSTrackRef", "GPS Direction Reference", gps_bear },
	{ 0x000f, TIFF_RTNL,  1,  ED_UNK,		/* degrees */
	    "GPSTrack", "Movement Direction", NULL },
	{ 0x0010, TIFF_ASCII, 2,  ED_VRB,
	    "GPSImgDirectionRef", "GPS Image Direction Ref", gps_bear },
	{ 0x0011, TIFF_RTNL,  1,  ED_UNK,		/* degrees */
	    "GPSImgDirection",  "Image Direction", NULL },
	{ 0x0012, TIFF_ASCII, 0,  ED_IMG,
	    "GPSMapDatum", "Geodetic Survey Data", NULL },
	{ 0x0013, TIFF_ASCII, 2,  ED_VRB,
	    "GPSDestLatitudeRef", "GPS Dest Latitude Ref", NULL },
	{ 0x0014, TIFF_RTNL,  3,  ED_IMG,
	    "GPSDestLatitude", "Destination Latitude", NULL },
	{ 0x0015, TIFF_ASCII, 2,  ED_VRB,
	    "GPSDestLongitudeRef", "GPS Dest Longitude Ref", NULL },
	{ 0x0016, TIFF_RTNL,  3,  ED_IMG,
	    "GPSDestLongitude", "Destination Longitude", NULL },
	{ 0x0017, TIFF_ASCII, 2,  ED_VRB,
	    "GPSDestBearingRef", "GPS Dest Bearing Ref", gps_bear },
	{ 0x0018, TIFF_RTNL,  1,  ED_UNK,		/* degrees */
	    "GPSDestBearing", "Destination Direction", NULL },
	{ 0x0019, TIFF_ASCII, 2,  ED_VRB,
	    "GPSDestDistanceRef", "GPS Dest Distance Ref", gps_dist },
	{ 0x001a, TIFF_RTNL,  1,  ED_UNK,
	    "GPSDestDistance", "Destination Distance", NULL },
	{ 0x001b, TIFF_UNDEF, 0,  ED_IMG,
	    "GPSProcessingMethod", "GPS Processing Method", NULL },
	{ 0x001c, TIFF_UNDEF, 0,  ED_IMG,
	    "GPSAreaInformation", "GPS Area", NULL },
	{ 0x001d, TIFF_ASCII, 11, ED_IMG,
	    "GPSDateStamp", "Date (UTC)", NULL },
	{ 0x001e, TIFF_SHORT, 1,  ED_IMG,
	    "GPSDifferental", "GPS Differential Correction", gps_diff },
	{ 0xffff, TIFF_UNKN,  0,  ED_UNK,
	    "Unknown", NULL, NULL },
};


/*
 * Process GPS tags.
 */
void
gpsprop(struct exifprop *prop, struct exiftags *t)
{
	u_int32_t i, n, d;
	double deg, min, sec, alt;
	char fmt[32], buf[16];
	struct exifprop *tmpprop;
	enum byteorder o = t->md.order;

	switch (prop->tag) {

	/* Version. */

	case 0x0000:
		exifstralloc(&prop->str, 8);

		/* Convert the value back into a string. */

		byte4exif(prop->value, (unsigned char *)buf, o);

		for (i = 0; i < 4; i++) {
			prop->str[i * 2] = '0' + buf[i];
			prop->str[i * 2 + 1] = '.';
		}
		prop->str[7] = '\0';
		break;

	/*
	 * Reference values.  The value is 2-count nul-terminated ASCII,
	 * not an offset to the ASCII string.
	 * XXX Shouldn't really be necessary now that short ASCII strings work.
	 */

	case 0x0001:
	case 0x0003:
	case 0x0009:
	case 0x000a:
	case 0x000c:
	case 0x000e:
	case 0x0010:
	case 0x0013:
	case 0x0015:
	case 0x0017:
	case 0x0019:
		/* Clean-up from any earlier processing. */

		free(prop->str);
		prop->str = NULL;

		byte4exif(prop->value, (unsigned char *)buf, o);

		for (i = 0; gpstags[i].tag < EXIF_T_UNKNOWN &&
		    gpstags[i].tag != prop->tag; i++);
		if (gpstags[i].table)
			prop->str = finddescr(gpstags[i].table,
			    (unsigned char)buf[0]);
		else {
			exifstralloc(&prop->str, 2);
			prop->str[0] = buf[0];
		}
		break;

	/*
	 * Coordinate values.
	 *
	 * This is really kind of a mess.  The display behavior here is
	 * based on image samples from a Nikon D1X and a Fuji FinePix S1 Pro.
	 * The specification allows for fractional minutes (and no seconds).
	 * Not sure if there are any other combinations...
	 */

	case 0x0002:
	case 0x0004:
	case 0x0014:
	case 0x0016:
	 	if (prop->count != 3) {
			exifwarn("unexpected GPS coordinate values");
			prop->lvl = ED_BAD;
			break;
		}

		free(prop->str);
		prop->str = NULL;
		exifstralloc(&prop->str, 32);

		/* Figure out the reference prefix. */

		switch (prop->tag) {
		case 0x0002:
			tmpprop = findprop(t->props, gpstags, 0x0001);
			break;
		case 0x0004:
			tmpprop = findprop(t->props, gpstags, 0x0003);
			break;
		case 0x0014:
			tmpprop = findprop(t->props, gpstags, 0x0013);
			break;
		case 0x0016:
			tmpprop = findprop(t->props, gpstags, 0x0015);
			break;
		default:
			tmpprop = NULL;
		}

		/* Degrees. */

		i = 0;
		n = exif4byte(t->md.btiff + prop->value + i * 8, o);
		d = exif4byte(t->md.btiff + prop->value + 4 + i * 8, o);

		strcpy(fmt, "%s %.f%s ");
		if (!n || !d)			/* Punt. */
			deg = 0.0;
		else {
			deg = (double)n / (double)d;
			if (d != 1)
				sprintf(fmt, "%%s %%.%df%%s ",
				    (int)log10((double)d));
		}

		/* Minutes. */

		i++;
		n = exif4byte(t->md.btiff + prop->value + i * 8, o);
		d = exif4byte(t->md.btiff + prop->value + 4 + i * 8, o);

		if (!n || !d) {			/* Punt. */
			min = 0.0;
			strcat(fmt, "%.f'");
		} else {
			min = (double)n / (double)d;
			if (d != 1) {
				sprintf(buf, "%%.%df'", (int)log10((double)d));
				strcat(fmt, buf);
			} else
				strcat(fmt, "%.f'");
		}

		/*
		 * Seconds.  We'll assume if minutes are fractional, we
		 * should just ignore seconds.
		 */

		i++;
		n = exif4byte(t->md.btiff + prop->value + i * 8, o);
		d = exif4byte(t->md.btiff + prop->value + 4 + i * 8, o);

		if (!n || !d) {			/* Assume no seconds. */
			snprintf(prop->str, 31, fmt, tmpprop && tmpprop->str ?
			    tmpprop->str : "", deg, DEGREE, min);
			break;
		} else {
			sec = (double)n / (double)d;
			if (d != 1) {
				sprintf(buf, " %%.%df", (int)log10((double)d));
				strcat(fmt, buf);
			} else
				strcat(fmt, " %.f");
		}
		snprintf(prop->str, 31, fmt, tmpprop && tmpprop->str ?
		    tmpprop->str : "", deg, DEGREE, min, sec);
		break;

	/* Altitude. */

	case 0x0006:
		n = exif4byte(t->md.btiff + prop->value, o);
		d = exif4byte(t->md.btiff + prop->value + 4, o);

		/* Look up reference.  Non-zero means negative altitude. */

		tmpprop = findprop(t->props, gpstags, 0x0005);
		if (tmpprop && tmpprop->value)
			n *= -1;

		if (!n || !d)
			alt = 0.0;
		else
			alt = (double)n / (double)d;

		/* Should already have a 32-byte buffer from parsetag(). */

		snprintf(prop->str, 31, "%.2f m", alt);
		prop->str[31] = '\0';
		break;

	/* Time. */

	case 0x0007:
		/* Should already have a 32-byte buffer from parsetag(). */

		prop->str[0] = '\0';
		for (i = 0; i < prop->count; i++) {
			n = exif4byte(t->md.btiff + prop->value + i * 8, o);
			d = exif4byte(t->md.btiff + prop->value + 4 + i * 8, o);

			if (!d) break;

			if (!i)
				sprintf(fmt, "%%02.%df", (int)log10((double)d));
			else
				sprintf(fmt, ":%%02.%df",
				    (int)log10((double)d));

			snprintf(buf, 8, fmt, (double)n / (double)d);
			strcat(prop->str, buf);
		}
		break;
	}
}
