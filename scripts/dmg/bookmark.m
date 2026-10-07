#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>

// Use macOS' own file-reference encoders. The Python-generated alias in the
// reference project's older dmg-builder failed to resolve on newer Finder.
// This writes file metadata only; it does not control Finder or require GUI access.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 4) { fprintf(stderr, "usage: bookmark <background> <alias-output> <bookmark-output>\n"); return 2; }
        NSString *path = [NSString stringWithUTF8String:argv[1]];
        NSURL *url = [NSURL fileURLWithPath:path];
        NSError *error = nil;
        NSData *bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationSuitableForBookmarkFile
                       includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
        if (!bookmark) { NSLog(@"Bookmark failed: %@", error); return 1; }
        AliasHandle alias = NULL;
        OSStatus status = FSNewAliasFromPath(NULL, argv[1], 0, &alias, NULL);
        if (status != noErr || !alias) { fprintf(stderr, "Alias creation failed: %d\n", (int)status); return 1; }
        NSData *record = [NSData dataWithBytes:*alias length:GetHandleSize((Handle)alias)];
        DisposeHandle((Handle)alias);
        if (![record writeToFile:[NSString stringWithUTF8String:argv[2]] options:NSDataWritingAtomic error:&error] ||
            ![bookmark writeToFile:[NSString stringWithUTF8String:argv[3]] options:NSDataWritingAtomic error:&error]) {
            NSLog(@"Writing references failed: %@", error); return 1;
        }
    }
    return 0;
}
