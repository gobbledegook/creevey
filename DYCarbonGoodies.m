//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//
//  DYCarbonGoodies.m
//  creevey
//
//  Created by d on 2005.04.03.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "DYCarbonGoodies.h"
#import <Carbon/Carbon.h>

NSString *ResolveAliasToPath(NSString *path) {
	NSString *resolvedPath = nil;
	CFURLRef url = CFURLCreateWithFileSystemPath(NULL /*allocator*/, (CFStringRef)path,
												 kCFURLPOSIXPathStyle, NO /*isDirectory*/);
	if (url == NULL) return nil;
	FSRef fsRef;
	if (CFURLGetFSRef(url, &fsRef)) {
		Boolean targetIsFolder, wasAliased;
		if (FSResolveAliasFileWithMountFlags(&fsRef,
											 true /*resolveAliasChains*/,
											 &targetIsFolder,
											 &wasAliased,
											 kResolveAliasFileNoUI) == noErr
			&& wasAliased) {
			CFURLRef resolvedUrl = CFURLCreateFromFSRef(NULL, &fsRef);
			if (resolvedUrl != NULL) {
				CFStringRef thePath = CFURLCopyFileSystemPath(resolvedUrl, kCFURLPOSIXPathStyle);
				resolvedPath = [NSString stringWithString:(NSString*)thePath];
				CFRelease(thePath);
				CFRelease(resolvedUrl);
			}
		}
	}
	CFRelease(url);
	if (resolvedPath == nil) return path;
	return resolvedPath;
}


OSStatus GetFinderPSN(ProcessSerialNumber *psn) {
	ProcessInfoRec          info;
	OSStatus                err = noErr;
	
	psn->lowLongOfPSN       = 0;
	psn->highLongOfPSN      = kNoProcess;
	info.processInfoLength  = sizeof(ProcessInfoRec);
	info.processName        = nil;
	info.processAppSpec     = nil;
	
	do {
		err = GetNextProcess(psn);
		if (err == noErr)
			GetProcessInformation(psn, &info);
	} while (((info.processSignature != 'MACS') || (info.processType != 'FNDR')) && (err == noErr));
	
	check_noerr_string(err, "GetFinderPSN failed");
	return err;
}

OSStatus BringFinderToFront(void) {
	OSStatus            err;
	ProcessSerialNumber finder;

	err = GetFinderPSN(&finder);
	if (err == noErr)
		err = SetFrontProcess(&finder);
	check_noerr_string(err, "BringFinderToFront failed");
	return err;
}


// horrors
// see Apple Event Manager reference
void RevealItemsInFinder(NSArray *theFiles)
{
	OSErr err;
	// prepare descList
	AEDescList descList;
	err = AECreateList(NULL,NULL,false,&descList);
	if (err) return;
	
	int numFiles = [theFiles count];
	int i, successfulFiles = 0;
	CFURLRef url;
	FSRef fsRef;
	AliasHandle alias;
	for (i=0; i<numFiles; ++i) {
		url = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)[theFiles objectAtIndex:i],
													 kCFURLPOSIXPathStyle, NO /*isDirectory*/);
		if (url == NULL) return;
		alias = NULL;
		if (CFURLGetFSRef(url, &fsRef) && FSNewAlias(nil, &fsRef, &alias) == noErr) {
			AEPutPtr(&descList,0,typeAlias,*alias,GetHandleSize((Handle)alias));
			++successfulFiles;
		}
		if (alias)  DisposeHandle((Handle)alias);
		CFRelease(url);
	}
	
	// prepare apple event
	AppleEvent theAppleEvent;
	AEBuildError tAEBuildError;
	AppleEvent replyAppleEvent;
	OSType finderSig = 'MACS';
	err = AEBuildAppleEvent(kAEMiscStandards, kAEMakeObjectsVisible,
							typeApplSignature, &finderSig, sizeof(OSType),
							kAutoGenerateReturnID, kAnyTransactionID,
							&theAppleEvent, &tAEBuildError,
							"'----':(@)", &descList);

	require_noerr(err, Bail);
	
	// send it
	err = AESend(&theAppleEvent, &replyAppleEvent, kAENoReply,
				 kAENormalPriority, kAEDefaultTimeout, NULL, NULL);
	if (successfulFiles && err == noErr)
		BringFinderToFront();
	
Bail:
	AEDisposeDesc(&descList);
	if (theAppleEvent.dataHandle)  AEDisposeDesc(&theAppleEvent);
	
	return;
}

/*
 err = AESendFinderFSSpec(kAEMiscStandards, kAEMakeObjectsVisible, &folder);
 
 
 if (err == noErr)
 err = BringFinderToFront();
 
 
 
 ---------------
 
 
 enum { kFinderCreator = 'MACS' };
 
 OSStatus AESendFinderFSSpec(AEEventClass eventClass, AEEventID eventID, const FSSpec *file) // bmp 1/27/2004 4.2a7 AMDOCS override this from MOSH to use Aliases to talk to Finder
 {
	 OSStatus err = noErr;
	 
	 
	 AEDesc      finderAddress   = {typeNull, NULL};
	 AppleEvent  appleEvent      = {typeNull, NULL};
	 AppleEvent  reply           = {typeNull, NULL};
	 AliasHandle fileAlias       = NULL;
	 
	 
	 DescType        finderCreator   = kFinderCreator;
	 
	 err = AECreateDesc(typeApplSignature, &finderCreator, sizeof(DescType), &finderAddress);
	 
	 
	 if (err == noErr)
		 err = AECreateAppleEvent(eventClass,
								  eventID,
								  &finderAddress,
								  kAutoGenerateReturnID,
								  kAnyTransactionID,
								  &appleEvent);
	 
	 
	 if (err == noErr)
	 {
		 err = NewAlias(NULL, file, &fileAlias);
		 
		 if (err == noErr)
			 err = AEPutParamPtr(&appleEvent, keyDirectObject, typeAlias, *fileAlias, GetHandleSize((Handle) fileAlias));
	 }
	 
	 if (err == noErr)
		 err = AESend(&appleEvent, &reply, kAENoReply + kAEAlwaysInteract + kAECanSwitchLayer, kAENormalPriority, kAEDefaultTimeout, NULL, NULL);
	 
	 
	 AEDisposeDesc(&finderAddress);
	 AEDisposeDesc(&appleEvent);
	 AEDisposeDesc(&reply);
	 
	 
	 if (fileAlias != NULL)
		 DisposeHandle((Handle) fileAlias);
	 
	 
	 return err;
 }
 */

BOOL FileIsInvisible(NSString *path) {
	CFURLRef url = CFURLCreateWithFileSystemPath(NULL /*allocator*/, (CFStringRef)path,
												 kCFURLPOSIXPathStyle, NO /*isDirectory*/);
	if (url == NULL) return NO;
	LSItemInfoRecord info;
	OSStatus err = LSCopyItemInfoForURL (url, kLSRequestBasicFlagsOnly, &info);
	CFRelease(url);
	if (err) return NO;
	
	return (info.flags & kLSItemInfoIsInvisible) != 0;
	/* UNTESTED CODE below, from mailing list
	FSRef                possibleInvisibleFile; 
	FSCatalogInfo        catalogInfo; 
	BOOL                isHidden = NO; 
	NSString            *fullFile = some_path_to_a_file; 
	errStat = FSPathMakeRef([fullFile fileSystemRepresentation], 
							&possibleInvisibleFile, nil); 
	FSGetCatalogInfo(&possibleInvisibleFile, kFSCatInfoFinderInfo, 
					 &catalogInfo,  nil, nil, nil); 
	isHidden |= (((FileInfo*)catalogInfo.finderInfo)->finderFlags & 
				 kIsInvisible) ? 1 : 0; 
	
	OR
	
    NSString * filePath = path  // obviously, this line is pseudocode
    FSSpec fsSpec = [filePath getFSSpec]; 
    FInfo fInfo; 

    OSStatus err = FSpGetFInfo(&fsSpec, &fInfo);
    if(err) 
        return NO;
    bool invisibleFlag = fInfo.fdFlags & kIsInvisible; 
    BOOL invisibleName = [[filePath lastPathComponent] hasPrefix:@"."];
    bool fileVisible = !(invisibleFlag && invisibleName);
	*/
	
}

// code below lifte from DeskPictAppDockMenu

// Setting the desktop picture involves a lot of Apple Event and Carbon code.
// It's all self-contained in this one function.  This Apple Event isn't guarrenteed to
// work forever, and real APIs to set the desktop picture should be coming down the road,
// but in the meantime this is how you do it.
OSErr SetDesktopPicture(NSString *picturePath,SInt32 pIndex)
{
    AEDesc tAEDesc = {typeNull, nil};	//	always init AEDescs
    OSErr		anErr = noErr;
    AliasHandle		aliasHandle=nil;
    FSRef		pictRef;
    OSStatus		status;
	
	// Someday pIndex will hopefully determine on which monitor to set the desktop picture.
	// This doesn't work in Mac OS X right now, so we don't do anything with the parameter.
#pragma unused (pIndex)
	
    // Let's make an FSRef from the NSString picture path that was passed in
    status=FSPathMakeRef([picturePath fileSystemRepresentation],&pictRef,NULL);
	
    // Now we create an alias to the picture from that FSRef
    if (status==noErr)
		anErr = FSNewAlias( nil, &pictRef, &aliasHandle);
    
    if ( noErr == anErr  &&  aliasHandle == nil )
        anErr = paramErr;
    
    // Now we create an AEDesc containing the alias to the picture
    if ( noErr == anErr )
    {
        char	handleState = HGetState( (Handle) aliasHandle );
        HLock( (Handle) aliasHandle);
        anErr = AECreateDesc( typeAlias, *aliasHandle, GetHandleSize((Handle) aliasHandle), &tAEDesc);
        HSetState( (Handle) aliasHandle, handleState );
        DisposeHandle( (Handle)aliasHandle );
    }
    if (noErr == anErr)
    {
        // Now we need to build the actual Apple Event that we're going to send the Finder
        AppleEvent tAppleEvent;
        OSType sig = 'MACS'; // The app signature for the Finder
        AEBuildError tAEBuildError;
        anErr = AEBuildAppleEvent(kAECoreSuite,kAESetData,typeApplSignature,&sig,sizeof(OSType),
                                  kAutoGenerateReturnID,kAnyTransactionID,&tAppleEvent,&tAEBuildError,
                                  "'----':'obj '{want:type(prop),form:prop,seld:type('dpic'),from:'null'()},data:(@)",&tAEDesc);
		
        // Finally we can go ahead and send the Apple Event using AESend                          
        if (noErr == anErr)
        {
            AppleEvent    theReply = {typeNull, nil};
            anErr = AESend(&tAppleEvent,&theReply,kAENoReply,kAENormalPriority,kNoTimeOut,nil,nil);
            AEDisposeDesc(&tAppleEvent);    // Always dispose ASAP
        }
    }
    return anErr;
}