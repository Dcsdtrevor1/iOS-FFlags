// Can you all let me know if these comments are good or if I should go back to having none at this point idk if anyone is even reading the code in the first place
#import <Foundation/Foundation.h>

#if __has_include("FFlagsData.h")
#import "FFlagsData.h"
#else
// Fallback if the build script wasnt run
static const char *kFFlagsJSON = "{}";
#endif

// --- Configuration Constants ---
// This is the file the dylib will look for as a local override
static NSString *const kDesiredSettingsFilename = @"DesiredIxpSettings.json";

// This is the file the dylib will create/update in the apps Library/Application Support/ClientSettings directory
static NSString *const kOutputSettingsFilename = @"IxpSettings.json";

// --- Utility Functions ---

static NSDictionary *ParseJSONString(NSString *json) {
if (json.length == 0) { return @{}; }
NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
if (!data) { return @{}; }
NSError *error = nil;
id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
if (error || ![obj isKindOfClass:[NSDictionary class]]) {
NSLog(@"[RBXFFlags] Failed to parse embedded JSON: %@", error);
return @{};
}
return (NSDictionary *)obj;
}

static NSDictionary *DeepMergeDicts(NSDictionary *existing, NSDictionary *desired) {
NSMutableDictionary *result = [existing mutableCopy];
[result addEntriesFromDictionary:desired];
return [result copy];
}

static NSDictionary *LoadDesiredFFlags(void) {
@autoreleasepool {
// 1) Optional runtime override file if present (using the new IxpSettings name)
NSString *home = NSHomeDirectory();
NSString *overridePath = [home stringByAppendingPathComponent:[NSString stringWithFormat:@"Library/Application Support/ClientSettings/%@", kDesiredSettingsFilename]];

    NSData *overrideData = [NSData dataWithContentsOfFile:overridePath];
    if (overrideData) {
        NSError *err = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:overrideData options:0 error:&err];
        if (!err && [obj isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[RBXFFlags] Loaded runtime override from %@", kDesiredSettingsFilename);
            return (NSDictionary *)obj;
        } else {
            NSLog(@"[RBXFFlags] Error loading runtime override: %@", err);
        }
    }

    // 2) Fallback to embedded JSON from build
    NSString *jsonString = [NSString stringWithUTF8String:kFFlagsJSON];
    if (jsonString.length > 2) { // Check if its more than just "{}"
         NSLog(@"[RBXFFlags] Loaded embedded flags from FFlagsData.h");
         return ParseJSONString(jsonString);
    }

    NSLog(@"[RBXFFlags] No desired flags found.");
    return @{};
}


}

// --- Dynamic Library Entry Point ---

attribute((constructor))
static void rbxfflags_init(void) {
// Only run this once
static dispatch_once_t onceToken;
dispatch_once(&onceToken, ^{
@try {
NSFileManager *fm = [NSFileManager defaultManager];
NSError *error = nil;

        // Get the App Support directory path
        NSString *settingsDir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        
        // Append the ClientSettings subdirectory
        settingsDir = [settingsDir stringByAppendingPathComponent:@"ClientSettings"];

        // The final path for the file we are creating/updating (using the new IxpSettings name)
        NSString *settingsPath = [settingsDir stringByAppendingPathComponent:kOutputSettingsFilename];

        // Ensure the ClientSettings directory exists
        if (![fm fileExistsAtPath:settingsDir]) {
            BOOL ok = [fm createDirectoryAtPath:settingsDir withIntermediateDirectories:YES attributes:nil error:&error];
            if (!ok || error) {
                NSLog(@"[RBXFFlags] Failed to create settings directory: %@, Error: %@", settingsDir, error);
                return;
            }
        }

        NSDictionary *desired = LoadDesiredFFlags();
        NSDictionary *finalConfig = desired ?: @{};

        // Check if the file already exists and merge with it
        if ([fm fileExistsAtPath:settingsPath]) {
            NSData *existingData = [NSData dataWithContentsOfFile:settingsPath options:0 error:&error];
            if (existingData) {
                id existingObj = [NSJSONSerialization JSONObjectWithData:existingData options:0 error:&error];
                if (!error && [existingObj isKindOfClass:[NSDictionary class]]) {
                    // DeepMergeDicts merges `desired` into `existing`
                    finalConfig = DeepMergeDicts((NSDictionary *)existingObj, desired ?: @{});
                } else if (error) {
                    NSLog(@"[RBXFFlags] Failed to parse existing JSON: %@", error);
                }
            }
        }

        // Serialize the final configuration dictionary
        NSData *outData = [NSJSONSerialization dataWithJSONObject:finalConfig options:NSJSONWritingPrettyPrinted error:&error];
        if (!outData || error) {
            NSLog(@"[RBXFFlags] Failed to serialize JSON: %@", error);
            return;
        }

        // Write the data to the target file
        BOOL ok = [outData writeToFile:settingsPath atomically:YES];
        if (!ok) {
            NSLog(@"[RBXFFlags] Failed to write to %@", settingsPath);
        } else {
            // Optional minimal log to confirm success
            NSLog(@"[RBXFFlags] Ensured/updated %@", settingsPath);
        }
    } @catch (NSException *ex) {
        NSLog(@"[RBXFFlags] Exception: %@", ex);
    }
});


}