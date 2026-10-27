#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface TCWindowRecord : NSObject

@property (nonatomic, readonly) CGWindowID windowID;
@property (nonatomic, readonly) pid_t processID;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, readonly) CGRect frame;
@property (nonatomic, readonly) int32_t level;
@property (nonatomic, readonly) float alpha;
@property (nonatomic, readonly) uint64_t attributes;
@property (nonatomic, readonly) uint64_t tags;
@property (nonatomic, readonly) uint64_t spaceTypeMask;
@property (nonatomic, readonly, getter=isOrderedIn) BOOL orderedIn;
@property (nonatomic, readonly, getter=isMinimized) BOOL minimized;
@property (nonatomic, readonly, getter=isFullscreen) BOOL fullscreen;
@property (nonatomic, readonly) CGWindowID parentWindowID;
/// An empty list does not prove the window has no Space.
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *spaceIDs;

@end

NSArray<TCWindowRecord *> * _Nullable TCWindowRecords(
    NSArray<NSNumber *> * _Nullable supplementalWindowIDs);
NSNumber * _Nullable TCWindowBelongsToProcess(CGWindowID windowID, pid_t processID);

uint64_t TCCurrentManagedSpace(CFStringRef displayUUID);
NSArray<NSNumber *> * _Nullable TCCurrentSpaceIDs(void);
int32_t TCSpaceType(uint64_t spaceID);
NSArray<NSNumber *> * _Nullable TCWindowSpaceIDs(CGWindowID windowID);
NSDictionary<NSNumber *, NSNumber *> * _Nullable TCSpaceDisplayIDs(void);
bool TCMoveWindowToSpace(CGWindowID windowID, uint64_t spaceID);
bool TCWindowIsInSpace(CGWindowID windowID, uint64_t spaceID);
CGWindowID TCWindowIDForAXElement(AXUIElementRef window);

NS_ASSUME_NONNULL_END
