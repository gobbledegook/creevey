/*
 * Copyright (c) 2002-2004, Eric M. Johnston <emj@postal.net>
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
 * $Id: makers.c,v 1.11 2004/09/15 23:35:55 ejohnst Exp $
 */

/*
 * Maker note lookup table.  Use makers_stub.c if you don't need
 * maker note modules linked in.
 */

#include <stdlib.h>

#include "makers.h"


struct makerfun makers[] = {
	{ 0, "unknown", NULL, NULL },		/* default value */
	{ EXIF_MKR_CANON, "canon", canon_prop, canon_ifd },
	{ EXIF_MKR_OLYMPUS, "olympus", olympus_prop, olympus_ifd },
	{ EXIF_MKR_FUJI, "fujifilm", fuji_prop, fuji_ifd },
	{ EXIF_MKR_NIKON, "nikon", nikon_prop, nikon_ifd },
	{ EXIF_MKR_CASIO, "casio", NULL, casio_ifd },
	{ EXIF_MKR_MINOLTA, "minolta", minolta_prop, minolta_ifd },
	{ EXIF_MKR_SANYO, "sanyo", sanyo_prop, sanyo_ifd },
	{ EXIF_MKR_ASAHI, "asahi", asahi_prop, asahi_ifd },
	{ EXIF_MKR_PENTAX, "pentax", asahi_prop, asahi_ifd },
	{ EXIF_MKR_LEICA, "leica", leica_prop, leica_ifd },
	{ EXIF_MKR_PANASONIC, "panasonic", panasonic_prop, panasonic_ifd },
	{ EXIF_MKR_SIGMA, "sigma", sigma_prop, sigma_ifd },
	{ EXIF_MKR_UNKNOWN, "unknown", NULL, NULL },
};
