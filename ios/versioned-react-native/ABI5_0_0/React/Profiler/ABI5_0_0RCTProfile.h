/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import "ABI5_0_0RCTDefines.h"

/**
 * ABI5_0_0RCTProfile
 *
 * This file provides a set of functions and macros for performance profiling
 *
 * NOTE: This API is a work in progress, please consider carefully before
 * using it.
 */

ABI5_0_0RCT_EXTERN NSString *const ABI5_0_0RCTProfileDidStartProfiling;
ABI5_0_0RCT_EXTERN NSString *const ABI5_0_0RCTProfileDidEndProfiling;

#if ABI5_0_0RCT_DEV

@class ABI5_0_0RCTBridge;

#define ABI5_0_0RCTProfileBeginFlowEvent() \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Wshadow\"") \
NSNumber *__rct_profile_flow_id = _ABI5_0_0RCTProfileBeginFlowEvent(); \
_Pragma("clang diagnostic pop")

#define ABI5_0_0RCTProfileEndFlowEvent() \
_ABI5_0_0RCTProfileEndFlowEvent(__rct_profile_flow_id)

ABI5_0_0RCT_EXTERN dispatch_queue_t ABI5_0_0RCTProfileGetQueue(void);

ABI5_0_0RCT_EXTERN NSNumber *_ABI5_0_0RCTProfileBeginFlowEvent(void);
ABI5_0_0RCT_EXTERN void _ABI5_0_0RCTProfileEndFlowEvent(NSNumber *);

/**
 * Returns YES if the profiling information is currently being collected
 */
ABI5_0_0RCT_EXTERN BOOL ABI5_0_0RCTProfileIsProfiling(void);

/**
 * Start collecting profiling information
 */
ABI5_0_0RCT_EXTERN void ABI5_0_0RCTProfileInit(ABI5_0_0RCTBridge *);

/**
 * Stop profiling and return a JSON string of the collected data - The data
 * returned is compliant with google's trace event format - the format used
 * as input to trace-viewer
 */
ABI5_0_0RCT_EXTERN void ABI5_0_0RCTProfileEnd(ABI5_0_0RCTBridge *, void (^)(NSString *));

/**
 * Collects the initial event information for the event and returns a reference ID
 */
ABI5_0_0RCT_EXTERN void _ABI5_0_0RCTProfileBeginEvent(NSThread *calleeThread,
                                      NSTimeInterval time,
                                      uint64_t tag,
                                      NSString *name,
                                      NSDictionary *args);
#define ABI5_0_0RCT_PROFILE_BEGIN_EVENT(...) \
  do { \
    if (ABI5_0_0RCTProfileIsProfiling()) { \
      NSThread *__calleeThread = [NSThread currentThread]; \
      NSTimeInterval __time = CACurrentMediaTime(); \
      dispatch_async(ABI5_0_0RCTProfileGetQueue(), ^{ \
        _ABI5_0_0RCTProfileBeginEvent(__calleeThread, __time, __VA_ARGS__); \
      }); \
    } \
  } while(0)

/**
 * The ID returned by BeginEvent should then be passed into EndEvent, with the
 * rest of the event information. Just at this point the event will actually be
 * registered
 */
ABI5_0_0RCT_EXTERN void _ABI5_0_0RCTProfileEndEvent(NSThread *calleeThread,
                                    NSString *threadName,
                                    NSTimeInterval time,
                                    uint64_t tag,
                                    NSString *category,
                                    NSDictionary *args);

#define ABI5_0_0RCT_PROFILE_END_EVENT(...) \
  do { \
    if (ABI5_0_0RCTProfileIsProfiling()) { \
      NSThread *__calleeThread = [NSThread currentThread]; \
      NSString *__threadName = ABI5_0_0RCTCurrentThreadName(); \
      NSTimeInterval __time = CACurrentMediaTime(); \
      dispatch_async(ABI5_0_0RCTProfileGetQueue(), ^{ \
        _ABI5_0_0RCTProfileEndEvent(__calleeThread, __threadName, __time, __VA_ARGS__); \
      }); \
    } \
  } while(0)

/**
 * Collects the initial event information for the event and returns a reference ID
 */
ABI5_0_0RCT_EXTERN NSUInteger ABI5_0_0RCTProfileBeginAsyncEvent(uint64_t tag,
                                                NSString *name,
                                                NSDictionary *args);

/**
 * The ID returned by BeginEvent should then be passed into EndEvent, with the
 * rest of the event information. Just at this point the event will actually be
 * registered
 */
ABI5_0_0RCT_EXTERN void ABI5_0_0RCTProfileEndAsyncEvent(uint64_t tag,
                                        NSString *category,
                                        NSUInteger cookie,
                                        NSString *name,
                                        NSString *threadName,
                                        NSDictionary *args);

/**
 * An event that doesn't have a duration (i.e. Notification, VSync, etc)
 */
ABI5_0_0RCT_EXTERN void ABI5_0_0RCTProfileImmediateEvent(uint64_t tag,
                                         NSString *name,
                                         NSTimeInterval time,
                                         char scope);

/**
 * Helper to profile the duration of the execution of a block. This method uses
 * self and _cmd to name this event for simplicity sake.
 *
 * NOTE: The block can't expect any argument
 */
#define ABI5_0_0RCTProfileBlock(block, tag, category, arguments) \
^{ \
  ABI5_0_0RCT_PROFILE_BEGIN_EVENT(tag, @(__PRETTY_FUNCTION__), nil); \
  block(); \
  ABI5_0_0RCT_PROFILE_END_EVENT(tag, category, arguments); \
}

/**
 * Hook into a bridge instance to log all bridge module's method calls
 */
ABI5_0_0RCT_EXTERN void ABI5_0_0RCTProfileHookModules(ABI5_0_0RCTBridge *);

/**
 * Unhook from a given bridge instance's modules
 */
ABI5_0_0RCT_EXTERN void ABI5_0_0RCTProfileUnhookModules(ABI5_0_0RCTBridge *);

/**
 * Send systrace or cpu profiling information to the packager
 * to present to the user
 */
ABI5_0_0RCT_EXTERN void ABI5_0_0RCTProfileSendResult(ABI5_0_0RCTBridge *bridge, NSString *route, NSData *profileData);

/**
 * Systrace gluecode
 *
 * allow to use systrace to back ABI5_0_0RCTProfile
 */

typedef struct {
  const char *key;
  int key_len;
  const char *value;
  int value_len;
} systrace_arg_t;

typedef struct {
  void (*start)(uint64_t enabledTags, char *buffer, size_t bufferSize);
  void (*stop)(void);

  void (*begin_section)(uint64_t tag, const char *name, size_t numArgs, systrace_arg_t *args);
  void (*end_section)(uint64_t tag, size_t numArgs, systrace_arg_t *args);

  void (*begin_async_section)(uint64_t tag, const char *name, int cookie, size_t numArgs, systrace_arg_t *args);
  void (*end_async_section)(uint64_t tag, const char *name, int cookie, size_t numArgs, systrace_arg_t *args);

  void (*instant_section)(uint64_t tag, const char *name, char scope);
} ABI5_0_0RCTProfileCallbacks;

ABI5_0_0RCT_EXTERN void ABI5_0_0RCTProfileRegisterCallbacks(ABI5_0_0RCTProfileCallbacks *);

/**
 * Systrace control window
 */
ABI5_0_0RCT_EXTERN void ABI5_0_0RCTProfileShowControls(void);
ABI5_0_0RCT_EXTERN void ABI5_0_0RCTProfileHideControls(void);

#else

#define ABI5_0_0RCTProfileBeginFlowEvent()
#define _ABI5_0_0RCTProfileBeginFlowEvent() @0

#define ABI5_0_0RCTProfileEndFlowEvent()
#define _ABI5_0_0RCTProfileEndFlowEvent(...)

#define ABI5_0_0RCTProfileIsProfiling(...) NO
#define ABI5_0_0RCTProfileInit(...)
#define ABI5_0_0RCTProfileEnd(...) @""

#define _ABI5_0_0RCTProfileBeginEvent(...)
#define _ABI5_0_0RCTProfileEndEvent(...)

#define ABI5_0_0RCT_PROFILE_BEGIN_EVENT(...)
#define ABI5_0_0RCT_PROFILE_END_EVENT(...)

#define ABI5_0_0RCTProfileBeginAsyncEvent(...) 0
#define ABI5_0_0RCTProfileEndAsyncEvent(...)

#define ABI5_0_0RCTProfileImmediateEvent(...)

#define ABI5_0_0RCTProfileBlock(block, ...) block

#define ABI5_0_0RCTProfileHookModules(...)
#define ABI5_0_0RCTProfileUnhookModules(...)

#define ABI5_0_0RCTProfileSendResult(...)

#define ABI5_0_0RCTProfileShowControls(...)
#define ABI5_0_0RCTProfileHideControls(...)

#endif
