/*
 * Copyright (c) 2001-2004, Eric M. Johnston <emj@postal.net>
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
 * $Id: tagdefs.c,v 1.24 2004/12/28 07:13:01 ejohnst Exp $
 */

/*
 * Exif tag definitions.
 *
 * Developed using the TIFF 6.0 specification:
 * (http://partners.adobe.com/asn/developer/pdfs/tn/TIFF6.pdf)
 * and the EXIF 2.21 standard: (http://tsc.jeita.or.jp/avs/data/cp3451_1.pdf).
 *
 */

#include <string.h>

#include "exif.h"
#include "exifint.h"


/* TIFF 6.0 field types. */

struct fieldtype ftypes[] = {
	{ TIFF_BYTE,	"byte",		1 },
	{ TIFF_ASCII,	"ascii",	1 },
	{ TIFF_SHORT,	"short",	2 },
	{ TIFF_LONG,	"long",		4 },
	{ TIFF_RTNL,	"rational",	8 },
	{ TIFF_SBYTE,	"sbyte",	1 },	/* not in Exif 2.2 */
	{ TIFF_UNDEF,	"undefined",	1 },
	{ TIFF_SSHORT,	"sshort",	2 },	/* not in Exif 2.2 */
	{ TIFF_SLONG,	"slong",	4 },
	{ TIFF_SRTNL,	"srational",	8 },
	{ TIFF_FLOAT,	"float",	4 },	/* not in Exif 2.2 */
	{ TIFF_DBL,	"double",	8 },	/* not in Exif 2.2 */
	{ TIFF_UNKN,	"unknown",	0 },
};


/*
 * User comment types.  All should be 8 bytes.
 */

struct descrip ucomment[] = {
	{ TIFF_ASCII, "ASCII\0\0\0" },
	{ TIFF_UNDEF, "JIS\0\0\0\0\0" },
	{ TIFF_UNDEF, "UNICODE\0" },
	{ TIFF_UNDEF, "\0\0\0\0\0\0\0\0" },
	{ TIFF_UNDEF, NULL },
};


/*
 * Various tag value lookup tables.  All are terminated by the value -1.
 */


/* Compression schemes. */

struct descrip compresss[] = {
	{ 1,	"Uncompressed" },
	{ 6,	"JPEG Compression (Thumbnail)" },
	{ -1,	"Unknown" },
};


/* Pixel compositions. */

struct descrip pixelcomps[] = {
	{ 2,	"RGB" },
	{ 6,	"YCbCr" },
	{ -1,	"Unknown" },
};


/* Image orientation in terms of rows and columns. */

struct descrip orients[] = {
	{ 1,	"Top, Left-Hand" },
	{ 2,	"Top, Right-Hand" },
	{ 3,	"Bottom, Right-Hand" },
	{ 4,	"Bottom, Left-Hand" },
	{ 5,	"Left-Hand, Top" },
	{ 6,	"Right-Hand, Top" },
	{ 7,	"Right-Hand, Bottom" },
	{ 8,	"Left-Hand, Bottom" },
	{ -1,	"Unknown" },
};


/* Planar configurations. */

struct descrip planarconfigs[] = {
	{ 1,	"Chunky Format" },
	{ 2, 	"Planar Format" },
	{ -1,	"Unknown" },
};


/* Resolution units. */

struct descrip resunits[] = {
	{ 2,	"i" },
	{ 3,	"cm" },
	{ -1,	"" },
};


/*
 * Chrominance components sampling ratio.
 * Note: This only refers to the second short; first is assumed to be 2.
 */

struct descrip chromratios[] = {
	{ 1,	"YCbCr4:2:2" },
	{ 2,	"YCbCr4:2:0" },
	{ -1,	"Unknown" },
};


/* Chrominance components positioning. */

struct descrip chrompos[] = {
	{ 1,	"Centered" },
	{ 2,	"Co-Sited" },
	{ -1,	"Unknown" },
};


/* Exposure programs. */

struct descrip expprogs[] = {
	{ 0,	"Not Defined" },
	{ 1,	"Manual" },
	{ 2,	"Normal Program" },
	{ 3,	"Aperture Priority" },
	{ 4,	"Shutter Priority" },
	{ 5,	"Creative" },
	{ 6,	"Action" },
	{ 7,	"Portrait Mode" },
	{ 8,	"Landscape Mode" },
	{ -1,	"Unknown" },
};


/* Component configuration. */

struct descrip compconfig[] = {
	{ 0,	"Does Not Exist" },
	{ 1,	"Y" },
	{ 2,	"Cb" },
	{ 3,	"Cr" },
	{ 4,	"R" },
	{ 5,	"G" },
	{ 6,	"B" },
	{ -1,	"Unknown" },
};


/* Metering modes. */

struct descrip metermodes[] = {
	{ 0,	"Unknown" },
	{ 1,	"Average" },
	{ 2,	"Center Weighted Average" },
	{ 3,	"Spot" },
	{ 4,	"Multi Spot" },
	{ 5,	"Pattern" },
	{ 6,	"Partial" },
	{ 255,	"Other" },
	{ -1,	"Unknown" },
};


/* Light sources. */

struct descrip lightsrcs[] = {
	{ 0,	"Unknown" },
	{ 1,	"Daylight" },
	{ 2,	"Fluorescent" },
	{ 3,	"Tungsten" },
	{ 4,	"Flash" },
	{ 9,	"Fine Weather" },
	{ 10,	"Cloudy Weather" },
	{ 11,	"Shade" },
	{ 12,	"Daylight Fluorescent" },
	{ 13,	"Day White Fluorescent" },
	{ 14,	"Cool White Fluorescent" },
	{ 15,	"White Fluorescent" },
	{ 17,	"Standard Light A" },
	{ 18,	"Standard Light B" },
	{ 19,	"Standard Light C" },
	{ 20,	"D55" },
	{ 21,	"D65" },
	{ 22,	"D75" },
	{ 23,	"D50" },
	{ 24,	"ISO Studio Tungsten" },
	{ 255,	"Other" },
	{ -1,	"Unknown" },
};


/*
 * Flash modes.
 *
 * The value is split into 5 sub-values:
 *   Flash fired, bit 0;
 *   Flash return, bits 1 & 2;
 *   Flash mode, bits 3 & 4;
 *   Flash function, bit 5; and
 *   Red-eye mode, bit 6.
 * Bit 7 is unused in the 2.21 spec.
 *
 * We'll just process each sub-value individually and concatenate them.
 */

struct descrip flash_fire[] = {
	{ 0x00,	"No Flash" },
	{ 0x01,	"Flash" },
	{ -1,	"Unknown" },
};

struct descrip flash_return[] = {
	{ 0x04, "Return Not Detected" },
	{ 0x06,	"Return Detected" },
	{ -1,	"Unknown" },
};

struct descrip flash_mode[] = {
	{ 0x08, "Compulsory" },
	{ 0x10,	"Compulsory" },
	{ 0x18,	"Auto" },
	{ -1,	"Unknown" },
};

struct descrip flash_func[] = {
	{ 0x20,	"No Flash Function" },
	{ -1,	"Unknown" },
};

struct descrip flash_redeye[] = {
	{ 0x40,	"Red-Eye Reduce" },
	{ -1,	"Unknown" },
};


/* Color spaces. */

struct descrip colorspcs[] = {
	{ 1,	"sRGB" },
	{0xffff,"Uncalibrated" },
	{ -1,	"Unknown" },
};


/* Image sensor types. */

struct descrip imgsensors[] = {
	{ 1,	"Not Defined" },
	{ 2,	"One-Chip Color Area" },
	{ 3,	"Two-Chip Color Area" },
	{ 4,	"Three-Chip Color Area" },
	{ 5,	"Color Sequential Area" },
	{ 7,	"Trilinear" },
	{ 8,	"Color Sequential Linear" },
	{ -1,	"Unknown" },
};


/* File sources */

struct descrip filesrcs[] = {
	{ 0,	"Other" },
	{ 1,	"Scanner (Transparent)" },
	{ 2,	"Scanner (Reflex)" },
	{ 3,	"Digital Still Camera" },
	{ -1,	"Unknown" },
};


/* Scene types. */

struct descrip scenetypes[] = {
	{ 1,	"Directly Photographed" },
	{ -1,	"Unknown" },
};


/* Custom rendering. */

struct descrip customrend[] = {
	{ 0,	"Normal" },
	{ 1,	"Custom" },
	{ -1,	"Unknown" },
};


/* Exposure mode. */

struct descrip expmode[] = {
	{ 0,	"Auto" },
	{ 1,	"Manual" },
	{ 2,	"Auto Bracket" },
	{ -1,	"Unknown" },
};


/* White balance. */

struct descrip whitebal[] = {
	{ 0,	"Auto" },
	{ 1,	"Manual" },
	{ -1,	"Unknown" },
};


/* Scene capture type. */

struct descrip scenecaptypes[] = {
	{ 0,	"Standard" },
	{ 1,	"Landscape" },
	{ 2,	"Portrait" },
	{ 3,	"Night Scene" },
	{ -1,	"Unknown" },
};


/* Gain control. */

struct descrip gainctrl[] = {
	{ 0,	"None" },
	{ 1,	"Low Gain Up" },
	{ 2,	"High Gain Up" },
	{ 3,	"Low Gain Down" },
	{ 4,	"High Gain Down" },
	{ -1,	"Unknown" },
};


/* Contrast & sharpness. */

struct descrip processrange[] = {
	{ 0,	"Normal" },
	{ 1,	"Soft" },
	{ 2,	"Hard" },
	{ -1,	"Unknown" },
};


/* Saturation. */

struct descrip saturate[] = {
	{ 0,	"Normal" },
	{ 1,	"Low" },
	{ 2,	"High" },
	{ -1,	"Unknown" },
};


/* Subject distance range. */

struct descrip subjdist[] = {
	{ 1,	"Macro" },
	{ 2,	"Close View" },
	{ 3,	"Distant View" },
	{ -1,	"Unknown" },
};


/* Exif 2.2 tags. */

struct exiftag tags[] = {
	{ 0x0100, TIFF_UNKN,  1,  ED_IMG, 		/* columns */
	    "ImageWidth", "Image Width", NULL },
	{ 0x0101, TIFF_UNKN,  1,  ED_IMG, 		/* rows */
	    "ImageLength", "Image Height", NULL },
	{ 0x0102, TIFF_SHORT, 3,  ED_IMG, 		/* bits */
	    "BitsPerSample", "Number of Bits Per Component", NULL },
	{ 0x0103, TIFF_SHORT, 1,  ED_IMG,
	    "Compression", "Compression Scheme", compresss },
	{ 0x0106, TIFF_SHORT, 1,  ED_IMG,
	    "PhotometricInterpretation", "Pixel Composition", pixelcomps },
	{ 0x010a, TIFF_UNKN,  0,  ED_UNK,
	    "FillOrder", NULL, NULL },
	{ 0x010d, TIFF_UNKN,  0,  ED_UNK,
	    "DocumentName", NULL, NULL },
	{ 0x010e, TIFF_ASCII, 0,  ED_UNK,
	    "ImageDescription", "Title", NULL },
	{ 0x010f, TIFF_ASCII, 0,  ED_CAM,
	    "Make", "Equipment Make", NULL },
	{ 0x0110, TIFF_ASCII, 0,  ED_CAM,
	    "Model", "Camera Model", NULL },
	{ 0x0111, TIFF_UNKN,  0,  ED_VRB,		/* bytes */
	    "StripOffsets", "Image Data Location", NULL },
	{ 0x0112, TIFF_SHORT, 1,  ED_IMG,
	    "Orientation", "Image Orientation", orients },
	{ 0x0115, TIFF_SHORT, 1,  ED_VRB,
	    "SamplesPerPixel", "Number of Components", NULL },
	{ 0x0116, TIFF_UNKN,  1,  ED_VRB,		/* rows */
	    "RowsPerStrip", "Number of Rows Per Strip", NULL },
	{ 0x0117, TIFF_UNKN,  0,  ED_VRB,		/* bytes */
	    "StripByteCounts", "Bytes per Compressed Strip", NULL },
	{ 0x011a, TIFF_RTNL,  1,  ED_IMG,		/* dp[i|cm] */
	    "XResolution", "Horizontal Resolution", NULL },
	{ 0x011b, TIFF_RTNL,  1,  ED_IMG,		/* dp[i|cm] */
	    "YResolution", "Vertical Resolution", NULL },
	{ 0x011c, TIFF_SHORT, 1,  ED_IMG,
	    "PlanarConfiguration", "Image Data Arrangement", planarconfigs },
	{ 0x0128, TIFF_SHORT, 1,  ED_VRB,
	    "ResolutionUnit", "Resolution Unit", resunits },
	{ 0x012d, TIFF_SHORT, 0,  ED_VRB,
	    "TransferFunction", "Transfer Function", NULL },
	{ 0x0131, TIFF_ASCII, 0,  ED_CAM,
	    "Software", "Camera Software", NULL },
	{ 0x0132, TIFF_ASCII, 20, ED_IMG,
	    "DateTime", "Image Created", NULL },
	{ 0x013b, TIFF_ASCII, 0,  ED_CAM,
	    "Artist", "Photographer", NULL },
	{ 0x013e, TIFF_RTNL,  2,  ED_IMG,
	    "WhitePoint", "White Point Chromaticity", NULL },
	{ 0x013f, TIFF_RTNL,  6,  ED_VRB,
	    "PrimaryChromaticities", "Chromaticities of Primary Colors", NULL },
	{ 0x0156, TIFF_UNKN,  0,  ED_UNK,
	    "TransferRange", NULL, NULL },
	{ 0x0200, TIFF_UNKN,  0,  ED_UNK,
	    "JPEGProc", NULL, NULL },
	{ 0x0201, TIFF_LONG,  1,  ED_VRB,
	    "JPEGInterchangeFormat", "Offset to JPEG SOI", NULL },
	{ 0x0202, TIFF_LONG,  1,  ED_VRB,		/* bytes */
	    "JPEGInterchangeFormatLength", "Bytes of JPEG Data", NULL },
	{ 0x0211, TIFF_RTNL,  3,  ED_VRB,
	    "YCbCrCoefficients", "Color Space Xform Matrix Coeff's", NULL },
	{ 0x0212, TIFF_SHORT, 2,  ED_VRB,
	    "YCbCrSubSampling", "Chrominance Comp Samp Ratio", chromratios },
	{ 0x0213, TIFF_SHORT, 1,  ED_VRB,
	    "YCbCrPositioning", "Chrominance Comp Positioning", chrompos },
	{ 0x0214, TIFF_RTNL,  6,  ED_VRB,
	    "ReferenceBlackWhite", "Black and White Ref Point Values", NULL },
	{ 0x828d, TIFF_UNKN,  0,  ED_UNK,
	    "CFARepeatPatternDim", NULL, NULL },
	{ 0x828e, TIFF_UNKN,  0,  ED_UNK,
	    "CFAPattern", NULL, NULL },
	{ 0x828f, TIFF_UNKN,  0,  ED_UNK,
	    "BatteryLevel", NULL, NULL },
	{ 0x8298, TIFF_ASCII, 0,  ED_UNK,
	    "Copyright", "Copyright", NULL },
	{ 0x829a, TIFF_RTNL,  1,  ED_IMG,		/* s */
	    "ExposureTime", "Exposure Time", NULL },
	{ 0x829d, TIFF_RTNL,  1,  ED_IMG,
	    "FNumber", "F-Number", NULL },
	{ 0x83bb, TIFF_UNKN,  0,  ED_UNK,
	    "IPTC/NAA", NULL, NULL },
	{ 0x8769, TIFF_LONG,  1,  ED_VRB,
	    "ExifOffset", "Exif IFD Pointer", NULL },
	{ 0x8773, TIFF_UNKN,  0,  ED_UNK,
	    "InterColorProfile", NULL, NULL },
	{ 0x8822, TIFF_SHORT, 1,  ED_IMG,
	    "ExposureProgram", "Exposure Program", expprogs },
	{ 0x8824, TIFF_ASCII, 0,  ED_CAM,
	    "SpectralSensitivity", "Spectral Sensitivity", NULL },
	{ 0x8825, TIFF_LONG,  1,  ED_UNK,
	    "GPSInfo", "GPS Info IFD Pointer", NULL },
	{ 0x8827, TIFF_SHORT, 0,  ED_IMG,
	    "ISOSpeedRatings", "ISO Speed Rating", NULL },
	{ 0x8828, TIFF_UNDEF, 0,  ED_CAM,
	    "OECF", "Opto-Electric Conversion Factor", NULL },
	{ 0x9000, TIFF_UNDEF, 4,  ED_VRB,
	    "ExifVersion", "Exif Version", NULL },
	{ 0x9003, TIFF_ASCII, 20, ED_VRB,
	    "DateTimeOriginal", "Image Generated", NULL },
	{ 0x9004, TIFF_ASCII, 20, ED_VRB,
	    "DateTimeDigitized", "Image Digitized", NULL },
	{ 0x9101, TIFF_UNDEF, 4,  ED_VRB,
	    "ComponentsConfiguration", "Meaning of Each Comp", compconfig },
	{ 0x9102, TIFF_RTNL,  1,  ED_VRB,
	    "CompressedBitsPerPixel", "Image Compression Mode", NULL },
	{ 0x9201, TIFF_SRTNL, 1,  ED_IMG,		/* s */
	    "ShutterSpeedValue", "Shutter Speed", NULL },
	{ 0x9202, TIFF_RTNL,  1,  ED_IMG,
	    "ApertureValue", "Lens Aperture", NULL },
	{ 0x9203, TIFF_SRTNL, 1,  ED_IMG,
	    "BrightnessValue", "Brightness", NULL },
	{ 0x9204, TIFF_SRTNL, 1,  ED_IMG,
	    "ExposureBiasValue", "Exposure Bias", NULL },
	{ 0x9205, TIFF_RTNL,  1,  ED_PAS,
	    "MaxApertureValue", "Maximum Lens Aperture", NULL },
	{ 0x9206, TIFF_RTNL,  1,  ED_IMG,		/* m */
	    "SubjectDistance", "Subject Distance", NULL },
	{ 0x9207, TIFF_SHORT, 1,  ED_IMG,
	    "MeteringMode", "Metering Mode", metermodes },
	{ 0x9208, TIFF_SHORT, 1,  ED_IMG,
	    "LightSource", "Light Source", lightsrcs },
	{ 0x9209, TIFF_SHORT, 1,  ED_IMG,
	    "Flash", "Flash", NULL },
	{ 0x920a, TIFF_RTNL,  1,  ED_IMG,		/* mm */
	    "FocalLength", "Focal Length", NULL },
	{ 0x9214, TIFF_SHORT,  0,  ED_VRB,
	    "SubjectArea", "Subject Area", NULL },
	{ 0x927c, TIFF_UNDEF, 0,  ED_UNK,
	    "MakerNote", "Manufacturer Notes", NULL },
	{ 0x9286, TIFF_UNDEF, 0,  ED_UNK,
	    "UserComment", "Comment", NULL },
	{ 0x9290, TIFF_ASCII, 0,  ED_VRB,
	    "SubsecTime", "DateTime Second Fraction", NULL },
	{ 0x9291, TIFF_ASCII, 0,  ED_VRB,
	    "SubsecTimeOrginal", "DateTimeOriginal Second Fraction", NULL },
	{ 0x9292, TIFF_ASCII, 0,  ED_VRB,
	    "SubsecTimeDigitized", "DateTimeDigitized Second Fraction", NULL },
	{ 0xa000, TIFF_UNDEF, 4,  ED_UNK,
	    "FlashPixVersion", "Supported FlashPix Version", NULL },
	{ 0xa001, TIFF_SHORT, 1,  ED_IMG,
	    "ColorSpace", "Color Space Information", colorspcs },
	{ 0xa002, TIFF_UNKN,  1,  ED_IMG,		/* pixels */
	    "PixelXDimension", "Image Width", NULL },
	{ 0xa003, TIFF_UNKN,  1,  ED_IMG,		/* pixels */
	    "PixelYDimension", "Image Height", NULL },
	{ 0xa004, TIFF_ASCII, 13, ED_UNK,
	    "RelatedSoundFile", "Related Audio File", NULL },
	{ 0xa005, TIFF_LONG,  1,  ED_UNK,
	    "InteroperabilityOffset", "Interoperability IFD Pointer", NULL },
	{ 0xa20b, TIFF_RTNL,  1,  ED_IMG,		/* bcps */
	    "FlashEnergy", "Flash Energy", NULL },
	{ 0xa20c, TIFF_UNDEF, 0,  ED_VRB,
	    "SpatialFrequencyResponse", "Spatial Frequency Response", NULL },
	{ 0xa20e, TIFF_RTNL,  1,  ED_VRB,		/* dp[i|cm] */
	    "FocalPlaneXResolution", "Focal Plane Horiz Resolution", NULL },
	{ 0xa20f, TIFF_RTNL,  1,  ED_VRB,		/* dp[i|cm] */
	    "FocalPlaneYResolution", "Focal Plane Vert Resolution", NULL },
	{ 0xa210, TIFF_SHORT, 1,  ED_VRB,
	    "FocalPlaneResolutionUnit", "Focal Plane Res Unit", resunits },
	{ 0xa214, TIFF_SHORT, 2,  ED_VRB,
	    "SubjectLocation", "Subject Location", NULL },
	{ 0xa215, TIFF_RTNL,  1,  ED_IMG,
	    "ExposureIndex", "Exposure Index", NULL },
	{ 0xa217, TIFF_SHORT, 1,  ED_CAM,
	    "SensingMethod", "Sensing Method", imgsensors },
	{ 0xa300, TIFF_UNDEF, 1,  ED_VRB,
	    "FileSource", "File Source", NULL },
	{ 0xa301, TIFF_UNDEF, 1,  ED_VRB,
	    "SceneType", "Scene Type", scenetypes },
	{ 0xa302, TIFF_UNDEF, 0,  ED_CAM,
	    "CFAPattern", "Color Filter Array Pattern", NULL },
	{ 0xa401, TIFF_SHORT, 1,  ED_IMG,
	    "CustomRendered", "Rendering", customrend },
	{ 0xa402, TIFF_SHORT, 1,  ED_IMG,
	    "ExposureMode", "Exposure Mode", expmode },
	{ 0xa403, TIFF_SHORT, 1,  ED_IMG,
	    "WhiteBalance", "White Balance", whitebal },
	{ 0xa404, TIFF_RTNL,  1,  ED_IMG,
	    "DigitalZoomRatio", "Digital Zoom Ratio", NULL },
	{ 0xa405, TIFF_SHORT, 1,  ED_PAS,		/* mm */
	    "FocalLenIn35mmFilm", "Focal Length (35mm Equiv)", NULL },
	{ 0xa406, TIFF_SHORT, 1,  ED_IMG,
	    "SceneCaptureType", "Scene Capture Type", scenecaptypes },
	{ 0xa407, TIFF_SHORT, 1,  ED_IMG,		/* XXX typo in spec? */
	    "GainControl", "Gain Control", gainctrl },
	{ 0xa408, TIFF_SHORT, 1,  ED_IMG,
	    "Contrast", "Contrast", processrange },
	{ 0xa409, TIFF_SHORT, 1,  ED_IMG,
	    "Saturation", "Saturation", saturate },
	{ 0xa40a, TIFF_SHORT, 1,  ED_IMG,
	    "Sharpness", "Sharpness", processrange },
	{ 0xa40b, TIFF_UNDEF, 0,  ED_UNK,
	    "DeviceSettingDescr", "Device Settings", NULL },
	{ 0xa40c, TIFF_SHORT, 1,  ED_IMG,
	    "SubjectDistRange", "Subject Distance Range", subjdist },
	{ 0xa420, TIFF_ASCII, 33, ED_IMG,
	    "ImageUniqueID", "Unique Image ID", NULL },
	{ 0xa500, TIFF_RTNL,  1,  ED_UNK,
	    "GammaCoefficient", "Gamma Coefficient", NULL },
	{ 0xffff, TIFF_UNKN,  0,  ED_UNK,
	    "Unknown", NULL, NULL },
};
