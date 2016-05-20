#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

/**
 * Constants
 */
NSString *kProcessIdentifierKey = @"__pid";
NSString *kDefaultAppNameKey = @"__default";
NSString *kFallbackDefaultAppName = @"Safari";
NSString *kSettingsFileName = @"~/.browterrc";
NSString *kUsageInfo = @"Usage:\n"
  "  browter add RULE BROWSER\n"
  "  browter default BROWSER\n"
  "  browter remove RULE\n"
  "  browter quit\n"
  "\n"
  "For more information, see https://github.com/Schoonology/Browter.\n";

/**
 * Globals
 */
NSMutableDictionary *settings;

/**
 * Prints a printf-formatted string to STDOUT, followed by the usage.
 */
void error(NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  printf("%s\n\n", [formattedString UTF8String]);
  printf("%s", [kUsageInfo UTF8String]);
}

/**
 * Clears this process' PID from the global settings file.
 */
void clear_pid(int signo) {
  [settings removeObjectForKey:kProcessIdentifierKey];
  [settings writeToFile:kSettingsFileName atomically:FALSE];

  exit(0);
}

/**
 * Opens `url` in our configured browser as defined by the global settings
 * file.
 */
void open_url(NSString *url) {
  NSString* __block app = [settings objectForKey:kDefaultAppNameKey];

  if (!app) {
    app = kFallbackDefaultAppName;
  }

  // This enumeration happens in a theoretically arbitrary order, which is why
  // rules should, generally, not overlap.
  [settings enumerateKeysAndObjectsUsingBlock:^(NSString *rule, NSString *browser, BOOL *stop) {
    if ([url containsString:rule]) {
      app = browser;
      *stop = YES;
    }
  }];

  // Log to syslog. See `run_server` for more information.
  NSLog(@"Opening %@ with %@...", url, app);

  // As it turns out, using `open` appears to be the only way to open a URL
  // with a specific application.
  [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[url, @"-a", app]];
}

/**
 * Runs the individual `command`, based on `args`, returning the desired exit
 * code. Errors resulting from invalid commands, arguments, etc. will be
 * printed to STDOUT before returning.
 *
 * For more information on the desired behaviour of commands, see the README.
 */
int run_command(NSString *command, NSArray<NSString *> *args) {
  NSDictionary *commands = @{
    @"default": @[@[@"BROWSER"], ^(NSArray<NSString *> *args) {
      [settings setObject:args[0] forKey:kDefaultAppNameKey];
      [settings writeToFile:kSettingsFileName atomically:FALSE];
    }],
    @"add": @[@[@"RULE", @"BROWSER"], ^(NSArray<NSString *> *args) {
      [settings setObject:args[1] forKey:args[0]];
      [settings writeToFile:kSettingsFileName atomically:FALSE];
    }],
    @"remove": @[@[@"RULE"], ^(NSArray<NSString *> *args) {
      [settings removeObjectForKey:args[0]];
      [settings writeToFile:kSettingsFileName atomically:FALSE];
    }],
    @"list": @[@[], ^(NSArray<NSString *> *args) {
      printf("Rules:\n");
      [settings enumerateKeysAndObjectsUsingBlock:^(NSString *rule, NSString *browser, BOOL *stop) {
        printf("  %s => %s\n", [rule UTF8String], [browser UTF8String]);
      }];
    }],
    @"quit": @[@[], ^(NSArray<NSString *> *args) {
      int pid = [[settings objectForKey:kProcessIdentifierKey] intValue];
      if (pid) {
        kill(pid, SIGHUP);
      }
    }],
  };

  id pair = [commands objectForKey:command];
  int desiredCount = [[pair firstObject] count];
  int countDiff = [args count] - desiredCount;
  void (^block)(NSArray *) = [pair lastObject];

  if (pair && countDiff == 0) {
    block(args);
    return 0;
  }

  if (!pair) {
    error(@"Error: \"%@\" is not a valid Browter command.", command);
  } else if (countDiff > 0) {
    error(@"Error: Too many arguments for \"%@\" command.", command);
  } else if (countDiff < 0) {
    error(@"Error: \"%@\" command requires %@ arguments.", command, desiredCount);
  }

  return 1;
}

/**
 * Top-level object and glue code to give NSAppleEventManager something to
 * call, as it cannot call arbitrary C functions.
 *
 * See `open_url` for actual URL routing logic.
 */
@interface URLHandler : NSObject
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;
@end

@implementation URLHandler
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
  open_url([[event paramDescriptorForKeyword:keyDirectObject] stringValue]);
}
@end

/**
 * Starts the long-running NSApplication, which will post our events for
 * requests from the OS to open any `http://`, `https://`, or `file://` URL
 * system-wide (as defined in Info.plist).
 *
 * See `open_url` for actual URL routing logic.
 *
 * This function never returns.
 */
int run_server() {
  int pid = [[NSProcessInfo processInfo] processIdentifier];

  // We switch to using NSLog for the remainder of the process. These logs can
  // be viewed using syslog. On Mac OS X 10.7 or newer:
  //
  //     syslog -d /private/var/log/asl -w
  //
  NSLog(@"Main Browter Process");
  NSLog(@"====================");
  NSLog(@"Settings: %@", settings);
  NSLog(@"PID: %d", pid);

  // Wire up signal handler for all reasonable signals.
  signal(SIGHUP, clear_pid);
  signal(SIGINT, clear_pid);

  // Set a PID in our global settings file for `browter quit`.
  [settings setValue:[NSNumber numberWithInt:pid]
    forKey:kProcessIdentifierKey];
  [settings writeToFile:kSettingsFileName
    atomically:FALSE];

  // Initialize our URLHandler and wire up the one and only event we care
  // about: Getting a URL.
  URLHandler *handler = [[URLHandler alloc] init];
  [[NSAppleEventManager sharedAppleEventManager] setEventHandler:handler
    andSelector:@selector(handleGetURLEvent:withReplyEvent:)
    forEventClass:kInternetEventClass
    andEventID:kAEGetURL];

  // Finally, defer to Cocoa for the remainder of the work.
  return NSApplicationMain(0, NULL);
}

/**
 * Processes our command/arguments, becoming long-running if no command was
 * given. Most of the work is done in other methods.
 */
int main(int argc, const char * argv[]) {
  ProcessSerialNumber psn = { 0, kCurrentProcess };
  TransformProcessType(&psn, kProcessTransformToBackgroundApplication);

  // Transform non-compile-time-constant values.
  kSettingsFileName = [kSettingsFileName stringByExpandingTildeInPath];

  settings = [NSMutableDictionary dictionaryWithContentsOfFile:kSettingsFileName];
  if (!settings) {
    settings = [[NSMutableDictionary alloc] init];
  }

  // If we have at least one argument, process it as a command.
  NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];

  if ([arguments count] > 1) {
    NSRange range = { 2, [arguments count] - 2 };
    return run_command(arguments[1], [arguments subarrayWithRange:range]);
  }

  // If there are no arguments, start the long-running browser process.
  return run_server();
}
