#import "WindowSystemBridge.h"
#import <AppKit/AppKit.h>
#import <dlfcn.h>

@interface TCWindowRecord ()
@property (nonatomic, readwrite) CGWindowID windowID;
@property (nonatomic, readwrite) pid_t processID;
@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, readwrite) CGRect frame;
@property (nonatomic, readwrite) int32_t level;
@property (nonatomic, readwrite) float alpha;
@property (nonatomic, readwrite) uint64_t attributes;
@property (nonatomic, readwrite) uint64_t tags;
@property (nonatomic, readwrite) uint64_t spaceTypeMask;
@property (nonatomic, readwrite, getter=isOrderedIn) BOOL orderedIn;
@property (nonatomic, readwrite, getter=isMinimized) BOOL minimized;
@property (nonatomic, readwrite, getter=isFullscreen) BOOL fullscreen;
@property (nonatomic, readwrite) CGWindowID parentWindowID;
@property (nonatomic, copy, readwrite) NSArray<NSNumber *> *spaceIDs;
@end

@implementation TCWindowRecord
@end

@interface NSObject (ManagedSpaceOperation)
- (instancetype)initWithWindows:(NSArray<NSNumber *> *)windows spaceID:(uint64_t)spaceID;
- (void)performWithWMBridgeDelegate;
@end

typedef int (*MainConnection)(void);
typedef CFArrayRef (*ManagedDisplays)(int);
typedef CFArrayRef (*WindowSpaces)(int, int, CFArrayRef);
typedef int32_t (*SpaceType)(int, uint64_t);
typedef AXError (*AXWindowID)(AXUIElementRef, CGWindowID *);
typedef CFArrayRef (*WindowsInSpaces)(int, int, CFArrayRef, intptr_t, intptr_t *, intptr_t *);
typedef CFTypeRef (*WindowQuery)(int, CFArrayRef, int32_t);
typedef CFTypeRef (*WindowIterator)(CFTypeRef);
typedef bool (*AdvanceWindow)(CFTypeRef);
typedef CGWindowID (*WindowIdentifier)(CFTypeRef);
typedef pid_t (*WindowProcess)(CFTypeRef);
typedef uint64_t (*WindowBits)(CFTypeRef);
typedef int32_t (*WindowLevel)(CFTypeRef);
typedef float (*WindowAlpha)(CFTypeRef);
typedef CGRect (*WindowFrame)(CFTypeRef);
typedef CFStringRef (*WindowTitle)(CFTypeRef);

static void *SkyLight(void) {
    static void *framework;
    if (!framework) {
        framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW);
    }
    return framework;
}

NSArray<TCWindowRecord *> *TCWindowRecords(NSArray<NSNumber *> *supplementalWindowIDs) {
    void *framework = SkyLight();
    if (!framework) return nil;
    MainConnection connection = dlsym(framework, "SLSMainConnectionID");
    ManagedDisplays displays = dlsym(framework, "SLSCopyManagedDisplaySpaces");
    WindowsInSpaces windowsInSpaces = dlsym(framework, "CGSCopyWindowsWithOptionsAndTags");
    WindowQuery query = dlsym(framework, "SLSWindowQueryWindows");
    WindowIterator copyWindows = dlsym(framework, "SLSWindowQueryResultCopyWindows");
    AdvanceWindow advance = dlsym(framework, "SLSWindowIteratorAdvance");
    WindowIdentifier identifier = dlsym(framework, "SLSWindowIteratorGetWindowID");
    WindowIdentifier parent = dlsym(framework, "SLSWindowIteratorGetParentID");
    WindowProcess process = dlsym(framework, "SLSWindowIteratorGetPID");
    WindowBits attributes = dlsym(framework, "SLSWindowIteratorGetAttributes");
    WindowBits tags = dlsym(framework, "SLSWindowIteratorGetTags");
    WindowBits spaceTypeMask = dlsym(framework, "SLSWindowIteratorGetSpaceTypeMask");
    WindowLevel level = dlsym(framework, "SLSWindowIteratorGetLevel");
    WindowAlpha alpha = dlsym(framework, "SLSWindowIteratorGetAlpha");
    WindowFrame frame = dlsym(framework, "SLSWindowIteratorGetBounds");
    WindowTitle title = dlsym(framework, "SLSWindowIteratorCopyTitle");
    if (!connection || !displays || !windowsInSpaces || !query || !copyWindows || !advance
        || !identifier || !parent || !process || !attributes || !tags || !spaceTypeMask
        || !level || !alpha || !frame || !title) return nil;

    int connectionID = connection();
    CFArrayRef listing = displays(connectionID);
    if (!listing) return nil;
    NSArray<NSDictionary *> *managed = CFBridgingRelease(listing);
    NSMutableOrderedSet<NSNumber *> *windowIDs = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary<NSNumber *, NSMutableOrderedSet<NSNumber *> *> *memberships =
        [NSMutableDictionary dictionary];
    NSMutableSet<NSNumber *> *visitedSpaces = [NSMutableSet set];
    for (NSDictionary *display in managed) {
        for (NSDictionary *space in display[@"Spaces"]) {
            NSNumber *spaceID = space[@"id64"];
            if (!spaceID) return nil;
            if ([visitedSpaces containsObject:spaceID]) continue;
            [visitedSpaces addObject:spaceID];
            intptr_t setTags = 0, clearTags = 0;
            CFArrayRef windows = windowsInSpaces(connectionID, 0, (__bridge CFArrayRef)@[spaceID],
                0x7, &setTags, &clearTags);
            if (!windows) return nil;
            NSArray<NSNumber *> *spaceWindowIDs = CFBridgingRelease(windows);
            for (NSNumber *windowID in spaceWindowIDs) {
                [windowIDs addObject:windowID];
                if (!memberships[windowID]) memberships[windowID] = [NSMutableOrderedSet orderedSet];
                [memberships[windowID] addObject:spaceID];
            }
        }
    }
    [windowIDs addObjectsFromArray:supplementalWindowIDs ?: @[]];
    if (windowIDs.count == 0) return @[];

    CFTypeRef result = query(connectionID, (__bridge CFArrayRef)windowIDs.array,
        (int32_t)windowIDs.count);
    if (!result) return nil;
    CFTypeRef iterator = copyWindows(result);
    if (!iterator) { CFRelease(result); return nil; }
    NSMutableArray<TCWindowRecord *> *records = [NSMutableArray array];
    while (advance(iterator)) {
        TCWindowRecord *record = [TCWindowRecord new];
        record.windowID = identifier(iterator);
        record.processID = process(iterator);
        CFStringRef name = title(iterator);
        record.title = name ? CFBridgingRelease(name) : @"";
        record.frame = frame(iterator);
        record.level = level(iterator);
        record.alpha = alpha(iterator);
        record.attributes = attributes(iterator);
        record.tags = tags(iterator);
        record.spaceTypeMask = spaceTypeMask(iterator);
        record.orderedIn = (record.attributes & 0x2) != 0;
        record.minimized = (record.tags & (1ULL << 60)) != 0;
        record.fullscreen = (record.spaceTypeMask & 0x20) != 0;
        record.parentWindowID = parent(iterator);
        record.spaceIDs = memberships[@(record.windowID)].array ?: @[];
        [records addObject:record];
    }
    CFRelease(iterator);
    CFRelease(result);
    return records;
}

NSNumber *TCWindowBelongsToProcess(CGWindowID windowID, pid_t processID) {
    const void *target = (const void *)(uintptr_t)windowID;
    CFArrayRef windowIDs = CFArrayCreate(kCFAllocatorDefault, &target, 1, NULL);
    if (!windowIDs) return nil;
    CFArrayRef descriptions = CGWindowListCreateDescriptionFromArray(windowIDs);
    CFRelease(windowIDs);
    if (!descriptions) return nil;
    NSArray<NSDictionary *> *windows = CFBridgingRelease(descriptions);
    for (NSDictionary *window in windows) {
        if ([window[(__bridge NSString *)kCGWindowNumber] unsignedIntValue] == windowID
            && [window[(__bridge NSString *)kCGWindowOwnerPID] intValue] == processID) return @(YES);
    }
    return @(NO);
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

NSArray<NSNumber *> *TCCurrentSpaceIDs(void) {
    void *framework = SkyLight();
    if (!framework) return nil;
    MainConnection connection = dlsym(framework, "SLSMainConnectionID");
    ManagedDisplays displays = dlsym(framework, "SLSCopyManagedDisplaySpaces");
    if (!connection || !displays) return nil;
    CFArrayRef listing = displays(connection());
    if (!listing) return nil;
    NSMutableOrderedSet<NSNumber *> *spaceIDs = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *display in CFBridgingRelease(listing)) {
        NSNumber *spaceID = display[@"Current Space"][@"id64"];
        if (!spaceID) return nil;
        [spaceIDs addObject:spaceID];
    }
    return spaceIDs.array;
}

int32_t TCSpaceType(uint64_t spaceID) {
    void *framework = SkyLight();
    if (!framework) return -1;
    MainConnection connection = dlsym(framework, "SLSMainConnectionID");
    SpaceType type = dlsym(framework, "SLSSpaceGetType");
    return connection && type ? type(connection(), spaceID) : -1;
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
