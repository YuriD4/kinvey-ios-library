//
//  KCSDataStore.m
//  KinveyKit
//
//  Created by Michael Katz on 5/23/13.
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


#import "KCSDataStore.h"

#import "KinveyCoreInternal.h"
#import "KinveyDataStoreInternal.h"

#define kKCSMaxReturnSize 10000


@interface KCSDataStore ()
@property (nonatomic, copy) NSString* collectionName;
@property (nonatomic, retain) NSString* route;
@property (nonatomic) BOOL cacheEnabled;
@end

@implementation KCSDataStore

- (instancetype) initWithCollection:(NSString*)collection
{
    NSParameterAssert(collection);
    
    self = [super init];
    if (self) {
        KK2(Have collection object supply these and get rid of cln names?)
        _collectionName = collection;
        if ([_collectionName isEqualToString:KCSUserCollectionName]) {
            _route = KCSRESTRouteUser;
        } else if ([_collectionName isEqualToString:KCSFileStoreCollectionName]) {
            _route = KCSRESTRouteBlob;
        } else {
            _route = KCSRESTRouteAppdata;
        }
    }
    return self;
}

#pragma mark - READ

- (void) getAll:(KCSDataStoreCompletion)completion
{
    [self query:nil options:@{KCSRequestLogMethod} completion:completion];
}

- (void) query:(KCSQuery2*)query options:(NSDictionary*)options completion:(KCSDataStoreCompletion)completion
{
    NSParameterAssert(completion);
    if (self.collectionName == nil) {
        [[NSException exceptionWithName:NSInternalInconsistencyException reason:@"No collection set in data store" userInfo:nil] raise];
    }
    
    NSDictionary* reqOptions = @{KCSRequestLogMethod}; //start here and add what params are passed in
    reqOptions = [reqOptions dictionaryByAddingDictionary:options];
    
    KCSRequest2* request = [KCSRequest2 requestWithCompletion:^(KCSNetworkResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
        } else {
            NSArray* elements = [response jsonObject];
            if ([elements count] == kKCSMaxReturnSize) {
                KCSLogForcedWarn(KCS_LOG_CONTEXT_DATA, @"Results returned exactly %d items. This is the server limit, so there may more entities that match the query. Try again with a more specific query or use limit and skip modifiers to get all the data.", kKCSMaxReturnSize);
            }
            completion(elements, nil);
        }
    }
                                                        route:KCSRESTRouteAppdata
                                                      options:reqOptions
                                                  credentials:[KCSUser activeUser]];
    request.path = @[_collectionName];
    request.queryString = [query escapedQueryString];
    [request start];
}

#pragma mark - Count

- (void) countAll:(KCSDataStoreCountCompletion)completion
{
    KCS_BREAK
}

- (void) countQuery:(KCSQuery2*)query completion:(KCSDataStoreCountCompletion)completion
{
    KCS_BREAK
}

#pragma mark - Deletion
- (void) deleteEntity:(NSString*)_id completion:(KCSDataStoreCountCompletion)completion
{
    if (!_id) [[NSException exceptionWithName:NSInvalidArgumentException reason:@"_id is nil" userInfo:nil] raise];
    
    KCSRequest2* request = [KCSRequest2 requestWithCompletion:^(KCSNetworkResponse *response, NSError *error) {
        NSUInteger count = 0;
        if (!error) {
            NSDictionary* responseDict = [response jsonObject];
            count = [responseDict[@"count"] unsignedIntegerValue];
        }
        completion(count, error);
    }
                                                        route:self.route
                                                      options:@{KCSRequestLogMethod}
                                                  credentials:[KCSUser activeUser]];
    request.path = @[self.collectionName, _id];
    request.method = KCSRESTMethodDELETE;
    [request start];
}

- (void) deleteByQuery:(KCSQuery2*)query completion:(KCSDataStoreCountCompletion)completion
{
    if (!query) [[NSException exceptionWithName:NSInvalidArgumentException reason:@"query is nil" userInfo:nil] raise];
    
    KCSRequest2* request = [KCSRequest2 requestWithCompletion:^(KCSNetworkResponse *response, NSError *error) {
        NSUInteger count = 0;
        if (!error) {
            NSDictionary* responseDict = [response jsonObject];
            count = [responseDict[@"count"] unsignedIntegerValue];
        }
        completion(count, error);
    }
                                                        route:self.route
                                                      options:@{KCSRequestLogMethod}
                                                  credentials:[KCSUser activeUser]];
    request.path = @[self.collectionName];
    request.queryString = [query escapedQueryString];
    request.method = KCSRESTMethodDELETE;
    [request start];

}


@end
