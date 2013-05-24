//
//  KCSGenericRESTRequest.m
//  KinveyKit
//
//  Created by Michael Katz on 8/22/12.
//  Copyright (c) 2012-2013 Kinvey. All rights reserved.
//

#import "KCSGenericRESTRequest.h"

#import "KCSRESTRequest.h"
#import "KCSConnectionPool.h"
#import "KCSClient.h"
#import "KinveyUser.h"
#import "KCSLogManager.h"
#import "KCSAuthCredential.h"
#import "KinveyErrorCodes.h"
#import "KCSErrorUtilities.h"
#import "KinveyAnalytics.h"
#import "KCS_SBJson.h"

@interface KCSGenericRESTRequest()

@property (nonatomic, retain) NSMutableURLRequest *request;
@property (nonatomic) BOOL isMockRequest;
@property (nonatomic, retain) Class mockConnection;
@property (nonatomic) NSInteger retriesAttempted;
@property (nonatomic, copy) KCSConnectionCompletionBlock completionAction;
@property (nonatomic, copy) KCSConnectionFailureBlock failureAction;
@property (nonatomic, copy) KCSConnectionProgressBlock progressAction;
- (instancetype)initWithResource:(NSString *)resource usingMethod: (NSInteger)requestMethod;
@end

@implementation KCSGenericRESTRequest


+ (instancetype)requestForResource: (NSString *)resource usingMethod: (NSInteger)requestMethod withCompletionAction: (KCSConnectionCompletionBlock)complete failureAction:(KCSConnectionFailureBlock)failure progressAction: (KCSConnectionProgressBlock)progress
{
    KCSGenericRESTRequest* req = [[self alloc] initWithResource:resource usingMethod:requestMethod];
    req.completionAction = complete;
    req.failureAction = failure;
    req.progressAction = progress;
    
    return req;
}

- (instancetype)initWithResource:(NSString *)resource usingMethod: (NSInteger)requestMethod
{
    self = [super init];
    if (self){
        self.resourceLocation = resource; // I own this!
        _method = requestMethod;
        _completionAction = NULL;
        _progressAction = NULL;
        _failureAction = NULL;
        _isMockRequest = NO;
        _followRedirects = YES;
        _retriesAttempted = 0;
        _headers = [NSMutableDictionary dictionary];
        
        // Prepare to generate the request...
        KCSClient *kinveyClient = [KCSClient sharedClient];
        
        // NB: Not retained as it is only used in the building of _request
        NSURL *url = [NSURL URLWithString:resource];
        
        KCSLogNetwork(@"Requesting resource: %@", resource);
        _request = [NSMutableURLRequest requestWithURL:url cachePolicy:kinveyClient.cachePolicy timeoutInterval:kinveyClient.connectionTimeout];
    }
    return self;
}

- (void) dealloc
{
    _resourceLocation = nil;
    _headers = nil;
    
    self.completionAction = NULL;
    self.progressAction = NULL;
    self.failureAction = NULL;
}

#pragma mark -
// Prototype is to make compiler happy
+ (NSString *)getHTTPMethodForConstant:(NSInteger)constant
{
    switch (constant) {
        case kGetRESTMethod:
            return @"GET";
            break;
        case kPutRESTMethod:
            return @"PUT";
            break;
        case kPostRESTMethod:
            return @"POST";
            break;
        case kDeleteRESTMethod:
            return @"DELETE";
            break;
            
        default:
            return @"";
            break;
    }
}
- (void)start
{
    KCSConnection *connection;
    
    if (self.isMockRequest) {
        connection = [KCSConnectionPool connectionWithConnectionType:self.mockConnection];
    } else {
        connection = [KCSConnectionPool asyncConnection];
    }
    
    
    [self.request setHTTPMethod: [KCSGenericRESTRequest getHTTPMethodForConstant: self.method]];
    [self.request setHTTPShouldUsePipelining:self.method != kPostRESTMethod];
    
    for (NSString *key in [self.headers allKeys]) {
        [self.request setValue:[self.headers objectForKey:key] forHTTPHeaderField:key];
    }
        
    // Let the server know that we support GZip.
    [self.request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    
    if (!self.followRedirects){
        connection.followRedirects = NO;
    }
    
    [connection performRequest:self.request progressBlock:self.progressAction completionBlock:self.completionAction failureBlock:self.failureAction usingCredentials:nil];
}


@end
