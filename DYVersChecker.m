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

void DYVersCheckForUpdateAndNotify(BOOL notify) {
	SInt32 v1, v2, v3;
	GetSystemVersion(&v1, &v2, &v3);
	id bundleVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
	NSString *url = [NSString stringWithFormat:@"http://blyt.net/cgi-bin/vers.cgi?v=%@&s=%i&t=%i&u=%i", bundleVersion, v1, v2, v3];
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
			[scanner setCharactersToBeSkipped:nil]; // don't skip whitespace
			NSInteger latestBuild = 0;
			// the response should be a number followed by a single space
			if (!([scanner scanInteger:&latestBuild] && [scanner scanString:@" " intoString:NULL] && [scanner isAtEnd]) || latestBuild == 0) {
				if (notify)
					NSRunAlertPanel(nil,NSLocalizedString(@"Could not check for update - an error occurred while connecting to the server.",@""),nil,nil,nil);
			} else {
				NSInteger currentBuild = [bundleVersion integerValue];
				if (latestBuild > currentBuild) {
					if (NSRunInformationalAlertPanel([[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"],
													 NSLocalizedString(@"A new version of Phoenix Slides is available.", @""),
													 NSLocalizedString(@"More Info", @""),
													 NSLocalizedString(@"Not Now", @""),nil)
						== NSAlertDefaultReturn)
						[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://blyt.net/phxslides/"]];
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
