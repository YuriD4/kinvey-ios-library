//
//  KCSBlobService.m
//  SampleApp
//
//  Created by Brian Wilson on 11/9/11.
//  Copyright (c) 2011 Kinvey. All rights reserved.
//

#import "KinveyHTTPStatusCodes.h"
#import "KCSBlobService.h"
#import "KCSClient.h"
#import "SBJson.h"
#import "KCSRESTRequest.h"
#import "KCSConnectionResponse.h"
#import "KCSErrorUtilities.h"
#import "KinveyErrorCodes.h"

@implementation KCSResourceResponse

@synthesize localFileName=_localFileName;
@synthesize resourceId=_resourceId;
@synthesize resource=_resource; // Set to nil on upload
@synthesize length=_length;
@synthesize streamingURL=_streamingURL;

+ (KCSResourceResponse *)responseWithFileName:(NSString *)localFile withResourceId:(NSString *)resourceId withStreamingURL:(NSString *)streamingURL withData:(NSData *)resource withLength:(NSInteger)length
{
    KCSResourceResponse *response = [[[KCSResourceResponse alloc] init] autorelease];
    response.localFileName = localFile;
    response.resourceId = resourceId;
    response.resource = resource;
    response.length = length;
    response.streamingURL = streamingURL;
    
    return response;
}

- (void)dealloc
{
    [_localFileName release];
    [_resourceId release];
    [_resource release];
    [_streamingURL release];
    [super dealloc];
}


@end

#pragma mark Blob Service

@implementation KCSResourceService

+ (void)downloadResource: (NSString *)resourceId
    withResourceDelegate: (id<KCSResourceDelegate>)delegate
         completionBlock: (KCSCompletionBlock)completionBlock
           progressBlock: (KCSProgressBlock)progressBlock
{
    NSString *resource = [[[KCSClient sharedClient] resourceBaseURL] stringByAppendingFormat:@"download-loc/%@", resourceId];
    KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:kGetRESTMethod];
    
    KCSConnectionCompletionBlock cBlock = ^(KCSConnectionResponse *response){
        if (response.responseCode != KCS_HTTP_STATUS_OK){
            KCS_SBJsonParser *parser = [[[KCS_SBJsonParser alloc] init] autorelease];
            NSString *failureJSON = [[parser objectWithData:response.responseData] description];
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Resource download failed."
                                                                               withFailureReason:[NSString stringWithFormat:@"JSON Error: %@", failureJSON]
                                                                          withRecoverySuggestion:@"Retry request based on information in JSON Error"
                                                                             withRecoveryOptions:nil];
            NSError *error = [NSError errorWithDomain:KCSResourceErrorDomain
                                                 code:[response responseCode]
                                             userInfo:userInfo];
            
            if (delegate){
                [delegate resourceServiceDidFailWithError:error];
            } else {
                completionBlock(nil, error);
            }
        } else {
            KCSResourceResponse *resourceResponse = [KCSResourceResponse responseWithFileName:nil withResourceId:resourceId withStreamingURL:nil withData:response.responseData withLength:[response.responseData length]];
            if (delegate){
                [delegate resourceServiceDidCompleteWithResult: resourceResponse];
            } else {
                completionBlock([NSArray arrayWithObject:resourceResponse], nil);
            }
        }
    };
    
    KCSConnectionFailureBlock fBlock = ^(NSError *error){
        if (delegate){
            [delegate resourceServiceDidFailWithError:error];
        } else {
            completionBlock(nil, error);
        }
    };
    
    KCSConnectionProgressBlock pBlock = ^(KCSConnectionProgress *connection){};
    
    [[request withCompletionAction:cBlock failureAction:fBlock progressAction:pBlock] start];
}

+ (void)downloadResource: (NSString *)resourceId withResourceDelegate: (id<KCSResourceDelegate>)delegate
{
    [KCSResourceService downloadResource:resourceId
                    withResourceDelegate:delegate
                         completionBlock:nil
                           progressBlock:nil];
}

+ (void)downloadResource:(NSString *)resourceId completionBlock:(KCSCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [KCSResourceService downloadResource:resourceId
                    withResourceDelegate:nil
                         completionBlock:completionBlock
                           progressBlock:progressBlock];
}


+ (void)downloadResource:(NSString *)resourceId
                  toFile:(NSString *)filename
    withResourceDelegate:(id<KCSResourceDelegate>)delegate
         completionBlock:(KCSCompletionBlock)completionBlock
           progressBlock:(KCSProgressBlock)progressBlock
{
    NSString *resource = [[[KCSClient sharedClient] resourceBaseURL] stringByAppendingFormat:@"download-loc/%@", resourceId];
    KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:kGetRESTMethod];
    
    KCSConnectionCompletionBlock cBlock = ^(KCSConnectionResponse *response){
        if (response.responseCode != KCS_HTTP_STATUS_OK){
            KCS_SBJsonParser *parser = [[[KCS_SBJsonParser alloc] init] autorelease];

            NSString *failureJSON = [[parser objectWithData:response.responseData] description];
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Resource download to file failed."
                                                                               withFailureReason:[NSString stringWithFormat:@"JSON Error: %@", failureJSON]
                                                                          withRecoverySuggestion:@"Retry request based on information in JSON Error"
                                                                             withRecoveryOptions:nil];
            NSError *error = [NSError errorWithDomain:KCSResourceErrorDomain
                                                 code:[response responseCode]
                                             userInfo:userInfo];
            
            if (delegate){
                [delegate resourceServiceDidFailWithError:error];
            } else {
                completionBlock(nil, error);
            }
        } else {
            // We have a valid NSData object, right now this is the only way I know to complete this request...
            NSError *fileError = nil;
            BOOL didWriteSuccessfully = [response.responseData writeToFile:filename
                                                                   options:NSDataWritingAtomic
                                                                     error:&fileError];
            
            if (didWriteSuccessfully){
                KCSResourceResponse *resourceResponse = [KCSResourceResponse responseWithFileName:filename 
                                                                                   withResourceId:resourceId 
                                                                                 withStreamingURL:nil
                                                                                         withData:nil
                                                                                       withLength:[response.responseData length]];
                if (delegate){
                    [delegate resourceServiceDidCompleteWithResult:resourceResponse];
                } else {
                    completionBlock([NSArray arrayWithObject:resourceResponse], nil);
                }
            } else {
                if (delegate){
                    // We failed to write the file
                    [delegate resourceServiceDidFailWithError:fileError];
                } else {
                    completionBlock(nil, fileError);
                }
            }
        }
    };
    
    KCSConnectionFailureBlock fBlock = ^(NSError *error){
        if (delegate){
            [delegate resourceServiceDidFailWithError:error];
        } else {
            completionBlock(nil, error);
        }
    };
    
    KCSConnectionProgressBlock pBlock = ^(KCSConnectionProgress *connection){};
    
    [[request withCompletionAction:cBlock failureAction:fBlock progressAction:pBlock] start];
}

+ (void)downloadResource:(NSString *)resourceId toFile:(NSString *)filename withResourceDelegate:(id<KCSResourceDelegate>)delegate
{
    [KCSResourceService downloadResource:resourceId
                                  toFile:filename
                    withResourceDelegate:delegate
                         completionBlock:nil
                           progressBlock:nil];
}

+ (void)downloadResource:(NSString *)resourceId toFile:(NSString *)filename completionBlock:(KCSCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [KCSResourceService downloadResource:resourceId
                                  toFile:filename
                    withResourceDelegate:nil
                         completionBlock:completionBlock
                           progressBlock:progressBlock];
}

+ (void)saveLocalResource:(NSString *)filename withDelegate:(id<KCSResourceDelegate>)delegate
{
    [KCSResourceService saveLocalResource:filename toResource:[filename lastPathComponent] withDelegate:delegate];
}

+ (void)saveLocalResource:(NSString *)filename completionBlock:(KCSCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [KCSResourceService saveLocalResource:filename
                               toResource:[filename lastPathComponent]
                          completionBlock:completionBlock
                            progressBlock:progressBlock];
}


+ (void)saveLocalResourceWithURL:(NSURL *)URL
                      toResource:(NSString *)resourceId
                    withDelegate:(id<KCSResourceDelegate>)delegate
                 completionBlock:(KCSCompletionBlock)completionBlock
                   progressBlock:(KCSProgressBlock)progressBlock
{
    // Not sure what the best read options to use here are, so not providing any.  Hopefully the defaults are ok.
    NSData *data = [NSData dataWithContentsOfURL:URL];
    if (data){
        // We read in the data, we can upload it.
        if (delegate){
            [KCSResourceService saveData:data toResource:resourceId withDelegate:delegate];
        } else {
            [KCSResourceService saveData:data toResource:resourceId completionBlock:completionBlock progressBlock:progressBlock];
        }
    } else {
        // We had an issue..., we didn't upload, so call the failure method of the delegate
        NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Updload failed"
                                                                           withFailureReason:@"Unable to determine why, URL didn't load"
                                                                      withRecoverySuggestion:@"Unknown"
                                                                         withRecoveryOptions:nil];
        NSError *err = [NSError errorWithDomain:KCSResourceErrorDomain code:KCSFileError userInfo:userInfo];
        
        if (delegate){
            [delegate resourceServiceDidFailWithError:err];
        } else {
            completionBlock(nil, err);
        }
    }

}

+ (void)saveLocalResourceWithURL:(NSURL *)URL toResource:(NSString *)resourceId withDelegate:(id<KCSResourceDelegate>)delegate
{
    [KCSResourceService saveLocalResourceWithURL:URL
                                      toResource:resourceId
                                    withDelegate:delegate
                                 completionBlock:nil
                                   progressBlock:nil];
}

+ (void)saveLocalResourceWithURL:(NSURL *)URL toResource:(NSString *)resourceId completionBlock:(KCSCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [KCSResourceService saveLocalResourceWithURL:URL
                                      toResource:resourceId
                                    withDelegate:nil
                                 completionBlock:completionBlock
                                   progressBlock:progressBlock];
    
}


+ (void)saveLocalResourceWithURL:(NSURL *)URL withDelegate:(id<KCSResourceDelegate>)delegate
{
    [KCSResourceService saveLocalResourceWithURL:URL toResource:[URL lastPathComponent] withDelegate:delegate];
}

+ (void)saveLocalResourceWithURL:(NSURL *)URL completionBlock:(KCSCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [KCSResourceService saveLocalResourceWithURL:URL toResource:[URL lastPathComponent] completionBlock:completionBlock progressBlock:progressBlock];
}



+ (void)getStreamingURLForResource:(NSString *)resourceId
              withResourceDelegate:(id<KCSResourceDelegate>)delegate
                   completionBlock:(KCSCompletionBlock)completionBlock
                     progressBlock:(KCSProgressBlock)progressBlock
{
    NSString *resource = [[[KCSClient sharedClient] resourceBaseURL] stringByAppendingFormat:@"download-loc/%@", resourceId];
    KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:kGetRESTMethod];
    
    KCSConnectionCompletionBlock cBlock = ^(KCSConnectionResponse *response){
        // This needs to be REDIRECT, otherwise something is messed up!
        if (response.responseCode != KCS_HTTP_STATUS_REDIRECT){
            KCS_SBJsonParser *parser = [[[KCS_SBJsonParser alloc] init] autorelease];
            NSString *failureJSON = [[parser objectWithData:response.responseData] description];
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Get streaming URL failed."
                                                                               withFailureReason:[NSString stringWithFormat:@"JSON Error: %@", failureJSON]
                                                                          withRecoverySuggestion:@"Retry request based on information in JSON Error"
                                                                             withRecoveryOptions:nil];
            NSError *error = [NSError errorWithDomain:KCSResourceErrorDomain
                                                 code:[response responseCode]
                                             userInfo:userInfo];
            
            if (error){
                [delegate resourceServiceDidFailWithError:error];
            } else {
                completionBlock(nil, error);
            }
        } else {
            NSString *URL = [[response.responseHeaders objectForKey:@"Location"] retain];
            
            if (!URL){
                NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"URL for streaming resource not available."
                                                                                   withFailureReason:@"No 'Location' header found in HTTP redirect."
                                                                              withRecoverySuggestion:@"No client recovery available, contact Kinvey Support."
                                                                                 withRecoveryOptions:nil];
                NSError *error = [NSError errorWithDomain:KCSResourceErrorDomain
                                                     code:KCSUnexpectedResultFromServerError
                                                 userInfo:userInfo];
                
                if (delegate){
                    [delegate resourceServiceDidFailWithError:error];
                } else {
                    completionBlock(nil, error);
                }
            } else {
                // NB: The delegate must take ownership of this resource!
                KCSResourceResponse *resourceResponse = [KCSResourceResponse responseWithFileName:nil withResourceId:resourceId withStreamingURL:URL withData:nil withLength:0];
                if (delegate){
                    [delegate resourceServiceDidCompleteWithResult:resourceResponse];
                } else {
                    completionBlock([NSArray arrayWithObject:resourceResponse], nil);
                }
                [URL release];
            }
        }
    };
    
    KCSConnectionFailureBlock fBlock = ^(NSError *error){
        if (delegate){
            [delegate resourceServiceDidFailWithError:error];
        } else {
            completionBlock(nil, error);
        }
    };
    
    KCSConnectionProgressBlock pBlock = ^(KCSConnectionProgress *connection){};
    
    request.followRedirects = NO;
    
    [[request withCompletionAction:cBlock failureAction:fBlock progressAction:pBlock] start];

}

+ (void)getStreamingURLForResource:(NSString *)resourceId withResourceDelegate:(id<KCSResourceDelegate>)delegate
{
    [KCSResourceService getStreamingURLForResource:resourceId withResourceDelegate:delegate
                                   completionBlock:nil progressBlock:nil];
}

+ (void)getStreamingURLForResource:(NSString *)resourceId completionBlock:(KCSCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [KCSResourceService getStreamingURLForResource:resourceId withResourceDelegate:nil completionBlock:completionBlock progressBlock:progressBlock];
}


+ (void)saveLocalResource:(NSString *)filename
               toResource:(NSString *)resourceId 
             withDelegate:(id<KCSResourceDelegate>)delegate
          completionBlock:(KCSCompletionBlock)completionBlock 
            progressBlock:(KCSProgressBlock)progressBlock
{
    NSError *fileOpError = nil;
    // Not sure what the best read options to use here are, so not providing any.  Hopefully the defaults are ok.
    NSData *data = [NSData dataWithContentsOfFile:filename options:0 error:&fileOpError];
    if (data){
        // We read in the data, we can upload it.
        if (delegate){
            [KCSResourceService saveData:data toResource:resourceId withDelegate:delegate];
        } else {
            [KCSResourceService saveData:data toResource:resourceId completionBlock:completionBlock progressBlock:progressBlock];
        }
    } else {
        // We had an issue..., we didn't upload, so call the failure method of the delegate
        if (delegate){
            [delegate resourceServiceDidFailWithError:fileOpError];
        } else {
            completionBlock(nil, fileOpError);
        }
    }
}

+ (void)saveLocalResource:(NSString *)filename
               toResource:(NSString *)resourceId 
             withDelegate:(id<KCSResourceDelegate>)delegate
{
    [KCSResourceService saveLocalResource:filename toResource:resourceId withDelegate:delegate completionBlock:nil progressBlock:nil];
}

+ (void)saveLocalResource:(NSString *)filename
               toResource:(NSString *)resourceId 
          completionBlock:(KCSCompletionBlock)completionBlock 
            progressBlock:(KCSProgressBlock)progressBlock
{
    [KCSResourceService saveLocalResource:filename toResource:resourceId withDelegate:nil completionBlock:completionBlock progressBlock:progressBlock];
}

+ (void)saveData:(NSData *)data 
      toResource:(NSString *)resourceId 
    withDelegate:(id<KCSResourceDelegate>)delegate
 completionBlock:(KCSCompletionBlock)completionBlock 
   progressBlock:(KCSProgressBlock)progressBlock
{
    NSString *resource = [[[KCSClient sharedClient] resourceBaseURL] stringByAppendingFormat:@"upload-loc/%@", resourceId];
    KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:kGetRESTMethod];

    KCSConnectionFailureBlock fBlock = ^(NSError *error){
        if (delegate){
            [delegate resourceServiceDidFailWithError:error];
        } else {
            completionBlock(nil, error);
        }
    };
    
    KCSConnectionProgressBlock pBlock = ^(KCSConnectionProgress *connection){};
    
    KCSConnectionCompletionBlock userCallback = ^(KCSConnectionResponse *response){
        if (response.responseCode != KCS_HTTP_STATUS_CREATED){
            NSString *xmlData = [[[NSString alloc] initWithData:response.responseData encoding:NSUTF8StringEncoding] autorelease];
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Saving data to the resource service failed."
                                                                               withFailureReason:[NSString stringWithFormat:@"XML Error: %@", xmlData]
                                                                          withRecoverySuggestion:@"Retry request based on information in XML Error"
                                                                             withRecoveryOptions:nil];
            NSError *error = [NSError errorWithDomain:KCSResourceErrorDomain
                                                 code:[response responseCode]
                                             userInfo:userInfo];
            
            if (delegate){
                [delegate resourceServiceDidFailWithError:error];
            } else {
                completionBlock(nil, error);
            }

        } else {
            // I feel like we should have a length here, but I might not be saving that response...
            KCSResourceResponse *resourceResponse = [KCSResourceResponse responseWithFileName:nil withResourceId:resourceId withStreamingURL:nil withData:nil withLength:0];
            if (delegate){
                [delegate resourceServiceDidCompleteWithResult:resourceResponse];
            } else {
                completionBlock([NSArray arrayWithObject:resourceResponse], nil);
            }
        }
    };
    
    KCSConnectionCompletionBlock cBlock = ^(KCSConnectionResponse *response){
        KCS_SBJsonParser *parser = [[[KCS_SBJsonParser alloc] init] autorelease];
        NSDictionary *jsonData = [parser objectWithData:response.responseData];
        if (response.responseCode != KCS_HTTP_STATUS_OK){
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Getting the resource service save location failed."
                                                                               withFailureReason:[NSString stringWithFormat:@"JSON Error: %@", jsonData]
                                                                          withRecoverySuggestion:@"Retry request based on information in JSON Error"
                                                                             withRecoveryOptions:nil];
            NSError *error = [NSError errorWithDomain:KCSResourceErrorDomain
                                                 code:[response responseCode]
                                             userInfo:userInfo];
            
            if (delegate){
                [delegate resourceServiceDidFailWithError:error];
            } else {
                completionBlock(nil, error);
            }
        } else {
            NSString *newResource = [jsonData valueForKey:@"URI"];
            KCSRESTRequest *newRequest = [KCSRESTRequest requestForResource:newResource usingMethod:kPutRESTMethod];
            [newRequest addBody:data];
            [newRequest setContentType:KCS_DATA_TYPE];
            [[newRequest withCompletionAction:userCallback failureAction:fBlock progressAction:pBlock] start];
        }
    };

    [[request withCompletionAction:cBlock failureAction:fBlock progressAction:pBlock] start];

}

+ (void)saveData:(NSData *)data 
      toResource:(NSString *)resourceId 
    withDelegate:(id<KCSResourceDelegate>)delegate
{
    [KCSResourceService saveData:data toResource:resourceId withDelegate:delegate completionBlock:nil progressBlock:nil];
}

+ (void)saveData:(NSData *)data 
      toResource:(NSString *)resourceId 
 completionBlock:(KCSCompletionBlock)completionBlock 
   progressBlock:(KCSProgressBlock)progressBlock
{
    [KCSResourceService saveData:data toResource:resourceId withDelegate:nil completionBlock:completionBlock progressBlock:progressBlock];
}

+ (void)deleteResource:(NSString *)resourceId 
          withDelegate:(id<KCSResourceDelegate>)delegate
       completionBlock:(KCSCompletionBlock)completionBlock 
         progressBlock:(KCSProgressBlock)progressBlock
{
    NSString *resource = [[[KCSClient sharedClient] resourceBaseURL] stringByAppendingFormat:@"remove-loc/%@", resourceId];
    KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:kGetRESTMethod];

    
    KCSConnectionFailureBlock fBlock = ^(NSError *error){
        if (delegate){
            [delegate resourceServiceDidFailWithError:error];
        } else {
            completionBlock(nil, error);
        }
    };
    
    KCSConnectionProgressBlock pBlock = ^(KCSConnectionProgress *connection){};
    
    KCSConnectionCompletionBlock userCallback = ^(KCSConnectionResponse *response){
        if (response.responseCode != KCS_HTTP_STATUS_ACCEPTED){
            NSString *xmlData = [[[NSString alloc] initWithData:response.responseData encoding:NSUTF8StringEncoding] autorelease];
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Deleting resource from resource service failed."
                                                                               withFailureReason:[NSString stringWithFormat:@"XML Error: %@", xmlData]
                                                                          withRecoverySuggestion:@"Retry request based on information in XML Error"
                                                                             withRecoveryOptions:nil];
            NSError *error = [NSError errorWithDomain:KCSResourceErrorDomain
                                                 code:[response responseCode]
                                             userInfo:userInfo];
            
            if (delegate){
                [delegate resourceServiceDidFailWithError:error];
            } else {
                completionBlock(nil, error);
            }

        } else {
            // I feel like we should have a length here, but I might not be saving that response...
            KCSResourceResponse *resourceResponse = [KCSResourceResponse responseWithFileName:nil withResourceId:nil withStreamingURL:nil withData:nil withLength:0];
            if (delegate){
                [delegate resourceServiceDidCompleteWithResult:resourceResponse];
            } else {
                completionBlock([NSArray arrayWithObject:resourceResponse], nil);
            }
        }

    };
    
    KCSConnectionCompletionBlock cBlock = ^(KCSConnectionResponse *response){
        KCS_SBJsonParser *parser = [[[KCS_SBJsonParser alloc] init] autorelease];
        NSDictionary *jsonData = [parser objectWithData:response.responseData];
        if (response.responseCode != KCS_HTTP_STATUS_OK){
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Getting delete location failed."
                                                                               withFailureReason:[NSString stringWithFormat:@"JSON Error: %@", jsonData]
                                                                          withRecoverySuggestion:@"Retry request based on information in JSON Error"
                                                                             withRecoveryOptions:nil];
            NSError *error = [NSError errorWithDomain:KCSResourceErrorDomain
                                                 code:[response responseCode]
                                             userInfo:userInfo];
            
            if (delegate){
                [delegate resourceServiceDidFailWithError:error];
            } else {
                completionBlock(nil, error);
            }
        } else {
            NSString *newResource = [jsonData valueForKey:@"URI"];
            KCSRESTRequest *newRequest = [KCSRESTRequest requestForResource:newResource usingMethod:kDeleteRESTMethod];
            [[newRequest withCompletionAction:userCallback failureAction:fBlock progressAction:pBlock] start];
        }
    };

    [[request withCompletionAction:cBlock failureAction:fBlock progressAction:pBlock] start];
}

+ (void)deleteResource:(NSString *)resourceId 
          withDelegate:(id<KCSResourceDelegate>)delegate
{
    [KCSResourceService deleteResource:resourceId withDelegate:delegate completionBlock:nil progressBlock:nil];
}

+ (void)deleteResource:(NSString *)resourceId 
       completionBlock:(KCSCompletionBlock)completionBlock 
         progressBlock:(KCSProgressBlock)progressBlock
{
    [KCSResourceService deleteResource:resourceId withDelegate:nil completionBlock:completionBlock progressBlock:progressBlock];
}

@end
