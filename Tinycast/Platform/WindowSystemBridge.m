#import "WindowSystemBridge.h"
#import <AppKit/AppKit.h>
#import <dlfcn.h>

@interface NSObject (ManagedSpaceOperation)
- (instancetype)initWithWindows:(NSArray<NSNumber *> *)windows spaceID:(uint64_t)spaceID;
- (void)performWithWMBridgeDelegate;
@end

typedef int (*MainConnection)(void);
typedef CFArrayRef (*ManagedDisplays)(int);
typedef CFArrayRef (*WindowSpaces)(int, int, CFArrayRef);
typedef AXError (*AXWindowID)(AXUIElementRef, CGWindowID *);

static void *SkyLight(void) {
    static void *framework;
    if (!framework) {
        framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW);
    }
    return framework;
}

uint64_t TCCurrentManagedSpace(CFStringRef displayUUID) {
    void *framework = SkyLight();
    if (!framework) return 0;
    MainConnection connection = dlsym(framework, "SLSMainConnectionID");
    ManagedDisplays displays = dlsym(framework, "SLSCopyManagedDisplaySpaces");
    if (!connection || !displays) return 0;
    CFArrayRef listing = displays(connection());
    if (!listing) return 0;
    NSArray<NSDictionary *> *managed = CFBridgingRelease(listing);
    for (NSDictionary *display in managed) {
        NSString *identifier = display[@"Display Identifier"];
        if ([identifier caseInsensitiveCompare:(__bridge NSString *)displayUUID] == NSOrderedSame) {
            return [display[@"Current Space"][@"id64"] unsignedLongLongValue];
        }
    }
    return 0;
}

NSArray<NSNumber *> *TCWindowSpaceIDs(CGWindowID windowID) {
    void *framework = SkyLight();
    if (!framework) return nil;
    MainConnection connection = dlsym(framework, "SLSMainConnectionID");
    WindowSpaces spaces = dlsym(framework, "SLSCopySpacesForWindows");
    if (!connection || !spaces) return nil;
    NSArray *windows = @[@(windowID)];
    CFArrayRef listing = spaces(connection(), 7, (__bridge CFArrayRef)windows);
    return listing ? CFBridgingRelease(listing) : nil;
}

NSDictionary<NSNumber *, NSNumber *> *TCSpaceDisplayIDs(void) {
    void *framework = SkyLight();
    if (!framework) return nil;
    MainConnection connection = dlsym(framework, "SLSMainConnectionID");
    ManagedDisplays displays = dlsym(framework, "SLSCopyManagedDisplaySpaces");
    if (!connection || !displays) return nil;
    CFArrayRef listing = displays(connection());
    if (!listing) return nil;
    NSMutableDictionary<NSNumber *, NSNumber *> *mapping = [NSMutableDictionary dictionary];
    for (NSDictionary *display in CFBridgingRelease(listing)) {
        CFUUIDRef uuid = CFUUIDCreateFromString(nil, (__bridge CFStringRef)display[@"Display Identifier"]);
        if (!uuid) continue;
        CGDirectDisplayID screenID = CGDisplayGetDisplayIDFromUUID(uuid);
        CFRelease(uuid);
        if (screenID == kCGNullDirectDisplay) continue;
        for (NSDictionary *space in display[@"Spaces"]) {
            mapping[space[@"id64"]] = @(screenID);
        }
    }
    return mapping;
}

bool TCMoveWindowToSpace(CGWindowID windowID, uint64_t spaceID) {
    if (!SkyLight()) return false;
    Class operationClass = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
    if (!operationClass) return false;
    NSObject *operation = [[operationClass alloc] initWithWindows:@[@(windowID)] spaceID:spaceID];
    if (!operation) return false;
    [operation performWithWMBridgeDelegate];
    return true;
}

bool TCWindowIsInSpace(CGWindowID windowID, uint64_t spaceID) {
    return [TCWindowSpaceIDs(windowID) containsObject:@(spaceID)];
}

CGWindowID TCWindowIDForAXElement(AXUIElementRef window) {
    AXWindowID identifier = dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
    CGWindowID windowID = 0;
    return identifier && identifier(window, &windowID) == kAXErrorSuccess ? windowID : 0;
}
