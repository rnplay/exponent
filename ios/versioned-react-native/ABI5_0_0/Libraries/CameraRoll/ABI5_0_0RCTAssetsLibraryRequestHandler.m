/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "ABI5_0_0RCTAssetsLibraryRequestHandler.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <libkern/OSAtomic.h>

#import "ABI5_0_0RCTBridge.h"
#import "ABI5_0_0RCTUtils.h"

@implementation ABI5_0_0RCTAssetsLibraryRequestHandler
{
  ALAssetsLibrary *_assetsLibrary;
}

ABI5_0_0RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

- (ALAssetsLibrary *)assetsLibrary
{
  return _assetsLibrary ?: (_assetsLibrary = [ALAssetsLibrary new]);
}

#pragma mark - ABI5_0_0RCTURLRequestHandler

- (BOOL)canHandleRequest:(NSURLRequest *)request
{
  return [request.URL.scheme caseInsensitiveCompare:@"assets-library"] == NSOrderedSame;
}

- (id)sendRequest:(NSURLRequest *)request
     withDelegate:(id<ABI5_0_0RCTURLRequestDelegate>)delegate
{
  __block volatile uint32_t cancelled = 0;
  void (^cancellationBlock)(void) = ^{
    OSAtomicOr32Barrier(1, &cancelled);
  };

  [[self assetsLibrary] assetForURL:request.URL resultBlock:^(ALAsset *asset) {
    if (cancelled) {
      return;
    }

    if (asset) {

      ALAssetRepresentation *representation = [asset defaultRepresentation];
      NSInteger length = (NSInteger)representation.size;

      NSURLResponse *response =
      [[NSURLResponse alloc] initWithURL:request.URL
                                MIMEType:representation.UTI
                   expectedContentLength:length
                        textEncodingName:nil];

      [delegate URLRequest:cancellationBlock didReceiveResponse:response];

      NSError *error = nil;
      uint8_t *buffer = (uint8_t *)malloc((size_t)length);
      if ([representation getBytes:buffer
                        fromOffset:0
                            length:length
                             error:&error]) {

        NSData *data = [[NSData alloc] initWithBytesNoCopy:buffer
                                                    length:length
                                              freeWhenDone:YES];

        [delegate URLRequest:cancellationBlock didReceiveData:data];
        [delegate URLRequest:cancellationBlock didCompleteWithError:nil];

      } else {
        free(buffer);
        [delegate URLRequest:cancellationBlock didCompleteWithError:error];
      }

    } else {
      NSString *errorMessage = [NSString stringWithFormat:@"Failed to load asset"
                                " at URL %@ with no error message.", request.URL];
      NSError *error = ABI5_0_0RCTErrorWithMessage(errorMessage);
      [delegate URLRequest:cancellationBlock didCompleteWithError:error];
    }
  } failureBlock:^(NSError *loadError) {
    if (cancelled) {
      return;
    }
    [delegate URLRequest:cancellationBlock didCompleteWithError:loadError];
  }];

  return cancellationBlock;
}

- (void)cancelRequest:(id)requestToken
{
  ((void (^)(void))requestToken)();
}

@end

@implementation ABI5_0_0RCTBridge (ABI5_0_0RCTAssetsLibraryImageLoader)

- (ALAssetsLibrary *)assetsLibrary
{
  return [[self moduleForClass:[ABI5_0_0RCTAssetsLibraryRequestHandler class]] assetsLibrary];
}

@end
