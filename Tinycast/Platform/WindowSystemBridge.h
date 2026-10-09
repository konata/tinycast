#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

uint64_t TCCurrentManagedSpace(CFStringRef displayUUID);
NSArray<NSNumber *> * _Nullable TCWindowSpaceIDs(CGWindowID windowID);
NSDictionary<NSNumber *, NSNumber *> * _Nullable TCSpaceDisplayIDs(void);
bool TCMoveWindowToSpace(CGWindowID windowID, uint64_t spaceID);
bool TCWindowIsInSpace(CGWindowID windowID, uint64_t spaceID);
CGWindowID TCWindowIDForAXElement(AXUIElementRef window);

NS_ASSUME_NONNULL_END
