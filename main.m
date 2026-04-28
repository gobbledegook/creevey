@import Cocoa;

int main(int argc, const char *argv[])
{
	if (NSAppKitVersionNumber < NSAppKitVersionNumber11_5) {
		@autoreleasepool {
			NSApplicationLoad();
			NSAlert *alert = [[NSAlert alloc] init];
			alert.messageText = @"Incompatible System Version";
			alert.informativeText = @"This program requires macOS 11.5 (Big Sur) or later.";
			[alert runModal];
		}
		return 0;
	}
    return NSApplicationMain(argc, argv);
}
