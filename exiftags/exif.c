/*
 * Copyright (c) 2001-2007, Eric M. Johnston <emj@postal.net>
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
 * $Id: exif.c,v 1.77 2007/12/16 00:25:08 ejohnst Exp $
 */

/*
 * Exchangeable image file format (Exif) parser.
 *
 * Developed using the TIFF 6.0 specification:
 * (http://partners.adobe.com/asn/developer/pdfs/tn/TIFF6.pdf)
 * and the EXIF 2.21 standard: (http://tsc.jeita.or.jp/avs/data/cp3451_1.pdf).
 *
 * Portions of this code were developed while referencing the public domain
 * 'Jhead' program (version 1.2) by Matthias Wandel <mwandel@rim.net>.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <math.h>
#include <float.h>
#include <ctype.h>

#include "exif.h"
#include "exifint.h"
#include "makers.h"

#define OLYMPUS_BUGS		/* Work around Olympus stupidity. */
#define WINXP_BUGS		/* Work around Windows XP stupidity. */
#define SIGMA_BUGS		/* Work around Sigma stupidity. */
#define UNCREDITED_BUGS		/* Work around uncredited stupidity. */


/* Function prototypes. */

static void parsetag(struct exifprop *prop, struct ifd *dir,
    struct exiftags *t, int domkr);


/*
 * Create an Exif property from the raw IFD field data.
 */
static void
readtag(struct field *afield, int ifdseq, struct ifd *dir, struct exiftags *t,
    int domkr)
{
	int i, j;
	struct exifprop *prop, *tmpprop;
	u_int16_t tag;

	prop = newprop();
	if (dir->par)
		tag = dir->par->tag;
	else
		tag = EXIF_T_UNKNOWN;

	/* Field info. */

	prop->tag = exif2byte(afield->tag, dir->md.order);
	prop->type = exif2byte(afield->type, dir->md.order);
	prop->count = exif4byte(afield->count, dir->md.order);
	/* XXX Makes dealing with two shorts somewhat messy. */
	if ((prop->type == TIFF_SHORT || prop->type == TIFF_SSHORT) &&
	    prop->count <= 1)
		prop->value = exif2byte(afield->value, dir->md.order);
	else
		prop->value = exif4byte(afield->value, dir->md.order);

	/* IFD identifying info. */

	prop->ifdseq = ifdseq;
	prop->par = dir->par;
	prop->tagset = dir->tagset;

	/* Lookup the field name. */

	for (i = 0; prop->tagset[i].tag < EXIF_T_UNKNOWN &&
	    prop->tagset[i].tag != prop->tag; i++);
	prop->name = prop->tagset[i].name;
	prop->descr = prop->tagset[i].descr;
	prop->lvl = prop->tagset[i].lvl;

	/*
	 * Lookup and check the field type.
	 *
	 * We have to be pretty severe with entries that have an invalid
	 * field type -- too many assumptions in the rest of the code.
	 */

	for (j = 0; ftypes[j].type && ftypes[j].type != prop->type; j++);
	if (!ftypes[j].type) {
		exifwarn2("unknown TIFF field type; discarding", prop->name);
		free(prop);
		return;
	}

	/* Skip sanity checking on maker note tags; we'll get to them later. */

	if (tag != EXIF_T_MAKERNOTE) {
		/*
		 * XXX Ignore UserComment -- a hack to get around an apparent
		 * WinXP Picture Viewer bug (err, liberty).  When you rotate
		 * a picture in the viewer, it modifies the IFD1 (thumbnail)
		 * tags to UserComment without changing the type appropriately.
		 * (At least we're able to ID invalid comments...)
		 */

		if (prop->tagset[i].type && prop->tagset[i].type !=
		    prop->type) {
#ifdef WINXP_BUGS
			if (prop->tag != EXIF_T_USERCOMMENT)
#endif
				exifwarn2("field type mismatch", prop->name);
			prop->lvl = ED_BAD;
		}

		/*
		 * Check the field count.
		 * XXX For whatever the reason, Sigma doesn't follow the
		 * spec on count for FileSource.
		 */

		if (prop->tagset[i].count && prop->tagset[i].count !=
#ifdef SIGMA_BUGS
		    prop->count && prop->tag != EXIF_T_FILESRC) {
#else
		    prop->count) {
#endif
			exifwarn2("field count mismatch", prop->name);

			/* Let's be forgiving with ASCII fields. */
			if (prop->type != TIFF_ASCII)
				prop->lvl = ED_BAD;
		}
	}

	/* Debuggage. */

	dumpprop(prop, afield);

	/*
	 * Do as much as we can with the tag at this point and add it
	 * to our list.
	 */

	parsetag(prop, dir, t, domkr);
	if ((tmpprop = t->props)) {
		while (tmpprop->next)
			tmpprop = tmpprop->next;
		tmpprop->next = prop;
	} else
		t->props = prop;
}


/*
 * Process the Exif tags for each field of an IFD.
 *
 * Note that this function is only called once per IFD.  Therefore, in order
 * to associate an IFD sequence number with the property, we keep track of
 * the count here.  Root IFDs (0 and 1) are processed first (along with any
 * other "root" IFDs we find), then any nested IFDs in the order they're
 * encountered.
 */
static void
readtags(struct ifd *dir, int seq, struct exiftags *t, int domkr)
{
	int i;

	if (debug) {
		/* XXX Byte order info can be off for maker notes. */
		if (dir->par && dir->par->tag != EXIF_T_UNKNOWN) {
			printf("Processing %s directory, %d entries, "
			    "%s-endian\n",
			    dir->par->name, dir->num, dir->md.order == BIG ?
			    "big" : "little");
		} else
			printf("Processing directory %d, %d entries, "
			    "%s-endian\n",
			    seq, dir->num, dir->md.order == BIG ? "big" :
			    "little");
	}

	for (i = 0; i < dir->num; i++)
		readtag(&(dir->fields[i]), seq, dir, t, domkr);

	if (debug)
		printf("\n");
}


/*
 * Post-process property values.  By now we've got all of the standard
 * Exif tags read in (but not maker tags), so it's safe to work out
 * dependencies between tags.
 *
 * XXX At this point, we've lost IFD-level TIFF metadata.  Therefore,
 * assumptions about byte order and beginning of the TIFF might be false.
 */
static void
postprop(struct exifprop *prop, struct exiftags *t)
{
	struct exifprop *tmpprop;
	u_int16_t v;
	u_int32_t val;
	float fval;
	enum byteorder o = t->md.order;
	struct exifprop *h = t->props;

	/* Skip bad properties. */

	if (prop->lvl == ED_BAD)
		return;

	/*
	 * Process tags from special IFDs.
	 */

	if (prop->par && prop->par->tagset == tags) {
		switch (prop->par->tag) {

		case EXIF_T_MAKERNOTE:
			if (makers[t->mkrval].propfun) {
				makers[t->mkrval].propfun(prop, t);
				return;
			}
			break;

		case EXIF_T_GPSIFD:
			gpsprop(prop, t);
			return;
		}
	}

	/* Process normal tags. */

	if (prop->tagset != tags)
		return;

	switch (prop->tag) {

	case EXIF_T_XRES:
	case EXIF_T_YRES:
	case EXIF_T_FPXRES:
	case EXIF_T_FPYRES:
		if (prop->tag == EXIF_T_XRES || prop->tag == EXIF_T_YRES) {
			if (!(tmpprop = findprop(h, tags, EXIF_T_RESUNITS)))
				break;
		} else {
			if (!(tmpprop = findprop(h, tags, EXIF_T_FPRESUNITS)))
				break;
		}
		val = exif4byte(t->md.btiff + prop->value, o) /
		    exif4byte(t->md.btiff + prop->value + 4, o);
		snprintf(prop->str, 31, "%d dp%s", val, tmpprop->str);
		prop->str[31] = '\0';
		break;

	/*
	 * Shutter speed doesn't seem all that useful.  It's usually the
	 * same as exposure time and when it's not, it's wrong.
	 * Exposure time overrides it.
	 */

	case EXIF_T_SHUTTER:
		fval = (float)exif4sbyte(t->md.btiff + prop->value, o) /
		    (float)exif4sbyte(t->md.btiff + prop->value + 4, o);
		if (isnan(fval)) fval = 0;
		/* 1 / (2^speed) */
		snprintf(prop->str, 31, "1/%d",
		    (int)floor(pow(2, (double)fval) + 0.5));
		prop->str[31] = '\0';
		/* FALLTHROUGH */

	case EXIF_T_EXPOSURE:
		if (strlen(prop->str) > 27) break;
		strcat(prop->str, " sec");
		if (prop->tag == EXIF_T_EXPOSURE)
			prop->override = EXIF_T_SHUTTER;
		break;

	case EXIF_T_FNUMBER:
		fval = (float)exif4byte(t->md.btiff + prop->value, o) /
		    (float)exif4byte(t->md.btiff + prop->value + 4, o);
		if (isnan(fval)) fval = 0;
		snprintf(prop->str, 31, "f/%.1f", fval);
		prop->str[31] = '\0';
		break;

	case EXIF_T_LAPERTURE:
	case EXIF_T_MAXAPERTURE:
		fval = (float)exif4byte(t->md.btiff + prop->value, o) /
		    (float)exif4byte(t->md.btiff + prop->value + 4, o);
		if (isnan(fval)) fval = 0;
		/* sqrt(2)^aperture */
		snprintf(prop->str, 31, "f/%.1f", pow(1.4142, (double)fval));
		prop->str[31] = '\0';
		break;

	case EXIF_T_BRIGHTVAL:
		if (exif4byte(t->md.btiff + prop->value, o) == 0xffffffff) {
			strcpy(prop->str, "Unknown");
			break;
		}
		/* FALLTHROUGH */

	case EXIF_T_EXPBIASVAL:
		if (strlen(prop->str) > 28) break;
		strcat(prop->str, " EV");
		break;

	case EXIF_T_DISTANCE:
		if (exif4byte(t->md.btiff + prop->value, o) == 0xffffffff) {
			strcpy(prop->str, "Infinity");
			break;
		}
		if (exif4byte(t->md.btiff + prop->value + 4, o) == 0) {
			strcpy(prop->str, "Unknown");
			break;
		}
		fval = (float)exif4byte(t->md.btiff + prop->value, o) /
		    (float)exif4byte(t->md.btiff + prop->value + 4, o);
		if (isnan(fval)) fval = 0;
		snprintf(prop->str, 31, "%.2f m", fval);
		prop->str[31] = '\0';
		break;

	/* Flash consists of a number of bits, which expanded with v2.2. */

#define LFLSH 96

	case EXIF_T_FLASH:
		if (t->exifmaj <= 2 && t->exifmin < 20)
			v = (u_int16_t)(prop->value & 0x7);
		else
			v = (u_int16_t)(prop->value & 0x7F);

		exifstralloc(&prop->str, LFLSH);

		/* Don't do anything else if there isn't a flash. */

		if (catdescr(prop->str, flash_func, (u_int16_t)(v & 0x20),
		    LFLSH))
			break;

		catdescr(prop->str, flash_fire, (u_int16_t)(v & 0x01), LFLSH);
		catdescr(prop->str, flash_mode, (u_int16_t)(v & 0x18), LFLSH);
		catdescr(prop->str, flash_redeye, (u_int16_t)(v & 0x40), LFLSH);
		catdescr(prop->str, flash_return, (u_int16_t)(v & 0x06), LFLSH);
		break;

	case EXIF_T_FOCALLEN:
		fval = (float)exif4byte(t->md.btiff + prop->value, o) /
		    (float)exif4byte(t->md.btiff + prop->value + 4, o);
		if (isnan(fval)) fval = 0;
		snprintf(prop->str, 31, "%.2f mm", fval);
		prop->str[31] = '\0';
		break;

	/* Digital zoom: set to verbose if numerator is 0 or fraction = 1. */

	case EXIF_T_DIGIZOOM:
		if (!exif4byte(t->md.btiff + prop->value, o))
			strcpy(prop->str, "Unused");
		else if (exif4byte(t->md.btiff + prop->value, o) !=
		    exif4byte(t->md.btiff + prop->value + 4, o))
			break;
		prop->lvl = ED_VRB;
		break;

	case EXIF_T_FOCALLEN35:
		exifstralloc(&prop->str, 16);
		snprintf(prop->str, 15, "%d mm", prop->value);
		break;

	/*
	 * XXX This really should be in parsetag() to guarantee that it's
	 * done before we process the maker notes.  However, I haven't seen
	 * model not come first, so it should be safe (and more convenient).
	 */

	case EXIF_T_MODEL:
		t->model = prop->str;
		break;
	}
}


/*
 * This gives us an opportunity to change the dump level based on
 * property values after all properties are established.
 */
static void
tweaklvl(struct exifprop *prop, struct exiftags *t)
{
	char *c;
	struct exifprop *tmpprop;

	/* Change any ASCII properties to verbose if they're empty. */

	if (prop->type == TIFF_ASCII &&
	    (prop->lvl & (ED_CAM | ED_IMG | ED_PAS))) {
		c = prop->str;
		while (c && *c && (isspace((int)*c) ||
		    (unsigned char)*c < ' ')) c++;
		if (!c || !*c)
			prop->lvl = ED_VRB;
	}

	/*
	 * Don't let unprintable characters slip through -- we'll just replace
	 * them with '_'.  (Can see this with some corrupt maker notes.)
	 * Remove trailing whitespace while we're at it.
	 */

	if (prop->str && prop->type == TIFF_ASCII) {
		c = prop->str;
		while (*c) {
			/* Catch those pesky chars > 127. */
			if ((unsigned char)*c < ' ')
				*c = '_';
			c++;
		}

		c = prop->str + strlen(prop->str);
		while (c > prop->str && isspace((int)*(c - 1))) --c;
		*c = '\0';
	}

	/*
	 * IFD1 refers to the thumbnail image; we don't really care.
	 * It seems that some images might not have an IFD1 (does FinePix
	 * Viewer strip it?), so make sure that the property doesn't have
	 * a parent association.
	 */

	if (prop->ifdseq == 1 && !prop->par && prop->lvl != ED_UNK)
		prop->lvl = ED_VRB;

	/* Maker tags can override normal Exif tags. */

	if (prop->override && (tmpprop = findprop(t->props, tags,
	    prop->override)))
		if (tmpprop->lvl & (ED_CAM | ED_IMG | ED_PAS))
			tmpprop->lvl = ED_OVR;
}


/*
 * Fetch the data for an Exif tag.
 */
static void
parsetag(struct exifprop *prop, struct ifd *dir, struct exiftags *t, int domkr)
{
	unsigned int i, len;
	u_int16_t v = (u_int16_t)prop->value;
	u_int32_t un, ud, denom;
	int32_t sn, sd;
	char buf[32], *c, *d;
	struct tiffmeta *md;
	unsigned char *btiff = dir->md.btiff;
	enum byteorder o = dir->md.order;

	/* If the tag's already marked as bad, no sense in continuing. */

	if (prop->lvl == ED_BAD)
		return;

	/* Set description if we have a lookup table. */

	for (i = 0; prop->tagset[i].tag < EXIF_T_UNKNOWN &&
	    prop->tagset[i].tag != prop->tag; i++);
	if (prop->tagset[i].table) {
		prop->str = finddescr(prop->tagset[i].table, v);
		return;
	}

	/* XXX Probably shouldn't process this switch for non-standard tags. */

	switch (prop->tag) {

	/* Process an Exif IFD. */

	case EXIF_T_EXIFIFD:
	case EXIF_T_GPSIFD:
	case EXIF_T_INTEROP:
		md = &dir->md;
		while (dir->next)
			dir = dir->next;

		/*
		 * XXX Olympus cameras don't seem to include a proper offset
		 * at the end of the ExifOffset IFD, so just read one IFD.
		 * Hopefully this won't cause us to miss anything...
		 */
#ifdef OLYMPUS_BUGS
		if (prop->tag == EXIF_T_EXIFIFD)
			readifd(prop->value, &dir->next, tags, md);
		else
#endif
			if (prop->tag == EXIF_T_GPSIFD) {
				dir->next = readifds(prop->value, gpstags, md);
			} else {
				dir->next = readifds(prop->value, tags, md);
			}

		if (!dir->next) {

			/*
			 * XXX Ignore the case where interoperability offset
			 * is invalid.  This appears to be the case with some
			 * Olympus cameras, and we don't want to abort things
			 * things on an IFD we don't really care about anyway.
			 */
#ifdef OLYMPUS_BUGS
			if (prop->tag == EXIF_T_INTEROP)
				break;
#endif
			exifwarn2("invalid Exif format: IFD length mismatch",
			    prop->name);
			break;
		}

		/* XXX Doesn't catch multiple IFDs. */
		dir->next->par = prop;
		return;

	/* Record the Exif version. */

	case EXIF_T_VERSION:
		byte4exif(prop->value, (unsigned char *)buf, o);
		buf[4] = '\0';
		t->exifmin = (short)atoi(buf + 2);
		buf[2] = '\0';
		t->exifmaj = (short)atoi(buf);

		exifstralloc(&prop->str, 8);
		snprintf(prop->str, 7, "%d.%02d", t->exifmaj, t->exifmin);
		break;

	/* Process a maker note. */

	case EXIF_T_MAKERNOTE:
		if (!domkr)
			return;

		/* Maker function can change metadata if necessary. */

		t->mkrmd = dir->md;
		md = &t->mkrmd;
		while (dir->next)
			dir = dir->next;

		/*
		 * Try to process maker note IFDs using the function
		 * specified for the maker.
		 *
		 * XXX Note that for this to work right, we have to see
		 * the manufacturer tag first to figure out makerifd().
		 */

		if (makers[t->mkrval].ifdfun) {
			if (!offsanity(prop, 1, dir))
				dir->next =
				    makers[t->mkrval].ifdfun(prop->value, md);
		} else
			exifwarn("maker note not supported");

		if (!dir->next)
			break;

		/* XXX Doesn't catch multiple IFDs. */
		dir->next->par = prop;
		return;

	/* Lookup functions for maker note. */

	case EXIF_T_EQUIPMAKE:

		/* Sanity check the offset. */

		if (offsanity(prop, 1, dir))
			return;

		strncpy(buf, (const char *)(btiff + prop->value), sizeof(buf));
		buf[sizeof(buf) - 1] = '\0';
		for (c = buf; *c; c++) *c = tolower(*c);

		for (i = 0; makers[i].val != EXIF_MKR_UNKNOWN; i++)
			if (!strncmp(buf, makers[i].name,
			    strlen(makers[i].name)))
				break;
		t->mkrval = (short)i;

		/* Keep processing (ASCII value). */
		break;

	/*
	 * Handle user comment.  According to the spec, the first 8 bytes
	 * of the comment indicate what charset follows.  For now, we
	 * just support ASCII.
	 *
	 * XXX A handful of the GPS tags are also stored in this format.
	 */

	case 0x001b:	/* GPSProcessingMethod */
	case 0x001c:	/* GPSAreaInformation */
		/*
		 * XXX Note that this is kind of dangerous -- any other
		 * tag set won't reach the end of the switch...
		 */
		if (prop->tagset != gpstags)
			break;
		/* FALLTHROUGH */

	case EXIF_T_USERCOMMENT:

		/* Check for a comment type and sane offset. */

		if (prop->count < 8) {
			exifwarn("invalid user comment length");
			prop->lvl = ED_BAD;
			return;
		}

		if (offsanity(prop, 1, dir))
			return;

		/* Ignore the 'comments' WinXP creates when rotating. */
#ifdef WINXP_BUGS
		for (i = 0; tags[i].tag < EXIF_T_UNKNOWN &&
		    tags[i].tag != EXIF_T_USERCOMMENT; i++);
		if (tags[i].type && tags[i].type != prop->type)
			break;
#endif
		/* Lookup the comment type. */

		for (i = 0; ucomment[i].descr; i++)
			if (!memcmp(ucomment[i].descr, btiff + prop->value, 8))
				break;

		/* Handle an ASCII comment; strip any trailing whitespace. */

		if (ucomment[i].val == TIFF_ASCII) {
			c = (char *)(btiff + prop->value + 8);
			d = strlen(c) < prop->count - 8 ? c + strlen(c) :
			    c + prop->count - 8;

			while (d > c && isspace((int)*(d - 1))) --d;

			exifstralloc(&prop->str, d - c + 1);
			strncpy(prop->str, c, d - c);
			prop->lvl = prop->str[0] ? ED_IMG : ED_VRB;
			return;
		}
		break;

	case EXIF_T_FILESRC:
		/*
		 * This 'undefined' field is one byte; runs afoul of XP
		 * not zeroing out stuff.
		 */
#ifdef WINXP_BUGS
		prop->str = finddescr(filesrcs, (u_int16_t)(v & 0xFFU));
#else
		prop->str = finddescr(filesrcs, v);
#endif
		return;
	}

	/*
	 * ASCII types.
	 */

	if (prop->type == TIFF_ASCII) {
		/* Should fit in the value field. */
		if (prop->count < 5) {
			exifstralloc(&prop->str, 5);
			byte4exif(prop->value, (unsigned char *)prop->str, o);
			return;
		}

		/* Sanity check the offset. */
		if (!offsanity(prop, 1, dir)) {
			exifstralloc(&prop->str, prop->count + 1);
			strncpy(prop->str, (const char *)(btiff + prop->value),
			    prop->count);
		}
		return;
	}

	/*
	 * Rational types.  (Note that we'll redo some in our later pass.)
	 * We'll reduce and simplify the fraction.
	 *
	 * XXX Misses multiple rationals.
	 */

	if ((prop->type == TIFF_RTNL || prop->type == TIFF_SRTNL) &&
	    !offsanity(prop, 8, dir)) {

		exifstralloc(&prop->str, 32);

		if (prop->type == TIFF_RTNL) {
			un = exif4byte(btiff + prop->value, o);
			ud = exif4byte(btiff + prop->value + 4, o);
			denom = gcd(un, ud);
// fixfract macro calls abs, which is not necessary for this line since un, id, denom are all unsigned
#define abs
			fixfract(prop->str, un, ud, denom);
#undef abs
		} else {
			sn = exif4sbyte(btiff + prop->value, o);
			sd = exif4sbyte(btiff + prop->value + 4, o);
			denom = gcd(abs(sn), abs(sd));
			fixfract(prop->str, sn, sd, (int32_t)denom);
		}
		return;
	}

	/*
	 * Multiple short values.
	 * XXX For now, we're going to ignore tags with count > 8.  Maker
	 * note tags frequently consist of many shorts; we don't really
	 * want to be spitting these out.  (Plus, TransferFunction is huge.)
	 *
	 * XXX Note that this doesn't apply to two shorts, which are
	 * stuffed into the value.
	 */

	if ((prop->type == TIFF_SHORT || prop->type == TIFF_SSHORT) &&
	    prop->count > 2 && !offsanity(prop, 2, dir)) {

		if (prop->count > 8)
			return;
		len = 8 * prop->count + 1;
		exifstralloc(&prop->str, len);

		for (i = 0; i < prop->count; i++) {
			if (prop->type == TIFF_SHORT)
				snprintf(prop->str + strlen(prop->str),
				    len - strlen(prop->str) - 1, "%d, ",
				    exif2byte(btiff + prop->value +
				    (i * 2), o));
			else
				snprintf(prop->str + strlen(prop->str),
				    len - strlen(prop->str) - 1, "%d, ",
				    exif2sbyte(btiff + prop->value +
				    (i * 2), o));
		}
		prop->str[strlen(prop->str) - 2] = '\0';
		return;
	}
	return;
}


/*
 * Delete dynamic Exif property and IFD memory.
 */
void
exiffree(struct exiftags *t)
{
	struct exifprop *tmpprop;
	struct ifdoff *tmpoff;

	if (!t) return;

	while ((tmpprop = t->props)) {
		if (t->props->str) free(t->props->str);
		t->props = t->props->next;
		free(tmpprop);
	}
	while ((tmpoff = (struct ifdoff *)(t->md.ifdoffs))) {
		t->md.ifdoffs = (void *)tmpoff->next;
		free(tmpoff);
	}
	free(t);
}


/*
 * Scan the Exif section.
 */
struct exiftags *
exifscan(unsigned char *b, int len, int domkr)
{
	int seq;
	u_int32_t ifdoff;
	struct exiftags *t;
	struct ifd *curifd, *tmpifd;

	/* Create and initialize our file info structure. */

	t = (struct exiftags *)malloc(sizeof(struct exiftags));
	if (!t) {
		exifwarn2("can't allocate file info",
		    (const char *)strerror(errno));
		return (NULL);
	}
	memset(t, 0, sizeof(struct exiftags));

	seq = 0;
	t->md.etiff = b + len;	/* End of TIFF. */

	/*
	 * Make sure we've got the proper Exif header.  If not, we're
	 * looking at somebody else's APP1 (e.g., Photoshop).
	 */

	if (memcmp(b, "Exif\0\0", 6)) {
		exiffree(t);
		return (NULL);
	}
	b += 6;

	/* Determine endianness of the TIFF data. */

	if (!memcmp(b, "MM", 2))
		t->md.order = BIG;
	else if (!memcmp(b, "II", 2))
		t->md.order = LITTLE;
	else {
		exifwarn("invalid TIFF header");
		exiffree(t);
		return (NULL);
	}

	t->md.btiff = b;	/* Beginning of TIFF. */
	b += 2;

	/* Verify the TIFF header. */

	if (exif2byte(b, t->md.order) != 42) {
		exifwarn("invalid TIFF header");
		exiffree(t);
		return (NULL);
	}
	b += 2;

	/* Get the 0th IFD, where all of the good stuff should start. */

	ifdoff = exif4byte(b, t->md.order);
	curifd = readifds(ifdoff, tags, &t->md);
	if (!curifd) {
		exifwarn("invalid Exif format (couldn't read IFD0)");
		exiffree(t);
		return (NULL);
	}

	/* Now, let's parse the fields... */

	while ((tmpifd = curifd)) {
		readtags(curifd, seq++, t, domkr);
		curifd = curifd->next;
		free(tmpifd);		/* No need to keep it around... */
	}

	return (t);
}


/*
 * Read the Exif section and prepare the data for output.
 */
struct exiftags *
exifparse(unsigned char *b, int len)
{
	struct exiftags *t;
	struct exifprop *curprop;

	/* Find the section and scan it. */

	if (!(t = exifscan(b, len, TRUE)))
		return (NULL);

	/* Make field values pretty. */

	curprop = t->props;
	while (curprop) {
		postprop(curprop, t);
		tweaklvl(curprop, t);
		curprop = curprop->next;
	}

	return (t);
}
