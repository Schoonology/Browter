#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NSMutableDictionary *settings;

/**
 * Prints usage information to STDOUT.
 */
void usage() {
  printf("Usage:\n");
  printf("  browter add RULE BROWSER\n");
  printf("  browter default BROWSER\n");
  printf("  browter remove RULE\n");
  printf("  browter quit\n");
  printf("\n");
  printf("For more information, see https://github.com/Schoonology/Browter.\n");
}

/**
 * Prints a printf-formatted string to STDOUT, followed by the usage.
 */
void error(NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *formattedString = [[NSString alloc] initWithFormat: format
    arguments: args];
  va_end(args);

  #pragma clang diagnostic push
  #pragma clang diagnostic ignored "-Wformat-security"
  printf([formattedString UTF8String]);
  #pragma clang diagnostic pop
  printf("\n\n");
  usage();
}

void save() {
  [settings writeToFile:[@"~/.browterrc" stringByExpandingTildeInPath] atomically:FALSE];
}

void pid_clear() {
  [settings removeObjectForKey:@"pid"];
  save();
}

void signal_handle(int signo) {
  pid_clear();
  exit(0);
}

/**
 * Top-level object to give NSAppleEventManager something to call, as it cannot
 * call arbitrary functions.
 */
@interface URLHandler : NSObject {
  NSDictionary *rules;
}
+ (id)handlerWithDictionary:(NSDictionary *)rules;
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;
@end

@implementation URLHandler
/**
 * Creates, initializes, and returns a new URLHandler wrapping `rules`.
 */
+ (id)handlerWithDictionary:(NSDictionary *)rules {
  URLHandler *handler = [[URLHandler alloc] init];

  handler->rules = rules;

  return handler;
}

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
  NSString* __block app = @"Safari";

  [self->rules enumerateKeysAndObjectsUsingBlock:^(NSString *rule, NSString *browser, BOOL *stop) {
    if ([url containsString:rule]) {
      app = browser;
      *stop = TRUE;
    }
  }];

  NSLog(@"Opening %@ with %@...", url, app);

  [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[url, @"-a", app]];
}

@end

/**
 * Initializes the process and creates our top-level object, which will handle
 * the actual URL routing.
 */
int main(int argc, const char * argv[]) {
  settings = [NSMutableDictionary dictionaryWithContentsOfFile:[@"~/.browterrc" stringByExpandingTildeInPath]];

  if (!settings) {
    settings = [[NSMutableDictionary alloc] init];
  }

  NSString *command = argv[1] ? [NSString stringWithCString:argv[1] encoding:[NSString defaultCStringEncoding]] : nil;

  if ([@"add" isEqualToString:command]) {
    if (argc < 4) {
      error(@"Error: \"add\" command requires both RULE and BROWSER arguments.");
      return 1;
    } else if (argc > 4) {
      error(@"Error: Too many arguments for \"add\" command.");
      return 1;
    }

    [settings setObject:[NSString stringWithCString:argv[3]
        encoding:[NSString defaultCStringEncoding]]
      forKey:[NSString stringWithCString:argv[2]
        encoding:[NSString defaultCStringEncoding]]];
    [settings writeToFile:[@"~/.browterrc" stringByExpandingTildeInPath] atomically:FALSE];
    return 0;
  } else if ([@"remove" isEqualToString:command]) {
    if (argc < 3) {
      error(@"Error: \"remove\" command requires a RULE argument.");
      return 1;
    } else if (argc > 3) {
      error(@"Error: Too many arguments for \"remove\" command.");
      return 1;
    }

    [settings removeObjectForKey:[NSString stringWithCString:argv[2]
        encoding:[NSString defaultCStringEncoding]]];
    [settings writeToFile:[@"~/.browterrc" stringByExpandingTildeInPath] atomically:FALSE];
    return 0;
  } else if ([@"quit" isEqualToString:command]) {
    if (argc > 2) {
      error(@"Error: No arguments allowed for \"quit\" command.");
      return 1;
    }

    [NSTask launchedTaskWithLaunchPath:@"/bin/kill" arguments:@[[[settings objectForKey:@"pid"] description]]];
    return 0;
  } else if (command) {
    error(@"Error: \"%@\" is not a valid Browter command.", command);
    return 1;
  }

  NSLog(@"Main Browter Process");
  NSLog(@"====================");
  NSLog(@"Settings: %@", settings);
  NSLog(@"PID: %d", [[NSProcessInfo processInfo] processIdentifier]);

  atexit(pid_clear);
  signal(SIGHUP, signal_handle);
  signal(SIGINT, signal_handle);
  signal(SIGTERM, signal_handle);
  signal(SIGQUIT, signal_handle);

  [settings setValue:[NSNumber numberWithInt:[[NSProcessInfo processInfo] processIdentifier]]
    forKey:@"pid"];
  [settings writeToFile:[@"~/.browterrc" stringByExpandingTildeInPath] atomically:FALSE];

  ProcessSerialNumber psn = { 0, kCurrentProcess };
  TransformProcessType(&psn, kProcessTransformToBackgroundApplication);

  URLHandler *handler = [URLHandler handlerWithDictionary:settings];

  return NSApplicationMain(argc, argv);
}
