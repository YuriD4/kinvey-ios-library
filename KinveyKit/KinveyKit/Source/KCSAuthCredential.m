//
//  KCSAuthCredential.m
//  KinveyKit
//
//  Created by Brian Wilson on 1/17/12.
//  Copyright (c) 2012-2013 Kinvey. All rights reserved.
//

#import "KCSAuthCredential.h"
#import "KCSRESTRequest.h"
#import "KCSClient.h"
#import "KinveyUser.h"
#import "KCSLogManager.h"
#import "KCSBase64.h"
#import "KCSHiddenMethods.h"

enum {
    KCSAuthNoAuth = 0,
    KCSAuthBasicAuthAppKey = 1,
    KCSAuthBasicAuthUser = 2
};

NSInteger deriveAuth(NSString *URL, NSInteger method);
NSInteger deriveAuth(NSString *URL, NSInteger method)
{
    // Default to none
    NSInteger authType = KCSAuthNoAuth;
    KCSClient *client = [KCSClient sharedClient];
    
    if ([URL hasPrefix:client.appdataBaseURL]){
        //if is the root of appdata it's a ping - use basic auth
        authType = [URL isEqualToString:client.appdataBaseURL] ? KCSAuthBasicAuthAppKey : KCSAuthBasicAuthUser;
    } else if ([URL hasPrefix:client.resourceBaseURL]){
        authType = KCSAuthBasicAuthUser;
    } else if ([URL hasPrefix:client.userBaseURL]){
        // We need auth, but we're not sure what type yet
        // Per the user API if we're POSTING to the ROOT of the user API,
        // then we need App Key auth, otherwise we need user auth
        if (method == kPostRESTMethod && ([URL isEqualToString:client.userBaseURL] || [URL isEqualToString:[client.userBaseURL stringByAppendingString:@"login"]])) {
            authType = KCSAuthBasicAuthAppKey;
        } else {
            authType = KCSAuthBasicAuthUser;
        }
    } else if ([URL hasPrefix:client.rpcBaseURL]) {
        // for now just use app secret until rpc endpoints are added that requier user auth
        authType = KCSAuthBasicAuthAppKey;
    } else {
        // No auth known, this needs to be extensable in the future to add new methods
        authType = KCSAuthNoAuth;
    }
    
    
    return authType;
}

@interface KCSAuthCredential ()
@property (nonatomic) NSInteger authRequired;
@property (nonatomic, strong) NSURLCredential *appKeyAuth;
@property (nonatomic, strong) NSString *appKeyBase64;
@end

@implementation KCSAuthCredential

- (instancetype)initWithURL: (NSString *)URL withMethod: (NSInteger)method
{
    self = [super init];
    if (self){
        _URL = URL;
        _method = method;
        _authRequired = deriveAuth(_URL, _method);
        _appKeyAuth = [NSURLCredential credentialWithUser:[[KCSClient sharedClient] appKey] password:[[KCSClient sharedClient] appSecret] persistence:NSURLCredentialPersistenceNone];
        _appKeyBase64 = KCSbasicAuthString([[KCSClient sharedClient] appKey], [[KCSClient sharedClient] appSecret]);
    }
    return self;
}

+ (KCSAuthCredential *)credentialForURL: (NSString *)URL usingMethod: (NSInteger)method
{
    return [[KCSAuthCredential alloc] initWithURL:URL withMethod:method];
}

- (NSURLCredential *)NSURLCredential
{
    if (self.authRequired == KCSAuthNoAuth){
        return nil;
    } else if (self.authRequired == KCSAuthBasicAuthAppKey){
        return self.appKeyAuth;
    } else if (self.authRequired == KCSAuthBasicAuthUser){
        KCSUser *curUser = [[KCSClient sharedClient] currentUser];
        if (curUser == nil){
            // We need to start auth proceeding here
            if (![[KCSClient sharedClient] userAuthenticationInProgress]){
                // We're the first!
                [KCSUser initCurrentUser];
            }
            return nil;
        } else {
            return [NSURLCredential credentialWithUser:curUser.username password:curUser.password persistence:NSURLCredentialPersistenceNone];
        }
    }
    
    KCSLogError(@"The type of auth required for this request (in NSURLCredential) is not known: %d", self.authRequired);
    return nil;
}


- (NSString *)HTTPBasicAuthString
{
    KCSLogDebug(@"Request for Basic Auth String with authRequired: %d", self.authRequired);
    if (self.authRequired == KCSAuthNoAuth){
        return nil;
    } else if (self.authRequired == KCSAuthBasicAuthAppKey){
        KCSLogDebug(@"Using app key/app secret for auth: (%@, %@) => %@", [[KCSClient sharedClient] appKey], [[KCSClient sharedClient] appSecret], self.appKeyBase64);
        return self.appKeyBase64;
    } else if (self.authRequired == KCSAuthBasicAuthUser){
        KCSUser *curUser = [KCSUser activeUser];
        if (curUser == nil){
            KCSLogDebug(@"No current user, auth needed.");
            // We need to start auth proceeding here
            if (![[KCSClient sharedClient] userAuthenticationInProgress]){
                // We're the first!
                [KCSUser initCurrentUser];
            }
            return nil;
        } else {
            NSString *authString = nil;
            if (curUser.sessionAuth) {
                authString = [@"Kinvey " stringByAppendingString: curUser.sessionAuth];//KCSbase64EncodedStringFromData([curUser.sessionAuth dataUsingEncoding:NSUTF8StringEncoding]);
                KCSLogDebug(@"Current user found, using sessionauth (%@) => XXXXXXXXX", curUser.username);
            } else {
                authString = KCSbasicAuthString(curUser.username, curUser.password);
                KCSLogDebug(@"Current user found (%@, XXXXXXXXX) => XXXXXXXXX", curUser.username);
            }
            return authString;
        }
    }
    
    KCSLogError(@"The type of auth required for this request (in NSURLCredential) is not known: %d", self.authRequired);
    return nil;
}

- (BOOL)requiresAuthentication
{
    return self.authRequired != KCSAuthNoAuth;
}

@end
