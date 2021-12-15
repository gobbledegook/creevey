//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  DYVersChecker.m
//  creevey
//  Created by d on 2005.07.29.

#import "DYVersChecker.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
static void GetSystemVersion(SInt32 *outVersMajor, SInt32 *outVersMinor, SInt32 *outVersBugFix) {
	Gestalt(gestaltSystemVersionMajor, outVersMajor);
	Gestalt(gestaltSystemVersionMinor, outVersMinor);
	Gestalt(gestaltSystemVersionBugFix, outVersBugFix);
}
#pragma GCC diagnostic pop

// replace with isOperatingSystemAtLeastVersion when we drop 10.9 support
static BOOL SystemVersionLessThan(NSInteger a1, NSInteger a2, NSInteger a3, NSInteger b1, NSInteger b2, NSInteger b3) {
	if (a1 == b1) {
		if (a2 == b2) return a3 < b3;
		return a2 < b2;
	}
	return a1 < b1;
}

void DYVersCheckForUpdateAndNotify(BOOL notify) {
	SInt32 v1, v2, v3;
	GetSystemVersion(&v1, &v2, &v3);
	id bundleVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
	NSString *url = @"https://blyt.net/phxslides/vers.txt";
	NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:nil delegateQueue:[NSOperationQueue mainQueue]];
	[[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		if (error) {
			if (notify)
				NSRunAlertPanel(nil,NSLocalizedString(@"Could not check for update - unable to connect to server.",@""),nil,nil,nil);
		} else if ([(NSHTTPURLResponse *)response statusCode] != 200) {
			if (notify)
				NSRunAlertPanel(nil,NSLocalizedString(@"Could not check for update - an error occurred while connecting to the server.",@""),nil,nil,nil);
		} else {
			NSString *responseText = [[[NSString alloc] initWithData:data encoding:NSMacOSRomanStringEncoding] autorelease];
			NSScanner *scanner = [NSScanner scannerWithString:responseText];
			NSInteger __block latestBuild = 0;
			// the response should be a number followed by pairs of system version numbers and build numbers, systems ordered descending
			// "x.y.z w" means "systems before x.y.z require build w or less"
			if (!([scanner scanInteger:&latestBuild]) || latestBuild == 0) {
				if (notify)
					NSRunAlertPanel(nil,NSLocalizedString(@"Could not check for update - an error occurred with the server's response.",@""),nil,nil,nil);
			} else {
				NSInteger currentBuild = [bundleVersion integerValue];
				NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\.(\\d+)\\.(\\d+) (\\d+)" options:0 error:NULL];
				[re enumerateMatchesInString:responseText options:0 range:NSMakeRange(0, [responseText length]) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
					NSInteger w1 = [[responseText substringWithRange:[result rangeAtIndex:1]] integerValue];
					NSInteger w2 = [[responseText substringWithRange:[result rangeAtIndex:2]] integerValue];
					NSInteger w3 = [[responseText substringWithRange:[result rangeAtIndex:3]] integerValue];
					if (SystemVersionLessThan(v1, v2, v3, w1, w2, w3)) {
						latestBuild = [[responseText substringWithRange:[result rangeAtIndex:4]] integerValue];
					}
				}];
				if (latestBuild > currentBuild) {
					if (NSRunInformationalAlertPanel([[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"],
													 NSLocalizedString(@"A new version of Phoenix Slides is available.", @""),
													 NSLocalizedString(@"More Info", @""),
													 NSLocalizedString(@"Not Now", @""),nil)
						== NSAlertDefaultReturn)
						[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://blyt.net/phxslides/"]];
				} else if (notify) {
					NSRunInformationalAlertPanel([[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"],
												 NSLocalizedString(@"You have the latest version of Phoenix Slides.", @""),
												 nil,nil,nil);
				}
				[[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate]
														  forKey:@"lastVersCheckTime"];
			}
		}
	}] resume];
}
