/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "ABI5_0_0RCTJavaScriptLoader.h"

#import "ABI5_0_0RCTBridge.h"
#import "ABI5_0_0RCTConvert.h"
#import "ABI5_0_0RCTSourceCode.h"
#import "ABI5_0_0RCTUtils.h"
#import "ABI5_0_0RCTPerformanceLogger.h"

#include <sys/stat.h>

uint32_t const ABI5_0_0RCTRAMBundleMagicNumber = 0xFB0BD1E5;

@implementation ABI5_0_0RCTJavaScriptLoader

ABI5_0_0RCT_NOT_IMPLEMENTED(- (instancetype)init)

+ (void)loadBundleAtURL:(NSURL *)scriptURL onComplete:(ABI5_0_0RCTSourceLoadBlock)onComplete
{
  // Sanitize the script URL
  scriptURL = [ABI5_0_0RCTConvert NSURL:scriptURL.absoluteString];

  if (!scriptURL) {
    NSError *error = [NSError errorWithDomain:@"JavaScriptLoader" code:1 userInfo:@{
      NSLocalizedDescriptionKey: @"No script URL provided."
    }];
    onComplete(error, nil);
    return;
  }

  // Load local script file
  if (scriptURL.fileURL) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSError *error = nil;
      NSData *source = nil;

      // Load the first 4 bytes to check if the bundle is regular or RAM ("Random Access Modules" bundle).
      // The RAM bundle has a magic number in the 4 first bytes `(0xFB0BD1E5)`.
      // The benefit of RAM bundle over a regular bundle is that we can lazily inject
      // modules into JSC as they're required.
      FILE *bundle = fopen(scriptURL.path.UTF8String, "r");
      if (!bundle) {
        onComplete(ABI5_0_0RCTErrorWithMessage([NSString stringWithFormat:@"Error opening bundle %@", scriptURL.path]), source);
        return;
      }

      uint32_t magicNumber;
      if (fread(&magicNumber, sizeof(magicNumber), 1, bundle) != 1) {
        fclose(bundle);
        onComplete(ABI5_0_0RCTErrorWithMessage(@"Error reading bundle"), source);
        return;
      }

      magicNumber = NSSwapLittleIntToHost(magicNumber);

      int64_t sourceLength = 0;
      if (magicNumber == ABI5_0_0RCTRAMBundleMagicNumber) {
        source = [NSData dataWithBytes:&magicNumber length:sizeof(magicNumber)];

        struct stat statInfo;
        if (stat(scriptURL.path.UTF8String, &statInfo) != 0) {
          error = ABI5_0_0RCTErrorWithMessage(@"Error reading bundle");
        } else {
          sourceLength = statInfo.st_size;
        }
      } else {
        source = [NSData dataWithContentsOfFile:scriptURL.path
                                                options:NSDataReadingMappedIfSafe
                                                  error:&error];
        sourceLength = source.length;
      }

      ABI5_0_0RCTPerformanceLoggerSet(ABI5_0_0RCTPLBundleSize, sourceLength);
      fclose(bundle);
      onComplete(error, source);
    });
    return;
  }

  // Load remote script file
  NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:scriptURL completionHandler:
                                ^(NSData *data, NSURLResponse *response, NSError *error) {

    // Handle general request errors
    if (error) {
      if ([error.domain isEqualToString:NSURLErrorDomain]) {
        NSString *desc = [@"Could not connect to development server.\n\nEnsure the following:\n- Node server is running and available on the same network - run 'npm start' from ReactABI5_0_0-native root\n- Node server URL is correctly set in AppDelegate\n\nURL: " stringByAppendingString:scriptURL.absoluteString];
        NSDictionary *userInfo = @{
          NSLocalizedDescriptionKey: desc,
          NSLocalizedFailureReasonErrorKey: error.localizedDescription,
          NSUnderlyingErrorKey: error,
        };
        error = [NSError errorWithDomain:@"JSServer"
                                    code:error.code
                                userInfo:userInfo];
      }
      onComplete(error, nil);
      return;
    }

    // Parse response as text
    NSStringEncoding encoding = NSUTF8StringEncoding;
    if (response.textEncodingName != nil) {
      CFStringEncoding cfEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)response.textEncodingName);
      if (cfEncoding != kCFStringEncodingInvalidId) {
        encoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding);
      }
    }
    // Handle HTTP errors
    if ([response isKindOfClass:[NSHTTPURLResponse class]] && ((NSHTTPURLResponse *)response).statusCode != 200) {
      NSString *rawText = [[NSString alloc] initWithData:data encoding:encoding];
      NSDictionary *userInfo;
      NSDictionary *errorDetails = ABI5_0_0RCTJSONParse(rawText, nil);
      if ([errorDetails isKindOfClass:[NSDictionary class]] &&
          [errorDetails[@"errors"] isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSDictionary *> *fakeStack = [NSMutableArray new];
        for (NSDictionary *err in errorDetails[@"errors"]) {
          [fakeStack addObject: @{
            @"methodName": err[@"description"] ?: @"",
            @"file": err[@"filename"] ?: @"",
            @"lineNumber": err[@"lineNumber"] ?: @0
          }];
        }
        userInfo = @{
          NSLocalizedDescriptionKey: errorDetails[@"message"] ?: @"No message provided",
          @"stack": fakeStack,
        };
      } else {
        userInfo = @{NSLocalizedDescriptionKey: rawText};
      }
      error = [NSError errorWithDomain:@"JSServer"
                                  code:((NSHTTPURLResponse *)response).statusCode
                              userInfo:userInfo];

      onComplete(error, nil);
      return;
    }
    ABI5_0_0RCTPerformanceLoggerSet(ABI5_0_0RCTPLBundleSize, data.length);
    onComplete(nil, data);
  }];

  [task resume];
}

@end
