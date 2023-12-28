@import Cocoa;

int main(int argc, const char *argv[])
{
	if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_12) {
		@autoreleasepool {
			NSApplicationLoad();
			NSAlert *alert = [[NSAlert alloc] init];
			alert.messageText = @"Incompatible System Version";
			alert.informativeText = @"This program requires macOS 10.13 (High Sierra) or later.";
			[alert runModal];
		}
		return 0;
	}
    return NSApplicationMain(argc, argv);
}
