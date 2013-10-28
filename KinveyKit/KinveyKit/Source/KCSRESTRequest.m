//
//  KCSRESTRequest.m
//  KinveyKit
//
//  Created by Brian Wilson on 11/28/11.
//  Copyright (c) 2011-2013 Kinvey. All rights reserved.
//

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
#import "KCSBase64.h"
#import "KCSRESTRequest.h"

// This is in Seconds!
#define KCS_RETRY_DELAY 0.05

// *cough* hack *cough*
#define MAX_DATE_STRING_LENGTH_K 40 
#define MAX_NUMBER_OF_RETRIES_K 10 / KCS_RETRY_DELAY

// KINVEY KCS API VERSION
#define KINVEY_KCS_API_VERSION_HEADER @"X-Kinvey-API-Version"
#define KINVEY_KCS_API_VERSION @"3"


void clogResource(NSString *resource, NSInteger requestMethod);
void clogResource(NSString *resource, NSInteger requestMethod)
{
    KCSLogDebug(@"cLogResource: (%@[%p], %d)", resource, (void *)resource, requestMethod);
}


NSString *getLogDate(void); // Make compiler happy...

NSString * getLogDate(void)
{
    time_t now = time(NULL);
    struct tm *t = gmtime(&now);
    
    char timestring[MAX_DATE_STRING_LENGTH_K];
    
    NSInteger len = strftime(timestring, MAX_DATE_STRING_LENGTH_K - 1, "%a, %d %b %Y %T %Z", t);
    assert(len < MAX_DATE_STRING_LENGTH_K);
    
    return [NSString stringWithCString:timestring encoding:NSASCIIStringEncoding];
}

@interface KCSGenericRESTRequest (KCSRestRequest)
@property (nonatomic, retain) NSMutableURLRequest *request;
@property (nonatomic) BOOL isMockRequest;
@property (nonatomic, retain) Class mockConnection;
@property (nonatomic) NSInteger retriesAttempted;
+ (NSString *)getHTTPMethodForConstant:(NSInteger)constant;
@end

@interface KCSRESTRequest ()
@property (nonatomic, strong) KCSConnection *connection;
@end

@implementation KCSRESTRequest

- (void)logResource: (NSString *)resource usingMethod:(NSInteger)requestMethod
{
    KCSLogNetwork(@"logResource: (%@[%p], %d)", resource, (void *)resource, requestMethod);
}

+ (instancetype) requestForResource:(NSString *)resource usingMethod:(NSInteger)requestMethod
{
    return [[self alloc] initWithResource:resource usingMethod:requestMethod];
}


- (instancetype) mockRequestWithMockClass:(Class)connection
{
    self.isMockRequest = YES;
    self.mockConnection = connection;
    return self;
}

- (instancetype) addHeaders:(NSDictionary*)theHeaders
{
    NSArray *keys = [theHeaders allKeys];
    
    for (NSString *key in keys) {
        [self.headers setObject:[theHeaders objectForKey:key] forKey:key];
    }
    
    return self;
}

- (void) setJsonBody:(id)bodyObject
{
    KCS_SBJsonWriter *writer = [[KCS_SBJsonWriter alloc] init];
    [self addBody:[writer dataWithObject:bodyObject]];
}

- (instancetype) addBody:(NSData *)theBody
{
    [self.request setHTTPBody:theBody];
    [self.request setValue:[NSString stringWithFormat:@"%ld", (long) [theBody length]] forHTTPHeaderField:@"Content-Length"];
    return self;
}

- (instancetype) withCompletionAction:(KCSConnectionCompletionBlock)complete
                        failureAction:(KCSConnectionFailureBlock)failure
                       progressAction: (KCSConnectionProgressBlock)progress
{
    self.completionAction = complete;
    self.progressAction = progress;
    self.failureAction = failure;
    
    return self;
}

// Modify known headers
- (void)setContentType: (NSString *)contentType
{
    [self.headers setObject:contentType forKey:@"Content-Type"];
}

- (void)setContentLength:(NSInteger)contentLength
{
    [self.headers setObject:@(contentLength) forKey:@"Content-Length"];
}

- (void)start
{
    KCSClient *kinveyClient = [KCSClient sharedClient];

    if (self.isMockRequest) {
        self.connection = [KCSConnectionPool connectionWithConnectionType:self.mockConnection];
    } else {
        self.connection = [KCSConnectionPool asyncConnection];
    }
    
    [self.request setHTTPMethod: [KCSGenericRESTRequest getHTTPMethodForConstant: self.method]];
    [self.request setHTTPShouldUsePipelining:YES];
    
    for (NSString *key in [self.headers allKeys]) {
        [self.request setValue:[self.headers objectForKey:key] forHTTPHeaderField:key];
    }
    
    // Add the Kinvey User-Agent
    [self.request setValue:[kinveyClient userAgent] forHTTPHeaderField:@"User-Agent"];
    
    // Add the Analytics header
    [self.request setValue:[kinveyClient.analytics headerString] forHTTPHeaderField:kinveyClient.analytics.analyticsHeaderName];
    
    // Add the API version
    [self.request setValue:KINVEY_KCS_API_VERSION forHTTPHeaderField:KINVEY_KCS_API_VERSION_HEADER];

    // Add the Date as a header
    [self.request setValue:getLogDate() forHTTPHeaderField:@"Date"];

    // Let the server know that we support GZip.
    [self.request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    
    // Let the server know we want wrapped json erors
    [self.request setValue:@"true" forHTTPHeaderField:@"X-Kinvey-ResponseWrapper"];
    
    if ([self.request.allHTTPHeaderFields objectForKey:@"Authorization"] == nil) {
        KCSAuthCredential* cred = [KCSAuthCredential credentialForURL:self.resourceLocation usingMethod:self.method];
        if (cred.requiresAuthentication){
            NSString* authString = [[cred credentials] authString];
            if (authString != nil) {
                [self.request setValue:authString forHTTPHeaderField:@"Authorization"];
            } else {
                // If authString is nil and we needed it (requiresAuthentication is true),
                // then this is a no-credentials error
                NSError* error = [NSError errorWithDomain:KCSNetworkErrorDomain code:KCSDeniedError userInfo:@{NSLocalizedDescriptionKey : @"No Authorization Found", NSLocalizedFailureReasonErrorKey : @"There is no active user/client and this request requires credentials.", NSURLErrorFailingURLStringErrorKey : self.resourceLocation}];
                self.failureAction(error);
                return;
            }
        }
    }
    
    self.connection.followRedirects = self.followRedirects;
    
    [self.connection performRequest:self.request progressBlock:self.progressAction completionBlock:self.completionAction failureBlock:self.failureAction usingCredentials:nil];
}

- (void) setAuth:(NSString*)username password:(NSString*)password
{
    NSString *authString = KCSbasicAuthString(username, password);
    [self.request setValue:authString forHTTPHeaderField:@"Authorization"];
}

- (void) cancel
{
    KCSLogNetwork(@"Cancelling request...");
    [self.connection cancel];
}
@end
