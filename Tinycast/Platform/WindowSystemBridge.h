#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>

uint64_t TCCurrentManagedSpace(CFStringRef displayUUID);
bool TCMoveWindowToSpace(CGWindowID windowID, uint64_t spaceID);
bool TCWindowIsInSpace(CGWindowID windowID, uint64_t spaceID);
CGWindowID TCWindowIDForAXElement(AXUIElementRef window);
