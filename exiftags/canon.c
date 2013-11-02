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
 * $Id: canon.c,v 1.54 2007/12/16 03:06:13 ejohnst Exp $
 */

/*
 * Exif tag definitions for Canon maker notes.
 * Developed from http://www.burren.cx/david/canon.html.
 * EOS 1D and 1Ds contributions from Stan Jirman <stanj@phototrek.org>.
 * EOS 10D contributions from Jason Montojo <jason.montojo@rogers.com>.
 * EOS 20D contributions from Per Kristian Hove <Per.Hove@math.ntnu.no>.
 * EOS 5D contributions from Albert Max Lai <amlai@columbia.edu>.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "makers.h"


/*
 * Calculate and format an exposure value ("-n.nn EV").
 */
static float
calcev(char *c, int l, int16_t v)
{
#if 0	/* Adjustment seems silly.  If someone complains, I'll reconsider. */
	int16_t n;

	/*
	 * XXX 1/3 and 2/3 values seem to be a bit off.  This makes a
	 * slight adjustment; may want to revisit.
	 */
	n = (abs(v) - 32) * (v & 0x8000 ? -1 : 1);
	if (n == 20 || n == -12) v++;
	else if (n == -20 || n == 12) v--;
#endif

	if (c) snprintf(c, l, "%.2f EV", (float)v / 32);
	return ((float)v / 32);
}


/* Macro mode. */

static struct descrip canon_macro[] = {
	{ 1,	"Macro" },
	{ 2,	"Normal" },
	{ -1,	"Unknown" },
};


/* Focus type. */

static struct descrip canon_focustype[] = {
	{ 0,	"Manual" },
	{ 1,	"Auto" },
	{ 2,	"Auto" },
	{ 3,	"Close-Up (Macro Mode)" },
	{ 7,	"Infinity Mode" },
	{ 8,	"Locked (Pan Mode)" },
	{ -1,	"Unknown" },
};


/* Quality. */

static struct descrip canon_quality[] = {
	{ 2,	"Normal" },
	{ 3,	"Fine" },
	{ 5,	"Superfine" },
	{ -1,	"Unknown" },
};


/* Flash mode. */

static struct descrip canon_flash[] = {
	{ 0,	"Off" },
	{ 1,	"Auto" },
	{ 2,	"On" },
	{ 3,	"Red-Eye Reduction" },
	{ 4,	"Slow-Synchro" },
	{ 5,	"Red-Eye Reduction (Auto)" },
	{ 6,	"Red-Eye Reduction (On)" },
	{ 16,	"External Flash" },
	{ -1,	"Unknown" },
};


/* Drive mode. */

static struct descrip canon_drive[] = {
	{ 0,	"Single" },		/* "Timed" when field 2 is > 0. */
	{ 1,	"Continuous" },
	{ -1,	"Unknown" },
};


/* Focus mode. */

static struct descrip canon_focus1[] = {
	{ 0,	"One-Shot" },
	{ 1,	"AI Servo" },
	{ 2,	"AI Focus" },
	{ 3,	"Manual" },
	{ 4,	"Single" },
	{ 5,	"Continuous" },
	{ 6,	"Manual" },
	{ -1,	"Unknown" },
};


/* Image size. */

static struct descrip canon_imagesz[] = {
	{ 0,	"Large" },
	{ 1,	"Medium" },
	{ 2,	"Small" },
	{ -1,	"Unknown" },
};


/* Shooting mode. */

static struct descrip canon_shoot[] = {
	{ 0,	"Full Auto" },
	{ 1,	"Manual" },
	{ 2,	"Landscape" },
	{ 3,	"Fast Shutter" },
	{ 4,	"Slow Shutter" },
	{ 5,	"Night" },
	{ 6,	"Black & White" },
	{ 7,	"Sepia" },
	{ 8,	"Portrait" },
	{ 9,	"Sports" },
	{ 10,	"Macro/Close-Up" },
	{ 11,	"Pan Focus" },
	{ 19,	"Indoor" },
	{ 22,	"Underwater" },
	{ 24,	"Kids & Pets" },
	{ 25,	"Night Snapshot" },
	{ -1,	"Unknown" },
};


/* Digital zoom. */

static struct descrip canon_dzoom[] = {
	{ 0,	"None" },
	{ 1,	"x2" },
	{ 2,	"x4" },
	{ -1,	"Unknown" },
};


/* Contrast, saturation, & sharpness. */

static struct descrip canon_range[] = {
	{ 0,	"Normal" },
	{ 1,	"High" },
	{ 0xffff, "Low" },
	{ -1,	"Unknown" },
};


/* ISO speed rating. */

static struct descrip canon_iso[] = {
	{ 15,	"Auto" },
	{ 16,	"50" },
	{ 17,	"100" },
	{ 18,	"200" },
	{ 19,	"400" },
	{ -1,	"Unknown" },
};


/* Metering mode. */

static struct descrip canon_meter[] = {
	{ 0,	"Default" },
	{ 1,	"Spot" },
	{ 3,	"Evaluative" },
	{ 4,	"Partial" },
	{ 5,	"Center-Weighted" },
	{ -1,	"Unknown" },
};


/* Exposure mode. */

static struct descrip canon_expmode[] = {
	{ 0,	"Easy Shooting" },
	{ 1,	"Program" },
	{ 2,	"Tv-Priority" },
	{ 3,	"Av-Priority" },
	{ 4,	"Manual" },
	{ 5,	"A-DEP" },
	{ 6,	"DEP" },
	{ -1,	"Unknown" },
};


/* White balance. */

static struct descrip canon_whitebal[] = {
	{ 0,	"Auto" },
	{ 1,	"Daylight" },
	{ 2,	"Cloudy" },
	{ 3,	"Tungsten" },
	{ 4,	"Fluorescent" },
	{ 5,	"Flash" },
	{ 6,	"Custom" },
	{ 7,	"Black & White" },
	{ 8,	"Shade" },
	{ 9,	"Manual Temperature" },
	{ 14,	"Daylight Fluorescent" },
	{ 15,	"Custom 1" },
	{ 16,	"Custom 2" },
	{ 17,	"Underwater" },
	{ -1,	"Unknown" },
};


/* Maker note IFD tags. */

static struct exiftag canon_tags[] = {
	{ 0x0001, TIFF_SHORT, 0,  ED_UNK, "Canon1Tag",
	  "Canon Tag1 Offset", NULL },
	{ 0x0004, TIFF_SHORT, 0,  ED_UNK, "Canon4Tag",
	  "Canon Tag4 Offset", NULL },
	{ 0x0006, TIFF_ASCII, 32, ED_VRB, "ImageType",
	  "Image Type", NULL },
	{ 0x0007, TIFF_ASCII, 24, ED_CAM, "FirmwareVer",
	  "Firmware Version", NULL },
	{ 0x0008, TIFF_LONG,  1,  ED_IMG, "ImgNum",
	  "Image Number", NULL },
	{ 0x0009, TIFF_ASCII, 32, ED_CAM, "OwnerName",
	  "Owner Name", NULL },
	{ 0x000c, TIFF_LONG,  1,  ED_CAM, "Serial",
	  "Serial Number", NULL },
	{ 0x000f, TIFF_SHORT, 0,  ED_UNK, "CustomFunc",
	  "Custom Function", NULL },
	{ 0x0090, TIFF_SHORT, 0,  ED_UNK, "CustomFunc",
	  "Custom Function", NULL },
	{ 0x0093, TIFF_SHORT, 0,  ED_UNK, "Canon93Tag",
	  "Canon Tag93 Offset", NULL },
	{ 0x0095, TIFF_ASCII, 64, ED_PAS, "LensName",
	  "Lens Name", NULL },
	{ 0x00a0, TIFF_SHORT, 0,  ED_UNK, "CanonA0Tag",
	  "Canon TagA0 Offset", NULL },
	{ 0xffff, TIFF_UNKN,  0,  ED_UNK, "CanonUnknown",
	  "Canon Unknown", NULL },
};


/* Fields under tag 0x0001 (camera settings). */

static struct exiftag canon_tags01[] = {
	{ 0,  TIFF_SHORT, 0, ED_VRB, "Canon1Len",
	  "Canon Tag1 Length", NULL },
	{ 1,  TIFF_SHORT, 0, ED_IMG, "CanonMacroMode",
	  "Macro Mode", canon_macro },
	{ 2,  TIFF_SHORT, 0, ED_VRB, "CanonTimerLen",
	  "Self-Timer Length", NULL },
	{ 3,  TIFF_SHORT, 0, ED_IMG, "CanonQuality",
	  "Compression Setting", canon_quality },
	{ 4,  TIFF_SHORT, 0, ED_IMG, "CanonFlashMode",
	  "Flash Mode", canon_flash },
	{ 5,  TIFF_SHORT, 0, ED_IMG, "CanonDriveMode",
	  "Drive Mode", canon_drive },
	{ 7,  TIFF_SHORT, 0, ED_IMG, "CanonFocusMode",
	  "Focus Mode", canon_focus1 },
	{ 10, TIFF_SHORT, 0, ED_IMG, "CanonImageSize",
	  "Image Size", canon_imagesz },
	{ 11, TIFF_SHORT, 0, ED_IMG, "CanonShootMode",
	  "Shooting Mode", canon_shoot },
	{ 12, TIFF_SHORT, 0, ED_VRB, "CanonDigiZoom",
	  "Digital Zoom", NULL },
	{ 13, TIFF_SHORT, 0, ED_IMG, "CanonContrast",
	  "Contrast", canon_range },
	{ 14, TIFF_SHORT, 0, ED_IMG, "CanonSaturate",
	  "Saturation", canon_range },
	{ 15, TIFF_SHORT, 0, ED_IMG, "CanonSharpness",
	  "Sharpness", canon_range },
	{ 16, TIFF_SHORT, 0, ED_IMG, "CanonISO",
	  "ISO Speed Rating", canon_iso },
	{ 17, TIFF_SHORT, 0, ED_IMG, "CanonMeterMode",
	  "Metering Mode", canon_meter },
	{ 18, TIFF_SHORT, 0, ED_IMG, "CanonFocusType",
	  "Focus Type", canon_focustype },
	{ 19, TIFF_SHORT, 0, ED_UNK, "CanonAFPoint",
	  "Autofocus Point", NULL },
	{ 20, TIFF_SHORT, 0, ED_IMG, "CanonExpMode",
	  "Exposure Mode", canon_expmode },
	{ 23, TIFF_SHORT, 0, ED_UNK, "CanonMaxFocal",
	  "Max Focal Length", NULL },
	{ 24, TIFF_SHORT, 0, ED_UNK, "CanonMinFocal",
	  "Min Focal Length", NULL },
	{ 25, TIFF_SHORT, 0, ED_UNK, "CanonFocalUnits",
	  "Focal Units/mm", NULL },
	{ 28, TIFF_SHORT, 0, ED_UNK, "CanonFlashAct",
	  "Flash Activity", NULL },
	{ 29, TIFF_SHORT, 0, ED_UNK, "CanonFlashDet",
	  "Flash Details", NULL },
	{ 36, TIFF_SHORT, 0, ED_VRB, "CanonDZoomRes",
	  "Zoomed Resolution", NULL },
	{ 37, TIFF_SHORT, 0, ED_VRB, "CanonBZoomRes",
	  "Base Zoom Resolution", NULL },
	{ 0xffff, TIFF_SHORT, 0, ED_UNK, "Canon01Unknown",
	  "Canon Tag1 Unknown", NULL },
};


/* Fields under tag 0x0004 (shot info). */

static struct exiftag canon_tags04[] = {
	{ 0,  TIFF_SHORT, 0, ED_VRB, "Canon4Len",
	  "Canon Tag4 Length", NULL },
	{ 2,  TIFF_SHORT, 0, ED_IMG, "CanonSensorSpeed",
	  "Sensor ISO Speed", NULL },
	{ 6,  TIFF_SHORT, 0, ED_IMG, "CanonExpComp",
	  "Exposure Compensation", NULL },
	{ 7,  TIFF_SHORT, 0, ED_IMG, "CanonWhiteB",
	  "White Balance", canon_whitebal },
	{ 9,  TIFF_SHORT, 0, ED_IMG, "CanonSequence",
	  "Sequence Number", NULL },
	{ 14, TIFF_SHORT, 0, ED_UNK, "CanonAFPoint2",
	  "Autofocus Point", NULL },
	{ 15, TIFF_SHORT, 0, ED_IMG, "CanonFlashBias",
	  "Flash Bias", NULL },
	{ 19, TIFF_SHORT, 0, ED_IMG, "CanonSubjDst",
	  "Subject Distance", NULL },
	{ 0xffff, TIFF_SHORT, 0, ED_UNK, "Canon04Unknown",
	  "Canon Tag4 Unknown", NULL },
};


/* Fields under tag 0x00a0 (EOS 1D, 1Ds). */

static struct exiftag canon_tagsA0[] = {
	{ 0,  TIFF_SHORT, 0, ED_VRB, "CanonA0Len",
	  "Canon TagA0 Length", NULL },
	{ 9,  TIFF_SHORT, 0, ED_IMG, "CanonColorTemp",
	  "Color Temperature", NULL },
	{ 10, TIFF_SHORT, 0, ED_IMG, "CanonColorMatrix",
	  "Color Matrix", NULL },
	{ 0xffff, TIFF_SHORT, 0, ED_UNK, "CanonA0Unknown",
	  "Canon TagA0 Unknown", NULL },
};


/* Fields under tag 0x0093 (counter on EOS 1D, 1Ds). */

static struct exiftag canon_tags93[] = {
	{ 0,  TIFF_SHORT, 0, ED_VRB, "Canon93Len",
	  "Canon Tag93 Length", NULL },
	{ 1,  TIFF_SHORT, 0, ED_VRB, "CanonActuateMult",
	  "Actuation Multiplier", NULL },
	{ 2,  TIFF_SHORT, 0, ED_VRB, "CanonActuateCount",
	  "Actuation Counter", NULL },
	{ 0xffff, TIFF_SHORT, 0, ED_UNK, "Canon93Unknown",
	  "Canon Tag93 Unknown", NULL },
};


/* Placeholder for unknown fields. */

static struct exiftag canon_tagsunk[] = {
	{ 0xffff, TIFF_SHORT, 0, ED_UNK, "CanonUnknown",
	  "Canon Unknown", NULL },
};


/* Value descriptions for custom functions. */

static struct descrip ccstm_offon[] = {
	{ 0,	"Off" },
	{ 1,	"On" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_shutter[] = {
	{ 0,	"AF/AE Lock" },
	{ 1,	"AE Lock/AF" },
	{ 2,	"AF/AF Lock" },
	{ 3,	"AE+Release/AE+AF" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_disen[] = {
	{ 0,	"Disabled" },
	{ 1,	"Enabled" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_explvl[] = {
	{ 0,	"1/2 Stop" },
	{ 1,	"1/3 Stop" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_autooff[] = {
	{ 0,	"Auto" },
	{ 1,	"Off" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_shutspd[] = {
	{ 0,	"Auto" },
	{ 1,	"1/200 (Fixed)" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_aebseq[] = {
	{ 0,	"0,-,+/Enabled" },
	{ 1,	"0,-,+/Disabled" },
	{ 2,	"-,0,+/Enabled" },
	{ 3,	"-,0,+/Disabled" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_shutsync[] = {
	{ 0,	"1st-Curtain Sync" },
	{ 1,	"2nd-Curtain Sync" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_lensaf[] = {
	{ 0,	"AF Stop" },
	{ 1,	"Operate AF" },
	{ 2,	"Lock AE & Start Timer" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_endis[] = {
	{ 0,	"Enabled" },
	{ 1,	"Disabled" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_menubut[] = {
	{ 0,	"Top" },
	{ 1,	"Previous (Volatile)" },
	{ 2,	"Previous" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_setbut[] = {
	{ 0,	"Not Assigned" },
	{ 1,	"Change Quality" },
	{ 2,	"Change ISO Speed" },
	{ 3,	"Select Parameters" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_yesno[] = {
	{ 0,	"Yes" },
	{ 1,	"No" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_noyes[] = {
	{ 0,	"No" },
	{ 1,	"Yes" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_onoff[] = {
	{ 0,	"On" },
	{ 1,	"Off" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_afsel[] = {
	{ 0,	"H=AF+Main/V=AF+Command" },
	{ 1,	"H=Comp+Main/V=Comp+Command" },
	{ 2,	"H=Command Only/V=Assist+Main" },
	{ 3,	"H=FEL+Main/V=FEL+Command" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_afill[] = {
	{ 0,	"On" },
	{ 1,	"Off" },
	{ 2,	"On Without Dimming" },
	{ 3,	"Brighter" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_lcdpanels[] = {
	{ 0,	"Remain. Shots/File No." },
	{ 1,	"ISO/Remain. Shots" },
	{ 2,	"ISO/File No." },
	{ 3,	"Shots In Folder/Remain. Shots" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_usmmf[] = {
	{ 0,	"Turns On After One-Shot AF" },
	{ 1,	"Turns Off After One-Shot AF" },
	{ 2,	"Always Turned Off" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_explvlinc[] = {
	{ 0,	"1/3-Stop Set, 1/3-Stop Comp" },
	{ 1,	"1-Stop Set, 1/3-Stop Comp" },
	{ 2,	"1/2-Stop Set, 1/2-Stop Comp" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_tvavform[] = {
	{ 0,	"Tv=Main/Av=Control" },
	{ 1,	"Tv=Control/Av=Main" },
	{ 2,	"Tv=Main/Av=Main w/o Lens" },
	{ 3,	"Tv=Control/Av=Main w/o Lens" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_shutterael[] = {
	{ 0,	"AF/AE Lock Stop" },
	{ 1,	"AE Lock/AF" },
	{ 2,	"AF/AF Lock, No AE Lock" },
	{ 3,	"AE/AF, No AE Lock" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_afspot[] = {
	{ 0,	"45/Center AF Point" },
	{ 1,	"11/Active AF Point" },
	{ 2,	"11/Center AF Point" },
	{ 3,	"9/Active AF Point" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_afact[] = {
	{ 0,	"Single AF Point" },
	{ 1,	"Expanded (TTL. of 7 AF Points)" },
	{ 2,	"Automatic Expanded (Max. 13)" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_regaf[] = {
	{ 0,    "Assist + AF" },
	{ 1,    "Assist" },
	{ 2,    "Only While Pressing Assist" },
	{ -1,   "Unknown" },
};

static struct descrip ccstm_lensaf1[] = {
	{ 0,	"AF Stop" },
	{ 1,	"AF Start" },
	{ 2,	"AE Lock While Metering" },
	{ 3,	"AF Point: M->Auto/Auto->Ctr" },
	{ 4,	"AF Mode: ONESHOT<->SERVO" },
	{ 5,	"IS Start" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_aisens[] = {
	{ 0,	"Standard" },
	{ 1,	"Slow" },
	{ 2,	"Moderately Slow" },
	{ 3,	"Moderately Fast" },
	{ 4,	"Fast" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_fscr[] = {
	{ 0,	"Ec-N, R" },
	{ 1,	"Ec-A,B,C,CII,CIII,D,H,I,L" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_10dsetbut[] = {
	{ 0,	"Not Assigned" },
	{ 1,	"Change Quality" },
	{ 2,	"Change Parameters" },
	{ 3,	"Menu Display" },
	{ 4,	"Image Replay" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_10dshutter[] = {
	{ 0,	"AF/AE Lock" },
	{ 1,	"AE Lock/AF" },
	{ 2,	"AF/AF Lock, No AE Lock" },
	{ 3,	"AE/AF, No AE Lock" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_assistflash[] = {
	{  0,	"Emits/Fires" },
	{  1,	"Does Not Emit/Fires" },
	{  2,	"Only Ext. Flash Emits/Fires" },
	{  3,	"Emits/Does Not Fire" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_afptreg[] = {
	{ 0,	"Center" },
	{ 1,	"Bottom" },
	{ 2,	"Right" },
	{ 3,	"Extreme Right" },
	{ 4,	"Automatic" },
	{ 5,	"Extreme Left" },
	{ 6,	"Left" },
	{ 7,	"Top" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_rawjpeg[] = {
	{ 0,	"RAW+Small/Normal" },
	{ 1,	"RAW+Small/Fine" },
	{ 2,	"RAW+Medium/Normal" },
	{ 3,	"RAW+Medium/Fine" },
	{ 4,	"RAW+Large/Normal" },
	{ 5,	"RAW+Large/Fine" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_10dmenubut[] = {
	{ 0,	"Previous (Volatile)" },
	{ 1,	"Previous" },
	{ 2,	"Top" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_assistbut[] = {
	{ 0,	"Normal" },
	{ 1,	"Select Home Position" },
	{ 2,	"Select HP (while pressing)" },
	{ 3,	"Av+/- (AF point by QCD)" },
	{ 4,	"FE lock" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_20dexplvl[] = {
	{ 0,	"1/3 Stop" },
	{ 1,	"1/2 Stop" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_20dflashsync[] = {
	{ 0,	"Auto" },
	{ 1,	"1/250 (Fixed)" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_20dflash[] = {
	{  0,	"Fires" },
	{  1,	"Does Not Fire" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_20dafpsel[] = {
	{  0,	"Normal" },
	{  1,	"Multi-Controller Direct" },
	{  2,	"Quick Control Dial Direct" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_20dettl[] = {
	{  0,	"Evaluative" },
	{  1,	"Average" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_5dflashsync[] = {
	{ 0,	"Auto" },
	{ 1,	"1/200 (Fixed)" },
	{ -1,	"Unknown" },
};

static struct descrip ccstm_5dfscr[] = {
	{ 0,	"Ee-A" },
	{ 1,	"Ee-D" },
	{ 2,	"Ee-S" },
	{ -1,	"Unknown" },
};


/* D30/D60 custom functions. */

static struct exiftag canon_d30custom[] = {
	{ 1,  TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Long exposure noise reduction", ccstm_offon },
	{ 2,  TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Shutter/AE lock buttons", ccstm_shutter },
	{ 3,  TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Mirror lockup", ccstm_disen },
	{ 4,  TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Tv/Av and exposure level", ccstm_explvl },
	{ 5,  TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "AF-assist light", ccstm_autooff },
	{ 6,  TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Av mode shutter speed", ccstm_shutspd },
	{ 7,  TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "AEB sequence/auto cancellation", ccstm_aebseq },
	{ 8,  TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Shutter curtain sync", ccstm_shutsync },
	{ 9,  TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Lens AF stop button", ccstm_lensaf },
	{ 10, TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Fill flash auto reduction", ccstm_endis },
	{ 11, TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Menu button return position", ccstm_menubut },
	{ 12, TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Shooting Set button function", ccstm_setbut },
	{ 13, TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Sensor cleaning", ccstm_disen },
	{ 14, TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Superimposed display", ccstm_onoff },
	{ 15, TIFF_SHORT, 0, ED_VRB, "D30Custom",
	  "Shutter release w/o CF card", ccstm_yesno },
	{ 0xffff, TIFF_SHORT, 0, ED_UNK, "D30CustomUnknown",
	  "Canon D30/D60 Custom Unknown", NULL },
};


/* EOS-1D/1Ds custom functions. */

static struct exiftag canon_1dcustom[] = {
	{ 0,  TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Focusing screen", ccstm_fscr },
	{ 1,  TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Finder display during exposure", ccstm_offon },
	{ 2,  TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Shutter release w/o CF card", ccstm_yesno },
	{ 3,  TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "ISO speed expansion", ccstm_noyes },
	{ 4,  TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Shutter button/AEL button", ccstm_shutterael },
	{ 5,  TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Manual Tv/Av for M", ccstm_tvavform },
	{ 6,  TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Exposure level increments", ccstm_explvlinc },
	{ 7,  TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "USM lens electronic MF", ccstm_usmmf },
	{ 8,  TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Top/back LCD panels", ccstm_lcdpanels },
	{ 9,  TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "AEB sequence/auto cancellation", ccstm_aebseq },
	{ 10, TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "AF point illumination", ccstm_afill },
	{ 11, TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "AF point selection", ccstm_afsel },
	{ 12, TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Mirror lockup", ccstm_disen },
	{ 13, TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "# AF points/spot metering", ccstm_afspot },
	{ 14, TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Fill flash auto reduction", ccstm_endis },
	{ 15, TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Shutter curtain sync", ccstm_shutsync },
	{ 16, TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Safety shift in Av or Tv", ccstm_disen },
	{ 17, TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "AF point activation area", ccstm_afact },
	{ 18, TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Switch to registered AF point", ccstm_regaf },
	{ 19, TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "Lens AF stop button", ccstm_lensaf1 },
	{ 20, TIFF_SHORT, 0, ED_VRB, "1DCustom",
	  "AI servo tracking sensitivity", ccstm_aisens },
	{ 0xffff, TIFF_SHORT, 0, ED_UNK, "1DCustomUnknown",
	  "Canon 1D/1Ds Custom Unknown", NULL },
};

/* 5D custom functions. */

static struct exiftag canon_5dcustom[] = {
	{ 0, TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Focusing Screen", ccstm_5dfscr },
	{ 1,  TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "SET button function when shooting", ccstm_10dsetbut },
	{ 2,  TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Long exposure noise reduction", ccstm_offon },
	{ 3,  TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Flash sync speed in Av mode", ccstm_5dflashsync },
	{ 4,  TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Shutter button/AE lock button", ccstm_10dshutter },
	{ 5,  TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "AF-assist beam", ccstm_assistflash },
	{ 6,  TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Exposure level increments", ccstm_20dexplvl },
	{ 7,  TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Flash firing", ccstm_20dflash },
	{ 8,  TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "ISO expansion", ccstm_offon },
	{ 9,  TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "AEB sequence/auto cancellation", ccstm_aebseq },
	{ 10, TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Superimposed display", ccstm_onoff },
	{ 11, TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Menu button display position", ccstm_10dmenubut },
	{ 12, TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Mirror lockup", ccstm_disen },
	{ 13, TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "AF point selection method", ccstm_20dafpsel },
	{ 14, TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "E-TTL II", ccstm_20dettl },
	{ 15, TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Shutter curtain sync", ccstm_shutsync },
	{ 16, TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Safety shift in Av or Tv", ccstm_disen },
	{ 17, TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Lens AF stop button", ccstm_lensaf1 },
	{ 18, TIFF_SHORT, 0, ED_VRB, "5DCustom",
	  "Add original decision data", ccstm_offon },
	{ 0xffff, TIFF_SHORT, 0, ED_UNK, "5DCustomUnknown",
	  "Canon 5D Custom Unknown", NULL },
};

/* 10D custom functions. */

static struct exiftag canon_10dcustom[] = {
	{ 1,  TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "SET button function when shooting", ccstm_10dsetbut },
	{ 2,  TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Shutter release w/o CF card", ccstm_yesno },
	{ 3,  TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Flash sync speed in Av mode", ccstm_shutspd },
	{ 4,  TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Shutter button/AE lock button", ccstm_10dshutter },
	{ 5,  TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "AF-assist beam/Flash firing", ccstm_assistflash },
	{ 6,  TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Exposure level increments", ccstm_explvl },
	{ 7,  TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "AF point registration", ccstm_afptreg },
	{ 8,  TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "RAW+JPEG recording", ccstm_rawjpeg },
	{ 9,  TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "AEB sequence/auto cancellation", ccstm_aebseq },
	{ 10, TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Superimposed display", ccstm_onoff },
	{ 11, TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Menu button display position", ccstm_10dmenubut },
	{ 12, TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Mirror lockup", ccstm_disen },
	{ 13, TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Assist button function", ccstm_assistbut },
	{ 14, TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Fill flash auto reduction", ccstm_endis },
	{ 15, TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Shutter curtain sync", ccstm_shutsync },
	{ 16, TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Safety shift in Av or Tv", ccstm_disen },
	{ 17, TIFF_SHORT, 0, ED_VRB, "10DCustom",
	  "Lens AF stop button", ccstm_lensaf },
	{ 0xffff, TIFF_SHORT, 0, ED_UNK, "10DCustomUnknown",
	  "Canon 10D Custom Unknown", NULL },
};

/* 20D custom functions. */

static struct exiftag canon_20dcustom[] = {
	{ 0,  TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "SET button function when shooting", ccstm_10dsetbut },
	{ 1,  TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Long exposure noise reduction", ccstm_offon },
	{ 2,  TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Flash sync speed in Av mode", ccstm_20dflashsync },
	{ 3,  TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Shutter button/AE lock button", ccstm_10dshutter },
	{ 4,  TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "AF-assist beam", ccstm_assistflash },
	{ 5,  TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Exposure level increments", ccstm_20dexplvl },
	{ 6,  TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Flash firing", ccstm_20dflash },
	{ 7,  TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "ISO expansion", ccstm_offon },
	{ 8,  TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "AEB sequence/auto cancellation", ccstm_aebseq },
	{ 9, TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Superimposed display", ccstm_onoff },
	{ 10, TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Menu button display position", ccstm_10dmenubut },
	{ 11, TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Mirror lockup", ccstm_disen },
	{ 12, TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "AF point selection method", ccstm_20dafpsel },
	{ 13, TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "E-TTL II", ccstm_20dettl },
	{ 14, TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Shutter curtain sync", ccstm_shutsync },
	{ 15, TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Safety shift in Av or Tv", ccstm_disen },
	{ 16, TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Lens AF stop button", ccstm_lensaf1 },
	{ 17, TIFF_SHORT, 0, ED_VRB, "20DCustom",
	  "Add original decision data", ccstm_offon },
	{ 0xffff, TIFF_SHORT, 0, ED_UNK, "20DCustomUnknown",
	  "Canon 20D Custom Unknown", NULL },
};


/*
 * Process maker note tag 0x0001 values.
 */
static int
canon_prop01(struct exifprop *aprop, struct exifprop *prop,
    unsigned char *off, struct exiftags *t)
{
	u_int16_t v = (u_int16_t)aprop->value;

	switch (aprop->tag) {
	case 2:
		aprop->lvl = v ? ED_IMG : ED_VRB;
		exifstralloc(&aprop->str, 32);
		snprintf(aprop->str, 31, "%d sec", v / 10);
		break;
	case 5:
		/* Change "Single" to "Timed" if #2 > 0. */

		if (!v && exif2byte(off + 2 * 2, t->mkrmd.order))
			strcpy(aprop->str, "Timed");
		break;
	case 12:
		aprop->lvl = v ? ED_IMG : ED_VRB;

		/*
		 * Looks like we can calculate zoom level when value
		 * is 3 (ref S110).  Calculation is (2 * #37 / #36).
		 */

		if (v == 3 && prop->count >= 37) {
			exifstralloc(&aprop->str, 32);
			snprintf(aprop->str, 31, "x%.1f", 2 *
			    (float)exif2byte(off + 37 * 2, t->mkrmd.order) /
			    (float)exif2byte(off + 36 * 2, t->mkrmd.order));
		} else
			aprop->str = finddescr(canon_dzoom, v);
		break;
	case 16:
		/* ISO overrides standard one if known. */
		if (!strcmp(aprop->str, "Unknown")) {
			aprop->lvl = ED_VRB;
			break;
		}
		aprop->override = EXIF_T_ISOSPEED;
		break;
	case 17:
		/* Maker meter mode overrides standard one if known. */
		if (!strcmp(aprop->str, "Unknown")) {
			aprop->lvl = ED_VRB;
			break;
		}
		aprop->override = EXIF_T_METERMODE;
		break;
	case 20:
		/* With "Easy Shooting", shooting mode is all that matters. */
		aprop->lvl = v ? ED_IMG : ED_VRB;
		break;
	default:
		return (FALSE);
	}

	return (TRUE);
}


/*
 * Process maker note tag 0x0004 values.
 */
static int
canon_prop04(struct exifprop *aprop, struct exifprop *prop,
    unsigned char *off, struct exiftags *t)
{
	struct exifprop *tmpprop;
	u_int16_t v = (u_int16_t)aprop->value;
	int d;

	switch (aprop->tag) {
	case 6:
		/* Calculate sensor speed (ISO units). */
		exifstralloc(&aprop->str, 32);
		snprintf(aprop->str, 31, "%d", (int)(exp(calcev(NULL, 0, v) *
		    log(2)) * 100.0 / 32.0 + 0.5));
		break;
		
	case 7:
		aprop->override = EXIF_T_WHITEBAL;
		break;
	case 9:
		aprop->lvl = v ? ED_IMG : ED_VRB;
		break;
	case 15:
		exifstralloc(&aprop->str, 16);
		if (calcev(aprop->str, 15, v) == 0.0)
			aprop->lvl = ED_VRB;
		break;

	/*
	 * Sigh.  Some cameras have a standard Exif subject distance tag,
	 * some do not.  Some express this in mm, some in cm.  (I cannot
	 * for the life of me figure out how to tell what the units are.)
	 * It looks like maybe some of the newer models stick to cm; we'll
	 * assume cm and consider mm by exception.  In any case, we'll only
	 * display the value in the absence of the standard Exif value.
	 * Needless to say, this is pretty ugly.
	 */

	case 19:
		exifstralloc(&aprop->str, 32);

		if (!v) {
			aprop->lvl = ED_VRB;
			strcpy(aprop->str, "Unknown");
			break;
		}

		if (t->model && (!strcmp(t->model, "Canon PowerShot A10") ||
		    !strcmp(t->model, "Canon PowerShot S110") ||
		    !strcmp(t->model, "Canon PowerShot S30") ||
		    !strcmp(t->model, "Canon PowerShot S40") ||
		    !strcmp(t->model, "Canon EOS 10D")))
			d = 1000;
		else
			d = 100;

		if (v == 0xffff)
			strcpy(aprop->str, "Infinity");
		else
			snprintf(aprop->str, 31, "%.3f m",
			    (float)v / (float)d);

		if ((tmpprop = findprop(t->props, tags, EXIF_T_DISTANCE))) {
			if (strcmp(tmpprop->str, "Unknown"))
				aprop->lvl = ED_VRB;
			else
				aprop->override = EXIF_T_DISTANCE;
		}
		break;

	default:
		return (FALSE);
	}

	return (TRUE);
}


/*
 * Process maker note tag 0x00a0 values.
 */
static int
canon_propA0(struct exifprop *aprop, struct exifprop *prop,
    unsigned char *off, struct exiftags *t)
{

	switch (aprop->tag) {
	case 9:
		exifstralloc(&aprop->str, 32);
		snprintf(aprop->str, 31, "%d K", aprop->value);
		break;
	default:
		return (FALSE);
	}

	return (TRUE);
}


/*
 * Common function for a tag's child values.  Pass in the list of tags
 * and a function to process them.
 */
static int
canon_subval(struct exifprop *prop, struct exiftags *t,
    struct exiftag *subtags, int (*valfun)())
{
	int i, j;
	u_int16_t v;
	struct exifprop *aprop;
	unsigned char *off = t->mkrmd.btiff + prop->value;

	/* Check size of tag (first value) if we're not debugging. */

	if (valfun && exif2byte(off, t->mkrmd.order) != 2 * prop->count) {
		exifwarn("Canon maker tag appears corrupt");
		return (FALSE);
	}

	if (debug)
		printf("Processing %s (0x%04X) directory, %d entries\n",
		    prop->name, prop->tag, prop->count);

	for (i = 0; i < (int)prop->count; i++) {
		v = exif2byte(off + i * 2, t->mkrmd.order);

		aprop = childprop(prop);
		aprop->value = (u_int32_t)v;
		aprop->tag = i;
		aprop->tagset = subtags;

		/* Lookup property name and description. */

		for (j = 0; subtags[j].tag < EXIF_T_UNKNOWN &&
		    subtags[j].tag != i; j++);
		aprop->name = subtags[j].name;
		aprop->descr = subtags[j].descr;
		aprop->lvl = subtags[j].lvl;
		if (subtags[j].table)
			aprop->str = finddescr(subtags[j].table, v);

		dumpprop(aprop, NULL);

		/* Process individual values.  Returns false if unknown. */

		if (valfun && !valfun(aprop, prop, off, t)) {
			if (aprop->lvl != ED_UNK)
				continue;
			exifstralloc(&aprop->str, 32);
			snprintf(aprop->str, 31, "num %02d, val 0x%04X", i, v);
		}
	}

	if (debug)
		printf("\n");
	return (TRUE);
}


/*
 * Process custom function tag values.
 */
static void
canon_custom(struct exifprop *prop, unsigned char *off, enum byteorder o,
    struct exiftag *table)
{
	int i, j = -1;
	const char *cn;
	char *cv = NULL;
	u_int16_t v;
	struct exifprop *aprop;

	/*
	 * Check size of tag (first value).
	 * XXX There seems to be a problem with the D60 where it reports the
	 * wrong size, hence the 2nd clause in the if().  Could be related
	 * to the second value being zero?
	 */

	if (exif2byte(off, o) != 2 * prop->count &&
	    exif2byte(off, o) != 2 * (prop->count - 1)) {
		exifwarn("Canon custom tag appears corrupt");
		return;
	}

	if (debug)
		printf("Processing %s directory, %d entries\n", prop->name,
		    prop->count);

	for (i = 1; i < (int)prop->count; i++) {
		v = exif2byte(off + i * 2, o);

		aprop = childprop(prop);
		aprop->value = v & 0xff;
		aprop->tag = v >> 8 & 0xff;
		aprop->tagset = table;

		/*
		 * Lookup function name and value.  First byte is function
		 * number; second is function value.
		 */

		for (j = 0; table[j].tag != EXIF_T_UNKNOWN &&
		    table[j].tag != (v >> 8 & 0xff); j++);
		aprop->name = table[j].name;
		aprop->descr = prop->descr;
		aprop->lvl = table[j].lvl;
		if (table[j].table)
			cv = finddescr(table[j].table,
			    (u_int16_t)(v & 0xff));
		cn = table[j].descr;


		dumpprop(aprop, NULL);

		exifstralloc(&aprop->str, 4 + strlen(cn) +
		    (cv ? strlen(cv) : 10));

		if (cv && j != -1) {
			snprintf(aprop->str, 4 + strlen(cn) + strlen(cv),
			    "%s - %s", cn, cv);
			free(cv);
			cv = NULL;
		} else {
			snprintf(aprop->str, 4 + strlen(cn) + 10, "%s %d - %d",
			    cn, v >> 8 & 0xff, v & 0xff);
			aprop->str[3 + strlen(cn) + 10] = '\0';
			aprop->lvl = ED_UNK;
		}
	}

	if (debug)
		printf("\n");
}


/*
 * Process Canon maker note tags.
 */
void
canon_prop(struct exifprop *prop, struct exiftags *t)
{
	unsigned char *offset;
	u_int16_t flmin = 0, flmax = 0, flunit = 0;
	u_int32_t v, w;
	struct exifprop *tmpprop;

	switch (prop->tag) {

	/* Various image data. */

	case 0x0001:
		if (!canon_subval(prop, t, canon_tags01, canon_prop01))
			break;

		/*
		 * Create a new value for the lens' focal length range.  If
		 * it's not a zoom lens, we'll make it verbose (it should
		 * match the existing focal length Exif tag).
		 */

		if (prop->count >= 25) {
			offset = t->mkrmd.btiff + prop->value;
			flmax = exif2byte(offset + 23 * 2, t->mkrmd.order);
			flmin = exif2byte(offset + 24 * 2, t->mkrmd.order);
			flunit = exif2byte(offset + 25 * 2, t->mkrmd.order);
		}

		if (flunit && (flmin || flmax)) {
			tmpprop = childprop(prop);
			tmpprop->name = "CanonLensSz";
			tmpprop->descr = "Lens Size";
			exifstralloc(&tmpprop->str, 32);

			if (flmin == flmax) {
				snprintf(tmpprop->str, 31, "%.2f mm",
			    	(float)flmax / (float)flunit);
				tmpprop->lvl = ED_VRB;
			} else {
				snprintf(tmpprop->str, 31, "%.2f - %.2f mm",
				    (float)flmin / (float)flunit,
				    (float)flmax / (float)flunit);
				tmpprop->lvl = ED_PAS;
			}
		}
		break;

	case 0x0004:
		canon_subval(prop, t, canon_tags04, canon_prop04);
		break;

	case 0x00a0:
		if (!canon_subval(prop, t, canon_tagsA0, canon_propA0))
			break;

		/* Color temp is bad if white balance isn't manual. */

		if ((tmpprop = findprop(t->props, canon_tags04, 7)))
			if (tmpprop->value != 9) {
				if ((tmpprop = findprop(prop, canon_tagsA0, 9)))
					tmpprop->lvl = ED_BAD;
		}
		break;

	/* Number of actuations. */

	case 0x0093:
		/*
		 * Alas, meanings of these fields seem to differ according
		 * to camera model.  For the 1D, 1Ds, and 1D2, they are total
		 * number of actuations.  For the 20D, they're the image
		 * number.  For now, we'll make the former behavior default
		 * and the latter an exception.
		 */

		if (!t->model) {
			exifwarn("Canon model unset; please report to author");
			break;
		}

		if (!canon_subval(prop, t, canon_tags93, NULL))
			break;
		v = 0;

		if (strstr(t->model, "20D")) {

			/* Image number is in two shorts... */

			if ((tmpprop = findprop(t->props, canon_tags93, 1))) {
				v = tmpprop->value >> 6;
				w = (tmpprop->value & 0x3f) << 8;

				if ((tmpprop = findprop(prop, canon_tags93, 2)))
					w += tmpprop->value;
				else {
					v = 0;
					w = 0;
				}
			}

			if (v) {
				tmpprop = childprop(prop);
				tmpprop->name = "ImgNum";
				tmpprop->descr = "Image Number";
				tmpprop->lvl = ED_IMG;
				exifstralloc(&tmpprop->str, 32);
				snprintf(tmpprop->str, 31, "%03d-%04d", v, w);
			}
			break;
		}

		/* Number of acuations is in two shorts... */

		if ((tmpprop = findprop(t->props, canon_tags93, 1))) {
			v = tmpprop->value * 65536;

			if ((tmpprop = findprop(prop, canon_tags93, 2)))
				v += tmpprop->value;
			else
				v = 0;
		}

		if (v) {
			tmpprop = childprop(prop);
			tmpprop->name = "CanonActuations";
			tmpprop->descr = "Camera Actuations";
			tmpprop->lvl = ED_IMG;
			tmpprop->value = v;
		}
		break;

	/* Image number. */

	case 0x0008:
		if (!prop->value)
			prop->lvl = ED_VRB;
		exifstralloc(&prop->str, 32);
		snprintf(prop->str, 31, "%03d-%04d", prop->value / 10000,
		    prop->value % 10000);
		break;

	/* Serial number. */

	case 0x000c:
		exifstralloc(&prop->str, 11);
		snprintf(prop->str, 11, "%010d", prop->value);
		break;

	/* Custom functions. */

	case 0x000f:
		/*
		 * Canon annoyingly reuses this tag value for different sets
		 * of custom functions (e.g., D30/60, 10D).  Therefore, we
		 * won't try to interpret them unless we know for sure that
		 * the camera model is supported.
		 */

		if (!t->model) {
			exifwarn("Canon model unset; please report to author");
			break;
		}

		if (strstr(t->model, "10D"))
			canon_custom(prop, t->mkrmd.btiff + prop->value,
			    t->mkrmd.order, canon_10dcustom);
		else if (strstr(t->model, "D30") || strstr(t->model, "D60"))
			canon_custom(prop, t->mkrmd.btiff + prop->value,
			    t->mkrmd.order, canon_d30custom);
		else if (strstr(t->model, "20D"))
			canon_custom(prop, t->mkrmd.btiff + prop->value,
			    t->mkrmd.order, canon_20dcustom);
		else if (strstr(t->model, "5D"))
			canon_custom(prop, t->mkrmd.btiff + prop->value,
			    t->mkrmd.order, canon_5dcustom);
		else
			exifwarn2("Custom function unsupported; please "
			    "report to author", t->model);
		break;

	case 0x0090:
		canon_custom(prop, t->mkrmd.btiff + prop->value, t->mkrmd.order,
		    canon_1dcustom);
		break;

	/* Dump debug for tags of type short w/count > 1. */

	default:
		if (prop->type == TIFF_SHORT && prop->count > 1 && debug)
			canon_subval(prop, t, canon_tagsunk, NULL);
		break;
	}
}


/*
 * Try to read Canon maker note IFDs.
 */
struct ifd *
canon_ifd(u_int32_t offset, struct tiffmeta *md)
{

	return (readifds(offset, canon_tags, md));
}
