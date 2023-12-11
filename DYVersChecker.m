//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by d on 2005.07.29.

#import "DYVersChecker.h"

void DYVersCheckForUpdateAndNotify(BOOL notify) {
	NSString *bundleVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
	NSString *url = @"https://blyt.net/phxslides/vers.txt";
	NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
	NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:nil delegateQueue:NSOperationQueue.mainQueue];
	[[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSAlert *alert = [[NSAlert alloc] init];
		BOOL newVersion = NO;
		if (error) {
			if (notify)
				alert.informativeText = NSLocalizedString(@"Could not check for update - unable to connect to server.",@"");
		} else if (((NSHTTPURLResponse *)response).statusCode != 200) {
			if (notify)
				alert.informativeText = NSLocalizedString(@"Could not check for update - an error occurred while connecting to the server.",@"");
		} else {
			NSString *responseText = [[NSString alloc] initWithData:data encoding:NSMacOSRomanStringEncoding];
			NSScanner *scanner = [NSScanner scannerWithString:responseText];
			NSInteger __block latestBuild = 0;
			// the response should be a number followed by pairs of system version numbers and build numbers, systems ordered descending
			// "x.y.z w" means "systems before x.y.z require build w or less"
			if (!([scanner scanInteger:&latestBuild]) || latestBuild == 0) {
				if (notify)
					alert.informativeText = NSLocalizedString(@"Could not check for update - an error occurred with the server's response.",@"");
			} else {
				NSInteger currentBuild = bundleVersion.integerValue;
				NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\.(\\d+)\\.(\\d+) (\\d+)" options:0 error:NULL];
				[re enumerateMatchesInString:responseText options:0 range:NSMakeRange(0, responseText.length) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
					NSOperatingSystemVersion w;
					w.majorVersion = [responseText substringWithRange:[result rangeAtIndex:1]].integerValue;
					w.minorVersion = [responseText substringWithRange:[result rangeAtIndex:2]].integerValue;
					w.patchVersion = [responseText substringWithRange:[result rangeAtIndex:3]].integerValue;
					if (![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:w]) {
						latestBuild = [responseText substringWithRange:[result rangeAtIndex:4]].integerValue;
					}
				}];
				if (latestBuild > currentBuild) {
					newVersion = YES;
					alert.messageText = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"];
					alert.informativeText = NSLocalizedString(@"A new version of Phoenix Slides is available.",@"");
					[alert addButtonWithTitle:NSLocalizedString(@"More Info", @"")];
					[alert addButtonWithTitle:NSLocalizedString(@"Not Now", @"")];
					if ([alert runModal] == NSAlertFirstButtonReturn)
						[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://blyt.net/phxslides/"]];
				} else if (notify) {
					alert.messageText = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"];
					alert.informativeText = NSLocalizedString(@"You have the latest version of Phoenix Slides.",@"");
				}
				[NSUserDefaults.standardUserDefaults setDouble:NSDate.timeIntervalSinceReferenceDate
														  forKey:@"lastVersCheckTime"];
			}
		}
		if (notify && !newVersion)
			[alert runModal];
	}] resume];
}
