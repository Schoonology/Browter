#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

/**
 * Top-level object to give NSAppleEventManager something to call, as it cannot
 * call arbitrary functions.
 */
@interface URLHandler : NSObject {}
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;
@end

@implementation URLHandler
/**
 * Initializes the URLHandler, wiring up the one and only event we care about.
 */
- (id)init
{
  self = [super init];

  if (self) {
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
      andSelector:@selector(handleGetURLEvent:withReplyEvent:)
      forEventClass:kInternetEventClass
      andEventID:kAEGetURL];
  }

  return self;
}

/**
 * Event handler fired whenever any http://, https://, or file:// URL is opened
 * system-wide (as defined in Info.plist).
 */
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
  NSString* url = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
  NSString* app = @"Firefox";

  NSLog(@"Opening %@ with %@...", url, app);

  [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[url, @"-a", app]];
}

@end

/**
 * Initializes the process and creates our top-level object, which will handle
 * the actual URL routing.
 */
int main(int argc, const char * argv[]) {
  ProcessSerialNumber psn = { 0, kCurrentProcess };
  TransformProcessType(&psn, kProcessTransformToBackgroundApplication);

  URLHandler *handler = [[URLHandler alloc] init];

  return NSApplicationMain(argc, argv);
}
