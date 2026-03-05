//
// clipboard-bridge.m
//
// Background daemon that watches the macOS clipboard and adds the legacy
// «class PNGf» (com.apple.pboard.type.PNGf) pasteboard type when an image
// is present as public.png but missing the legacy type.
//
// This fixes clipboard image pasting in apps that check for «class PNGf»
// (e.g. Claude Code) when images are copied from Chromium/Electron apps
// (Figma, Chrome, VS Code, Slack, Discord, etc.) which only provide public.png.
//

#import <AppKit/NSPasteboard.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#include <stdio.h>
#include <unistd.h>
#include <malloc/malloc.h>

int main(void) {
    @autoreleasepool {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        NSInteger lastCount = [pb changeCount];
        NSPasteboardType pngfType = @"com.apple.pboard.type.PNGf";
        NSPasteboardType publicPng = @"public.png";

        fprintf(stderr, "clipboard-bridge: watching (pid %d)\n", getpid());

        for (;;) {
            usleep(300000); // 300ms

            @autoreleasepool {
                NSInteger count = [pb changeCount];
                if (count == lastCount) continue;
                lastCount = count;

                NSArray<NSPasteboardType> *types = [pb types];
                if (!types) continue;

                BOOL hasImage = [types containsObject:publicPng] ||
                                [types containsObject:NSPasteboardTypeTIFF];
                BOOL hasPNGf = [types containsObject:pngfType];

                if (!hasImage || hasPNGf) continue;

                NSImage *img = [[NSImage alloc] initWithPasteboard:pb];
                if (!img) continue;

                NSData *tiff = [img TIFFRepresentation];
                if (!tiff) continue;

                NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
                if (!rep) continue;

                NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
                                               properties:@{}];
                if (!png) continue;

                // Preserve existing clipboard data
                NSMutableArray *savedTypes = [NSMutableArray array];
                NSMutableArray *savedData = [NSMutableArray array];
                for (NSPasteboardType t in types) {
                    NSData *d = [pb dataForType:t];
                    if (d) {
                        [savedTypes addObject:t];
                        [savedData addObject:d];
                    }
                }

                [pb clearContents];
                for (NSUInteger i = 0; i < savedTypes.count; i++) {
                    [pb setData:savedData[i] forType:savedTypes[i]];
                }
                [pb setData:png forType:pngfType];

                lastCount = [pb changeCount];

                NSSize sz = [img size];
                fprintf(stderr, "clipboard-bridge: added PNGf (%dx%d, %lu bytes)\n",
                        (int)sz.width, (int)sz.height, (unsigned long)[png length]);
            }
            malloc_zone_pressure_relief(NULL, 0);
        }
    }
    return 0;
}
