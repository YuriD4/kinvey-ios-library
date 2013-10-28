//
//  KCSRequest2.m
//  KinveyKit
//
//  Created by Michael Katz on 8/12/13.
//  Copyright (c) 2013 Kinvey. All rights reserved.
//
// This software is licensed to you under the Kinvey terms of service located at
// http://www.kinvey.com/terms-of-use. By downloading, accessing and/or using this
// software, you hereby accept such terms of service  (and any agreement referenced
// therein) and agree that you have read, understand and agree to be bound by such
// terms of service and are of legal age to agree to such terms with Kinvey.
//
// This software contains valuable confidential and proprietary information of
// KINVEY, INC and is subject to applicable licensing agreements.
// Unauthorized reproduction, transmission or distribution of this file and its
// contents is a violation of applicable laws.
//


#import "KCSRequest2.h"
#import "KinveyCoreInternal.h"

#import "KCSNSURLRequestOperation.h"
#import "KCSMockRequestOperation.h"
#import "KCSNSURLSessionOperation.h"

#define kHeaderAuthorization   @"Authorization"
#define kHeaderApiVersion      @"X-Kinvey-Api-Version"
#define kHeaderClientMethod    @"X-Kinvey-Client-Method"
#define kHeaderResponseWrapper @"X-Kinvey-ResponseWrapper"

#define kHeaderValueJson @"application/json"

#define kErrorKeyMethod @"KinveyKit.HTTPMethod"

#define kMaxTries 5

KCS_CONST_IMPL KCSRequestOptionClientMethod = kHeaderClientMethod;
KCS_CONST_IMPL KCSRequestOptionUseMock      = @"UseMock";
KCS_CONST_IMPL KCSRESTRouteAppdata          = @"appdata";
KCS_CONST_IMPL KCSRESTRouteUser             = @"user";
KCS_CONST_IMPL KCSRESTRouteRPC              = @"rpc";
KCS_CONST_IMPL KCSRestRouteTestReflection   = @"!reflection";

KCS_CONST_IMPL KCSRESTMethodDELETE = @"DELETE";
KCS_CONST_IMPL KCSRESTMethodGET    = @"GET";
KCS_CONST_IMPL KCSRESTMethodPATCH  = @"PATCH";
KCS_CONST_IMPL KCSRESTMethodPOST   = @"POST";
KCS_CONST_IMPL KCSRESTMethodPUT    = @"PUT";


#define KCS_VERSION @"3"

@interface KCSRequest2 ()
@property (nonatomic) BOOL useMock;
@property (nonatomic, copy) KCSRequestCompletionBlock completionBlock;
@property (nonatomic, copy) NSString* contentType;
@property (nonatomic, retain) NSOperationQueue* currentQueue;
@property (nonatomic, weak) id<KCSCredentials> credentials;
@property (nonatomic, retain) NSString* route;
@property (nonatomic, copy) NSDictionary* options;
@end

@implementation KCSRequest2

static NSOperationQueue* queue;

+ (void)initialize
{
    queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 4;
    [queue setName:@"com.kinvey.KinveyKit.RequestQueue"];
}

+ (instancetype) requestWithCompletion:(KCSRequestCompletionBlock)completion route:(NSString*)route options:(NSDictionary*)options credentials:(id)credentials;
{
    KCSRequest2* request = [[KCSRequest2 alloc] init];
    request.useMock = [options[KCSRequestOptionUseMock] boolValue];
    request.completionBlock = completion;
    request.credentials = credentials;
    request.route = route;
    request.options = options;
    return request;
}

- (instancetype) init
{
    self = [super init];
    if (self) {
        _contentType = kHeaderValueJson;
        _method = KCSRESTMethodGET;
    }
    return self;
}


# pragma mark -

- (id<KCSNetworkOperation>) start
{
    NSAssert(_route, @"should have route");
    NSAssert(self.credentials, @"should have credentials");
    DBAssert(self.options[KCSRequestOptionClientMethod], @"DB should set client method");
    
    KCSClientConfiguration* config = [KCSClient2 sharedClient].configuration;
    NSString* baseURL = [config baseURL];
    NSString* kid = config.appKey;
    
    NSArray* path = [@[self.route, kid] arrayByAddingObjectsFromArray:[_path arrayByPercentEncoding]];
    NSString* urlStr = [path componentsJoinedByString:@"/"];
    NSString* endpoint = [baseURL stringByAppendingString:urlStr];
    
    NSURL* url = [NSURL URLWithString:endpoint];
    
    _currentQueue = [NSOperationQueue currentQueue];
    
    NSOperation<KCSNetworkOperation>* op = nil;
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:[config.options[KCS_URL_CACHE_POLICY] unsignedIntegerValue]
                                                       timeoutInterval:[config.options[KCS_CONNECTION_TIMEOUT] doubleValue]];
    request.HTTPMethod = self.method;
    
    NSMutableDictionary* headers = [NSMutableDictionary dictionary];
    headers[kHeaderContentType] = _contentType;
    headers[kHeaderAuthorization] = [self.credentials authString];
    headers[kHeaderApiVersion] = KCS_VERSION;
    headers[kHeaderResponseWrapper] = @"true";
    setIfValNotNil(headers[kHeaderClientMethod], self.options[KCSRequestOptionClientMethod]);
    
    KK2(enable these headers)
    //headers[@"User-Agent"] = [client userAgent];
    //headers[@"X-Kinvey-Device-Information"] = [client.analytics headerString];
    
    [request setAllHTTPHeaderFields:headers];
    //[request setHTTPShouldUsePipelining:_httpMethod != kKCSRESTMethodPOST];
    
    KCSLogInfo(KCS_LOG_CONTEXT_NETWORK, @"%@ %@", request.HTTPMethod, request.URL);
    
    if (_useMock == YES) {
        op = [[KCSMockRequestOperation alloc] initWithRequest:request];
    } else {
        
        if ([KCSPlatformUtils supportsNSURLSession]) {
            op = [[KCSNSURLSessionOperation alloc] initWithRequest:request];
        } else {
            op = [[KCSNSURLRequestOperation alloc] initWithRequest:request];
        }
    }
    
    @weakify(op);
    op.completionBlock = ^() {
        @strongify(op);
        [self requestCallback:op request:request];
    };
    
    [queue addOperation:op];
    return op;
}

- (void) requestCallback:(NSOperation<KCSNetworkOperation>*)op request:(NSURLRequest*)request
{
    if ([[KCSClient sharedClient].options[KCS_CONFIG_RETRY_DISABLED] boolValue] == YES) {
        [self callCallback:op request:request];
    } else {
        if (opIsRetryableNetworkError(op)) {
            KCSLogNotice(KCS_LOG_CONTEXT_NETWORK, @"Retrying request. Network error: %ld.", (long)op.error.code);
            [self retryOp:op request:request];
        } else if (opIsRetryableKCSError(op)) {
            KCSLogNotice(KCS_LOG_CONTEXT_NETWORK, @"Retrying request. Kinvey server error: %@", [op.response jsonObject]);
            [self retryOp:op request:request];
        } else {
            //status OK or is a non-retryable error
            [self callCallback:op request:request];
        }
    }
}

BOOL opIsRetryableNetworkError(NSOperation<KCSNetworkOperation>* op)
{
    BOOL isError = NO;
    if (op.error) {
        if ([[op.error domain] isEqualToString:NSURLErrorDomain]) {
            switch (op.error.code) {
                case kCFURLErrorUnknown:
                case kCFURLErrorTimedOut:
                case kCFURLErrorCannotFindHost:
                case kCFURLErrorCannotConnectToHost:
                case kCFURLErrorNetworkConnectionLost:
                case kCFURLErrorDNSLookupFailed:
                case kCFURLErrorResourceUnavailable:
                case kCFURLErrorRequestBodyStreamExhausted:
                    isError = YES;
                    break;
            }
        }
    }
    
    return isError;
}

BOOL opIsRetryableKCSError(NSOperation<KCSNetworkOperation>* op)
{
    //kcs error KinveyInternalErrorRetry:
    //        statusCode: 500
    //        description: "The Kinvey server encountered an unexpected error. Please retry your request"
    
    return [op.response isKCSError] == YES &&
    op.response.code == 500 &&
    [[op.response jsonObject][@"error"] isEqualToString:@"KinveyInternalErrorRetry"];
}

- (void) retryOp:(NSOperation<KCSNetworkOperation>*)oldOp request:(NSURLRequest*)request
{
    NSUInteger newcount = oldOp.retryCount + 1;
    if (newcount == kMaxTries) {
        [self callCallback:oldOp request:request];
    } else {
        NSOperation<KCSNetworkOperation>* op = [[[oldOp class] alloc] initWithRequest:request];
        op.retryCount = newcount;
        @weakify(op);
        op.completionBlock = ^() {
            @strongify(op);
            [self requestCallback:op request:request];
        };
        
        double delayInSeconds = 0.1 * pow(2, newcount - 1); //exponential backoff
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [queue addOperation:op];
        });
    }
}

- (void) callCallback:(NSOperation<KCSNetworkOperation>*)op request:(NSURLRequest*)request
{
    [_currentQueue addOperationWithBlock:^{
        op.response.originalURL = request.URL;
        NSError* error = nil;
        if (op.error) {
            error = [op.error errorByAddingCommonInfo];
            KCSLogInfo(KCS_LOG_CONTEXT_NETWORK, @"Network Client Error %@", error);
        } else if ([op.response isKCSError]) {
            KCSLogInfo(KCS_LOG_CONTEXT_NETWORK, @"Kinvey Server Error (%ld) %@", (long)op.response.code, op.response.jsonData);
            error = [op.response errorObject];
        } else {
            KCSLogInfo(KCS_LOG_CONTEXT_NETWORK, @"Kinvey Success (%ld)", (long)op.response.code);
        }
        error = [error updateWithInfo:@{kErrorKeyMethod : request.HTTPMethod}];
        self.completionBlock(op.response, error);
    }];
}


@end
