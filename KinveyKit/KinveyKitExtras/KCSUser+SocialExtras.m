//
//  KCSUser+SocialExtras.m
//  KinveyKit
//
//  Created by Michael Katz on 9/18/12.
//  Copyright (c) 2012-2014 Kinvey. All rights reserved.
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


#import "KCSUser+SocialExtras.h"

#import "KCSErrorUtilities.h"

#import <Social/Social.h>
#import <Accounts/Accounts.h>

#import "KCSLinkedInHelper.h"
#import "KinveyCoreInternal.h"
#import "KinveySocialInternal.h"
#import "KCSRequest+Private.h"

@implementation KCSUser (SocialExtras)

+ (BOOL) checkForTwitterKeys
{
    NSString* twitterKey = [[KCSClient sharedClient].options objectForKey:KCS_TWITTER_CLIENT_KEY];
    NSString* twitterSecret = [[KCSClient sharedClient].options objectForKey:KCS_TWITTER_CLIENT_SECRET];
    return [twitterKey length] > 0 && [twitterSecret length] > 0;
}

+ (BOOL) checkForTwitterCredentials
{
    #if TARGET_OS_IPHONE
        return [SLComposeViewController isAvailableForServiceType:SLServiceTypeTwitter];
    #else
        NSSharingService *tweetSharingService = [NSSharingService sharingServiceNamed:NSSharingServiceNamePostOnTwitter];
        return [tweetSharingService canPerformWithItems:nil];
    #endif
}

+ (void) getAccessDictionaryFromTwitterFromPrimaryAccount:(KCSLocalCredentialBlock)completionBlock
{
    [self getAccessDictionaryFromTwitterFromTwitterAccounts:completionBlock accountChooseBlock:^ACAccount *(NSArray *twitterAccounts) {
        return twitterAccounts[0];
    }];
}

+(KCSRequest*)getAccessDictionaryFromTwitterFromTwitterAccounts:(KCSLocalCredentialBlock)completionBlock
                                             accountChooseBlock:(ACAccount* (^)(NSArray* twitterAccounts))chooseBlock
{
    //  Check to make sure that the user has added his credentials
    BOOL hasKeys = [self checkForTwitterKeys];
    BOOL hasTwitterCred = [self checkForTwitterCredentials];
    if (hasKeys && hasTwitterCred) {
        
        //
        //  Step 1)  Ask Twitter for a special request_token for reverse auth
        //
        NSString* urlStr = @"https://api.twitter.com/oauth/request_token";
        
        // "reverse_auth" is a required parameter
        NSString* reversAuthParams = @"x_auth_mode=reverse_auth&";
        
        //  Create the authorization header and attach to our request
        NSData *bodyData = [reversAuthParams dataUsingEncoding:NSUTF8StringEncoding];
        NSString* twitterKey = [[KCSClient sharedClient].options objectForKey:KCS_TWITTER_CLIENT_KEY];
        NSString* twitterSecret = [[KCSClient sharedClient].options objectForKey:KCS_TWITTER_CLIENT_SECRET];
        
        KCSSocialRequest* request = [[KCSSocialRequest alloc] initWithApiKey:twitterKey secret:twitterSecret token:nil tokenSecret:nil additionalKeys:nil body:bodyData url:urlStr httpMethod:KCSRESTMethodPOST];
        request.completionBlock =  ^(KCSNetworkResponse *response, NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionBlock(nil, error);
                });
            } else {
                NSString *signedReverseAuthSignature = [response stringValue];
                
                //
                //  Step 2)  Ask Twitter for the user's auth token and secret
                //           include x_reverse_auth_target=CK2 and x_reverse_auth_parameters=signedReverseAuthSignature parameters
                //
                NSString* twitterKey = [[KCSClient sharedClient].options objectForKey:KCS_TWITTER_CLIENT_KEY];
                
                NSDictionary *step2Params = @{@"x_reverse_auth_target" : twitterKey, @"x_reverse_auth_parameters" : signedReverseAuthSignature};
                NSURL *authTokenURL = [NSURL URLWithString:@"https://api.twitter.com/oauth/access_token"];
                
                SLRequest* step2Request = [SLRequest requestForServiceType:SLServiceTypeTwitter requestMethod:SLRequestMethodPOST URL:authTokenURL parameters:step2Params];
                
                //  Obtain the user's permission to access the store
                //
                //  NB: You *MUST* keep the ACAccountStore around for as long as you need an ACAccount around.  See WWDC 2011 Session 124 for more info.
                ACAccountStore* accountStore = [[ACAccountStore alloc] init];
                ACAccountType *twitterType = [accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
                
                [accountStore requestAccessToAccountsWithType:twitterType options:nil completion:^(BOOL granted, NSError *error) {
                    if (!granted) {
                        NSError* tokenError =[KCSErrorUtilities createError:nil description:@"User rejected access to Twitter account" errorCode:KCSDeniedError domain:KCSUserErrorDomain requestId:nil sourceError:error];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completionBlock(nil, tokenError);
                        });
                    } else {
                        // obtain all the local account instances
                        NSArray *accounts = [accountStore accountsWithAccountType:twitterType];
                        
                        ACAccount* acountToUse = chooseBlock(accounts);
                        
                        // we can assume that we have at least one account thanks to +[TWTweetComposeViewController canSendTweet], let's return it
                        [step2Request setAccount:acountToUse];
                        [step2Request performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
                            if (!responseData || ((NSHTTPURLResponse*)urlResponse).statusCode >= 400) {
                                NSError* tokenError = [KCSErrorUtilities createError:nil description:@"Unable to obtain a Twitter access token" errorCode:KCSDeniedError domain:KCSUserErrorDomain requestId:nil sourceError:error];
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    completionBlock(nil, tokenError);
                                });
                            }
                            else {
                                NSString *responseStr = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
                                //will get back in the form of oauth_token=XXXX&oauth_token_secret=YYYY&user_id=ZZZZ&screen_name=AAAAA
                                NSMutableDictionary* dictionary = [NSMutableDictionary dictionaryWithCapacity:2];
                                NSArray* components = [responseStr componentsSeparatedByString:@"&"];
                                for (NSString* component in components) {
                                    NSArray* items = [component componentsSeparatedByString:@"="];
                                    if (items.count == 2) {
                                        NSString* key = [items objectAtIndex:0];
                                        if ([key isEqualToString:@"oauth_token"]) {
                                            [dictionary setValue:[items objectAtIndex:1] forKey:@"access_token"];
                                        } else if ([key isEqualToString:@"oauth_token_secret"]) {
                                            [dictionary setValue:[items objectAtIndex:1] forKey:@"access_token_secret"];
                                        }
                                    }
                                }
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    completionBlock(dictionary, nil);
                                });
                            }
                        }];
                    }
                }];
            }
        };
        return [KCSRequest requestWithNetworkOperation:[request start]];
    } else {
        NSDictionary* info;
        NSString* description;
        if (!hasKeys) {
            description = @"Cannot use Twitter reverse auth without consumer app information";
            info = [KCSErrorUtilities createErrorUserDictionaryWithDescription:description withFailureReason:@"Missing Consumer Key and/or Consumer Secret" withRecoverySuggestion:@"Set KCS_TWITTER_CLIENT_KEY and KCS_TWITTER_CLIENT_SECRET in the Kinvey client options dictionary" withRecoveryOptions:nil];
        } else {
            description = @"Twitter account not configured in settings";
            info = [KCSErrorUtilities createErrorUserDictionaryWithDescription:description withFailureReason:nil withRecoverySuggestion:@"Configure twitter account in settings" withRecoveryOptions:nil];
        }
        NSError* error = [KCSErrorUtilities createError:info description:description errorCode:KCSDeniedError domain:KCSUserErrorDomain requestId:nil];
        completionBlock(nil, error);
        return nil;
    }
}

+ (void) getAccessDictionaryFromLinkedIn:(KCSLocalCredentialBlock)completionBlock permissions:(NSString*)permissions usingWebView:(KCSWebViewClass*) webview
{
    if (permissions == nil) permissions = @"r_basicprofile";
    
    NSString* linkedInKey = [[KCSClient sharedClient].options objectForKey:KCS_LINKEDIN_API_KEY];
    NSString* linkedInSecret = [[KCSClient sharedClient].options objectForKey:KCS_LINKEDIN_SECRET_KEY];
    NSString* linkedInAcceptRedirect = [[KCSClient sharedClient].options objectForKey:KCS_LINKEDIN_ACCEPT_REDIRECT];
    NSString* linkedInCancelRedirect = [[KCSClient sharedClient].options objectForKey:KCS_LINKEDIN_CANCEL_REDIRECT];
    
    if (linkedInKey == nil || linkedInSecret == nil || linkedInAcceptRedirect == nil || linkedInCancelRedirect == nil) {
        NSString* description = @"Cannot use Linked In authentication without consumer app information";
        NSDictionary* info = [KCSErrorUtilities createErrorUserDictionaryWithDescription:description withFailureReason:@"Missing one or more of: Linked In api key, secret key, accept redirect or cancel redirect." withRecoverySuggestion:@"Set KCS_LINKEDIN_API_KEY, KCS_LINKEDIN_SECRET_KEY, KCS_LINKEDIN_ACCEPT_REDIRECT, and KCS_LINKEDIN_CANCEL_REDIRECT in the Kinvey client options dictionary" withRecoveryOptions:nil];
        
        NSError* error = [KCSErrorUtilities createError:info description:description errorCode:KCSDeniedError domain:KCSUserErrorDomain requestId:nil];
        completionBlock(nil, error);
        
    } else {
        static KCSLinkedInHelper* helper;
        helper = [[KCSLinkedInHelper alloc] init];
        helper.apiKey = linkedInKey;
        helper.secretKey = linkedInSecret;
        helper.acceptRedirect = linkedInAcceptRedirect;
        helper.cancelRedirect = linkedInCancelRedirect;
        helper.webview = webview;
        
        [helper requestToken:permissions completionBlock:^(NSDictionary *accessDictOrNil, NSError *errorOrNil) {
            completionBlock(accessDictOrNil, errorOrNil);
        }];
    }
}


+ (void) getAccessDictionaryFromLinkedIn:(KCSLocalCredentialBlock)completionBlock usingWebView:(KCSWebViewClass*) webview
{
    [self getAccessDictionaryFromLinkedIn:completionBlock permissions:@"r_basicprofile" usingWebView:webview];
}



@end


