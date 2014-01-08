//
//  KCSAppdataStore.m
//  KinveyKit
//
//  Created by Brian Wilson on 5/1/12.
//  Copyright (c) 2012-2013 Kinvey. All rights reserved.
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

#import "KCSAppdataStore.h"

#import "KCSGroup.h"
#import "KCSReduceFunction.h"
#import "KCS_SBJson.h"
#import "KCSRESTRequest.h"
#import "KCSConnectionResponse.h"
#import "KCSLogManager.h"
#import "KinveyHTTPStatusCodes.h"
#import "KinveyErrorCodes.h"
#import "KCSErrorUtilities.h"
#import "KCSConnectionProgress.h"
#import "KCSQuery.h"
#import "KinveyEntity.h"
#import "NSArray+KinveyAdditions.h"
#import "NSString+KinveyAdditions.h"
#import "KCSObjectMapper.h"
#import "KCSHiddenMethods.h"
#import "KCSReachability.h"
#import "KCSSaveGraph.h"
#import "KCSBlobService.h"
#import "KCSFile.h"

#import "KCSObjectCache.h"
#import "KCSRequest2.h"
#import "KCSQuery2+KCSInternal.h"
#import "NSError+KinveyKit.h"
#import "KCSClient+KinveyDataStore.h"
#import "KinveyDataStore.h"

#define KCSSTORE_VALIDATE_PRECONDITION BOOL okayToProceed = [self validatePreconditionsAndSendErrorTo:completionBlock]; \
if (okayToProceed == NO) { \
return; \
}

#define KCS_OBJECT_LIMIT 10000

typedef KCSRESTRequest* (^RestRequestForObjBlock_t)(id obj);
typedef void (^ProcessDataBlock_t)(KCSConnectionResponse* response, KCSCompletionBlock completion);

@interface KCSAppdataStore () {
    KCSSaveGraph* _previousProgress;
    NSString* _title;
}

@property (nonatomic) BOOL treatSingleFailureAsGroupFailure;
@property (nonatomic) BOOL offlineUpdateEnabled;

@property (nonatomic, strong) KCSCollection *backingCollection;

- (id) manufactureNewObject:(NSDictionary*)jsonDict resourcesOrNil:(NSMutableDictionary*)resources;

@end

@interface KCSPartialDataParser : NSObject <KCS_SBJsonStreamParserAdapterDelegate>
@property (nonatomic, strong) KCS_SBJsonStreamParser* parser;
@property (nonatomic, strong) KCS_SBJsonStreamParserAdapter* adapter;
@property (nonatomic, strong) NSMutableArray* items;
@property (nonatomic, strong) id objectMaker;
@end

@implementation KCSPartialDataParser

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.parser = [[KCS_SBJsonStreamParser alloc] init];
        self.adapter = [[KCS_SBJsonStreamParserAdapter alloc] init];
        _adapter.delegate = self;
        _adapter.levelsToSkip = 2;
        _parser.delegate = _adapter;
        
        self.items = [NSMutableArray array];
    }
    return self;
}

- (NSArray*) parseData:(NSData*)data hasArray:(BOOL)hasArray
{
    _adapter.levelsToSkip = hasArray ? 2 : 1;
    KCS_SBJsonStreamParserStatus status = [_parser parse:data];
    if (status == SBJsonStreamParserError) {
        KCSLogError(@"Error parsing partial progress reults: %@", _parser.error);
	} else if (status == SBJsonStreamParserWaitingForData) {
        KCSLogTrace(@"Parsed partial progress results. Item count %d", _items.count);
		NSLog(@"Parser waiting for more data");
	} else if (status == SBJsonStreamParserComplete) {
        NSLog(@"complete");
    }
    return [_items copy];
}

- (void)parser:(KCS_SBJsonStreamParser *)parser foundArray:(NSArray *)array
{
    DBAssert(true, @"not expecting an array here");
}

- (void)parser:(KCS_SBJsonStreamParser *)parser foundObject:(NSDictionary *)dict {
    id obj = [self.objectMaker manufactureNewObject:dict resourcesOrNil:nil];
    [_items addObject:obj];
}

@end

@implementation KCSAppdataStore


#pragma mark - Initialization

+ (KCSObjectCache*)caches
{
    static KCSObjectCache* sDataCaches;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sDataCaches = [[KCSObjectCache alloc] init];
    });
    return sDataCaches;
}

- (instancetype)init
{
    return [self initWithAuth:nil];
}

- (instancetype)initWithAuth: (KCSAuthHandler *)auth
{
    self = [super init];
    if (self) {
        _authHandler = auth;
        _treatSingleFailureAsGroupFailure = YES;
        //        _saveQueue = nil;
        _title = nil;
    }
    return self;
}

+ (instancetype)store
{
    return [self storeWithOptions:nil];
}

+ (instancetype) storeWithOptions: (NSDictionary *)options
{
    return  [self storeWithCollection:nil options:options];
}

+ (instancetype) storeWithAuthHandler: (KCSAuthHandler *)authHandler withOptions: (NSDictionary *)options
{
    return [self storeWithCollection:nil options:options];
}

+ (instancetype) storeWithCollection:(KCSCollection*)collection options:(NSDictionary*)options
{
    
    if (options == nil) {
        options = @{ KCSStoreKeyResource : collection };
    } else {
        options = [NSMutableDictionary dictionaryWithDictionary:options];
        if (collection) {
            [options setValue:collection forKey:KCSStoreKeyResource];
        }
    }
    KCSAppdataStore* store = [[self alloc] init];
    [store configureWithOptions:options];
    return store;
}

+ (instancetype) storeWithCollection:(KCSCollection*)collection authHandler:(KCSAuthHandler *)authHandler withOptions: (NSDictionary *)options
{
    return [self storeWithCollection:collection options:options];
}

- (BOOL)configureWithOptions: (NSDictionary *)options
{
    
    if (options) {
        // Configure
        KCSCollection* collection = [options objectForKey:KCSStoreKeyResource];
        if (collection == nil) {
            NSString* collectionName = [options objectForKey:KCSStoreKeyCollectionName];
            if (collectionName != nil) {
                Class objectClass = [options objectForKey:KCSStoreKeyCollectionTemplateClass];
                if (objectClass == nil) {
                    objectClass = [NSMutableDictionary class];
                }
                collection = [KCSCollection collectionFromString:collectionName ofClass:objectClass];
            }
        }
        self.backingCollection = collection;
//        NSString* queueId = [options valueForKey:KCSStoreKeyUniqueOfflineSaveIdentifier];
//        if (queueId == nil)
//            queueId = [self description];
//        //        _saveQueue = [KCSSaveQueue saveQueueForCollection:self.backingCollection uniqueIdentifier:queueId];
//        self.cache2 = [[KCSObjectCache alloc] init]; //TODO: use persistence key
//        
//        _offlineSaveEnabled = [options valueForKey:KCSStoreKeyUniqueOfflineSaveIdentifier] != nil;
//        
//        //TODO: use delegate in c2
//        id del = [options valueForKey:KCSStoreKeyOfflineSaveDelegate];
//#warning        _saveQueue.delegate = del;
        
        _previousProgress = [options objectForKey:KCSStoreKeyOngoingProgress];
        _title = [options objectForKey:KCSStoreKeyTitle];
    }
    
    if (self.backingCollection == nil) {
        [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Collection cannot be nil" userInfo:options] raise];
    }
    
    // Even if nothing happened we return YES (as it's not a failure)
    return YES;
}

#pragma mark - Block Making
// Avoid compiler warning by prototyping here...
//KCSConnectionCompletionBlock makeGroupCompletionBlock(KCSGroupCompletionBlock onComplete, NSString* key, NSArray* fields, BOOL buildsObjects);
KCSConnectionFailureBlock    makeGroupFailureBlock(KCSGroupCompletionBlock onComplete);
KCSConnectionProgressBlock   makeProgressBlock(KCSProgressBlock onProgress);

- (KCSConnectionCompletionBlock) makeGroupCompletionBlock:(KCSGroupCompletionBlock) onComplete key:(NSString*)key fields:(NSArray*)fields buildsObjects:(BOOL)buildsObjects
{
    return [^(KCSConnectionResponse *response){
        
        KCSLogTrace(@"In collection callback with response: %@", response);
        NSObject* jsonData = [response jsonResponseValue];
        
        NSArray *jsonArray = nil;
        if (response.responseCode != KCS_HTTP_STATUS_OK){
            NSError* error = [KCSErrorUtilities createError:(NSDictionary*)jsonData
                                                description:@"Collection grouping was unsuccessful."
                                                  errorCode:response.responseCode
                                                     domain:KCSAppDataErrorDomain
                                                  requestId:response.requestId];
            onComplete(nil, error);
            
            return;
        }
        
        if ([jsonData isKindOfClass:[NSArray class]]){
            jsonArray = (NSArray *)jsonData;
        } else {
            if ([(NSDictionary *)jsonData count] == 0){
                jsonArray = [NSArray array];
            } else {
                jsonArray = @[jsonData];
            }
        }
        
        if (buildsObjects == YES) {
            NSMutableArray* newArray = [NSMutableArray arrayWithCapacity:jsonArray.count];
            for (NSDictionary* d in jsonArray) {
                NSMutableDictionary* newDictionary = [d mutableCopy];
                NSArray* objectDicts = [d objectForKey:key];
                NSMutableArray* returnObjects = [NSMutableArray arrayWithCapacity:objectDicts.count];
                for (NSDictionary* objDict in objectDicts) {
                    NSMutableDictionary* resources = [NSMutableDictionary dictionary];
                    id newobj = [self manufactureNewObject:objDict resourcesOrNil:resources];
                    [returnObjects addObject:newobj];
                }
                [newDictionary setObject:returnObjects forKey:key];
                [newArray addObject:newDictionary];
            }
            jsonArray = [NSArray arrayWithArray:newArray];
        }
        
        KCSGroup* group = [[KCSGroup alloc] initWithJsonArray:jsonArray valueKey:key queriedFields:fields];
        
        onComplete(group, nil);
    } copy];
}

KCSConnectionFailureBlock makeGroupFailureBlock(KCSGroupCompletionBlock onComplete)
{
    return [^(NSError *error){
        onComplete(nil, error);
    } copy];
}

KCSConnectionProgressBlock makeProgressBlock(KCSProgressBlock onProgress)
{
    return onProgress == nil ? nil : [^(KCSConnectionProgress *connectionProgress) {
        onProgress(@[], connectionProgress.percentComplete);
    } copy];
}

- (NSError*) noCollectionError
{
    NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"This store is not associated with a resource."
                                                                       withFailureReason:@"Store's collection is nil"
                                                                  withRecoverySuggestion:@"Create a store with KCSCollection object for  'kKCSStoreKeyResource'."
                                                                     withRecoveryOptions:nil];
    return [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSNotFoundError userInfo:userInfo];
}

- (BOOL) validatePreconditionsAndSendErrorTo:(void(^)(id objs, NSError* error))completionBlock
{
    if (completionBlock == nil) {
        return NO;
    }
    
    BOOL okay = YES;
    KCSCollection* collection = self.backingCollection;
    if (collection == nil) {
        collection = NO;
        dispatch_async(dispatch_get_current_queue(), ^{
            completionBlock(nil, [self noCollectionError]);
        });
    }
    return okay;
}

#pragma mark - Querying/Fetching
//for overriding by subclasses (simpler than strategy, for now)
- (id) manufactureNewObject:(NSDictionary*)jsonDict resourcesOrNil:(NSMutableDictionary*)resources
{
    return [KCSObjectMapper makeObjectOfType:self.backingCollection.objectTemplate withData:jsonDict];
}

- (ProcessDataBlock_t) makeProcessDictBlockForNewObject
{
    ProcessDataBlock_t processBlock = ^(KCSConnectionResponse *response, KCSCompletionBlock completionBlock) {
        NSDictionary* jsonResponse = (NSDictionary*) [response jsonResponseValue];
        
        if (response.responseCode != KCS_HTTP_STATUS_CREATED && response.responseCode != KCS_HTTP_STATUS_OK){
            NSError* error = [KCSErrorUtilities createError:jsonResponse
                                                description:nil
                                                  errorCode:response.responseCode
                                                     domain:KCSAppDataErrorDomain
                                                  requestId:response.requestId];
            completionBlock(nil, error);
        } else {
            if (jsonResponse) {
                NSArray* jsonArray = [NSArray wrapIfNotArray:jsonResponse];
                NSUInteger itemCount = jsonArray.count;
                if (itemCount == 0) {
                    completionBlock(@[], nil);
                } else if (itemCount == KCS_OBJECT_LIMIT) {
                    KCSLogWarning(@"Returned exactly %i objects. This is the Kinvey limit for a query, and there may actually be more results. If this is the case use the limit & skip modifiers on `KCSQuery` to page through the results.", KCS_OBJECT_LIMIT);
                }
                __block NSUInteger completedCount = 0;
                __block NSError* resourceError = nil;
                NSMutableArray* returnObjects = [NSMutableArray arrayWithCapacity:itemCount];
                for (NSDictionary* jsonDict in jsonArray) {
                    NSMutableDictionary* resources = [NSMutableDictionary dictionary];
                    id newobj = [self manufactureNewObject:jsonDict resourcesOrNil:resources];
                    [returnObjects addObject:newobj];
                    NSUInteger resourceCount = resources.count;
                    if ( resourceCount > 0 ) {
                        //need to load the resources
                        __block NSUInteger completedResourceCount = 0;
                        [resources enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                            [KCSFileStore downloadKCSFile:obj completionBlock:^(NSArray *downloadedResources, NSError *error) {
                                completedResourceCount++;
                                if (error != nil) {
                                    resourceError = error;
                                }
                                if (downloadedResources != nil && downloadedResources.count > 0) {
                                    KCSFile* downloadedFile = downloadedResources[0];
                                    id loadedResource = [downloadedFile resolvedObject];
                                    [newobj setValue:loadedResource forKey:key];
                                } else {
                                    //set nil for the resource
                                    [newobj setValue:nil forKey:key];
                                }
                                if (completedResourceCount == resourceCount) {
                                    //all resources loaded
                                    completedCount++;
                                    if (completedCount == itemCount) {
                                        completionBlock(returnObjects, resourceError);
                                    }
                                }
                            } progressBlock:^(NSArray *objects, double percentComplete) {
                                //TODO: sub progress
                            }];
                        }];
                    } else {
                        //no linked resources
                        completedCount++;
                        if (completedCount == itemCount) {
                            completionBlock(returnObjects, resourceError);
                        }
                    }
                }
                
            } else {
                completionBlock(nil, nil);
            }
        }
    };
    return [processBlock copy];
}



- (NSString*) getObjIdFromObject:(id)object completionBlock:(KCSCompletionBlock)completionBlock
{
    NSString* theId = nil;
    if ([object isKindOfClass:[NSString class]]) {
        theId = object;
    } else if ([object conformsToProtocol:@protocol(KCSPersistable)]) {
        theId = [object kinveyObjectId];
        if (theId == nil) {
            dispatch_async(dispatch_get_current_queue(), ^{
                NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Invalid object ID."
                                                                                   withFailureReason:@"Object id cannot be empty."
                                                                              withRecoverySuggestion:nil
                                                                                 withRecoveryOptions:nil];
                NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSInvalidArgumentError userInfo:userInfo];
                completionBlock(nil, error);
            });
        }
    } else {
        dispatch_async(dispatch_get_current_queue(), ^{
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Invalid object ID."
                                                                               withFailureReason:@"Object id must be a NSString."
                                                                          withRecoverySuggestion:nil
                                                                             withRecoveryOptions:nil];
            NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSInvalidArgumentError userInfo:userInfo];
            completionBlock(nil, error);
        });
    }
    return theId;
}

//for overriding by subclasses (simpler than strategy, for now)
- (NSString*) modifyLoadQuery:(NSString*)query ids:(NSArray*)array
{
    return query;
}

- (void)loadObjectWithID: (id)objectID
     withCompletionBlock: (KCSCompletionBlock)completionBlock
       withProgressBlock: (KCSProgressBlock)progressBlock;
{
    KCSSTORE_VALIDATE_PRECONDITION
    
    KCSCollection* collection = self.backingCollection;
    NSArray* array = [NSArray wrapIfNotArray:objectID];
    if ([array containsObject:@""]) {
        dispatch_async(dispatch_get_current_queue(), ^{
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Invalid object ID."
                                                                               withFailureReason:@"Object id cannot be empty."
                                                                          withRecoverySuggestion:nil
                                                                             withRecoveryOptions:nil];
            NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSInvalidArgumentError userInfo:userInfo];
            completionBlock(nil, error);
        });
        return;
    }
    
    NSString* query = @"";
    BOOL hasArray = NO;
    if (array.count == 1) {
        query = [NSString stringByPercentEncodingString:[self getObjIdFromObject:array[0] completionBlock:completionBlock]];
        if (query == nil) {
            //already sent an error;
            return;
        }
    } else {
        hasArray = YES;
        NSMutableArray* objIds = [NSMutableArray arrayWithCapacity:array.count];
        for (id object in array) {
            NSString* anId = [self getObjIdFromObject:object completionBlock:completionBlock];
            if (anId == nil) {
                //already sent an error;
                return;
            } else {
                [objIds addObject:[NSString stringWithFormat:@"\"%@\"", anId]];
            }
        }
        query = [NSString stringWithFormat:@"{\"_id\" : { \"$in\" : [%@]}}", [objIds join:@","]];
        query = [NSString stringWithFormat:@"?query=%@",[query stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }
    
    query = [self modifyLoadQuery:query ids:array];
    
    KCSRESTRequest* request = [collection restRequestForMethod:kGetRESTMethod apiEndpoint:query];
    ProcessDataBlock_t processBlock = [self makeProcessDictBlockForNewObject];
    
    KCSConnectionCompletionBlock completionAction = ^(KCSConnectionResponse* response) {
        KCSLogTrace(@"In collection callback with response: %@", [response jsonResponseValue]);
        processBlock(response, ^(NSArray* objectsOrNil, NSError* error) {
            completionBlock(objectsOrNil, error);
        });
    };
    
    KCSConnectionFailureBlock failureAction = ^(NSError* error) {
        completionBlock(nil, error);
    };
    
    KCSPartialDataParser* partialParser = nil;
    if (progressBlock!= nil) {
        partialParser = [[KCSPartialDataParser alloc] init];
        partialParser.objectMaker = self;
    }
    
    [[request withCompletionAction:completionAction failureAction:failureAction progressAction:^(KCSConnectionProgress* progress) {
        if (progressBlock != nil) {
            NSArray* partialResults = [partialParser parseData:progress.data hasArray:hasArray];
            progressBlock(partialResults, progress.percentComplete);
        }
    }] start];
}

- (void)queryWithQuery:(id)query withCompletionBlock: (KCSCompletionBlock)completionBlock withProgressBlock: (KCSProgressBlock)progressBlock
{
    KCSSTORE_VALIDATE_PRECONDITION
    KCSCollection* collection = self.backingCollection;
    NSString* queryString = query != nil ? [query parameterStringRepresentation] : @"";
    
    KCSRESTRequest *request = [collection restRequestForMethod:kGetRESTMethod apiEndpoint:queryString];
    ProcessDataBlock_t processBlock =  [self makeProcessDictBlockForNewObject];
    
    KCSConnectionCompletionBlock completionAction = ^(KCSConnectionResponse* response) {
        KCSLogTrace(@"In collection callback with response: %@", response);
        processBlock(response, ^(NSArray* objectsOrNil, NSError* error) {
            completionBlock(objectsOrNil, error);
        });
    };
    
    KCSConnectionFailureBlock failureAction = ^(NSError* error) {
        completionBlock(nil, error);
    };
    
    KCSPartialDataParser* partialParser = nil;
    if (progressBlock!= nil) {
        partialParser = [[KCSPartialDataParser alloc] init];
        partialParser.objectMaker = self;
    }
    
    [[request withCompletionAction:completionAction failureAction:failureAction progressAction:^(KCSConnectionProgress* progress) {
        if (progressBlock != nil) {
            NSArray* partialResults = [partialParser parseData:progress.data hasArray:YES];
            progressBlock(partialResults, progress.percentComplete);
        }
    }] start];
}

- (void)group:(id)fieldOrFields reduce:(KCSReduceFunction *)function condition:(KCSQuery *)condition completionBlock:(KCSGroupCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    KCSCollection* collection = self.backingCollection;
    BOOL okayToProceed = [self validatePreconditionsAndSendErrorTo:completionBlock];
    if (okayToProceed == NO) {
        return;
    }
    
    NSString* collectionName = collection.collectionName;
    NSString *format = nil;
    
    if ([collectionName isEqualToString:@""]){
        format = @"%@_group";
    } else {
        format = @"%@/_group";
    }
    
    NSArray* fields = [NSArray wrapIfNotArray:fieldOrFields];
    
    NSString *resource = [collection.baseURL stringByAppendingFormat:format, collectionName];
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithCapacity:4];
    NSMutableDictionary *keys = [NSMutableDictionary dictionaryWithCapacity:[fields count]];
    for (NSString* field in fields) {
        [keys setObject:[NSNumber numberWithBool:YES] forKey:field];
    }
    [body setObject:keys forKey:@"key"];
    [body setObject:[function JSONStringRepresentationForInitialValue:fields] forKey:@"initial"];
    [body setObject:[function JSONStringRepresentationForFunction:fields] forKey:@"reduce"];
    [body setObject:[NSDictionary dictionary] forKey:@"finalize"];
    
    if (condition != nil) {
        [body setObject:[condition query] forKey:@"condition"];
    }
    
    KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:kPostRESTMethod];
    KCS_SBJsonWriter *writer = [[KCS_SBJsonWriter alloc] init];
    [request addBody:[writer dataWithObject:body]];
    [request setContentType:KCS_JSON_TYPE];
    
    KCSConnectionCompletionBlock cBlock = [self makeGroupCompletionBlock:completionBlock
                                                                     key:[function outputValueName:fields]
                                                                  fields:fields
                                                           buildsObjects:[function buildsObjects]];
    KCSConnectionFailureBlock fBlock = makeGroupFailureBlock(completionBlock);
    KCSConnectionProgressBlock pBlock = makeProgressBlock(progressBlock);
    
    // Make the request happen
    [[request withCompletionAction:cBlock failureAction:fBlock progressAction:pBlock] start];
}

- (void)group:(id)fieldOrFields reduce:(KCSReduceFunction *)function completionBlock:(KCSGroupCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [self group:fieldOrFields reduce:function condition:[KCSQuery query] completionBlock:completionBlock progressBlock:progressBlock];
}

- (void)groupByKeyFunction:(id)keyFunction reduce:(KCSReduceFunction *)function condition:(KCSQuery *)condition completionBlock:(KCSGroupCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    KCSCollection* collection = self.backingCollection;
    BOOL okayToProceed = [self validatePreconditionsAndSendErrorTo:completionBlock];
    if (okayToProceed == NO) {
        return;
    }
    
    NSString* collectionName = collection.collectionName;
    NSString *format = nil;
    
    if ([collectionName isEqualToString:@""]){
        format = @"%@_group";
    } else {
        format = @"%@/_group";
    }
    
    
    NSString *resource = [collection.baseURL stringByAppendingFormat:format, collectionName];
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithCapacity:5];

    [body setObject:keyFunction forKey:@"keyf"];
    [body setObject:[function JSONStringRepresentationForInitialValue:@[]] forKey:@"initial"];
    [body setObject:[function JSONStringRepresentationForFunction:@[]] forKey:@"reduce"];
    [body setObject:[NSDictionary dictionary] forKey:@"finalize"];
    
    if (condition != nil) {
        [body setObject:[condition query] forKey:@"condition"];
    }
    
    KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:kPostRESTMethod];
    KCS_SBJsonWriter *writer = [[KCS_SBJsonWriter alloc] init];
    [request addBody:[writer dataWithObject:body]];
    [request setContentType:KCS_JSON_TYPE];
    
    KCSConnectionCompletionBlock cBlock = [self makeGroupCompletionBlock:completionBlock
                                                                     key: [function outputValueName:@[]]
                                                                  fields:@[]
                                                           buildsObjects:[function buildsObjects]];
    KCSConnectionFailureBlock fBlock = makeGroupFailureBlock(completionBlock);
    KCSConnectionProgressBlock pBlock = makeProgressBlock(progressBlock);
    
    // Make the request happen
    [[request withCompletionAction:cBlock failureAction:fBlock progressAction:pBlock] start];
}


#pragma mark - Adding/Updating
- (ProcessDataBlock_t) makeProcessDictBlock:(KCSSerializedObject*)serializedObject
{
    ProcessDataBlock_t processBlock = ^(KCSConnectionResponse *response, KCSCompletionBlock completionBlock) {
        NSDictionary* jsonResponse = (NSDictionary*) [response jsonResponseValue];
        
        if (response.responseCode != KCS_HTTP_STATUS_CREATED && response.responseCode != KCS_HTTP_STATUS_OK){
            NSString* description = nil;
            if (response.responseCode == KCSDeniedError) {
                NSString* format401 = @"Active user (username:'%@') does not have permission to write object (%@) to collection '%@'";
                NSString* objectTitle = serializedObject.objectId ? [NSString stringWithFormat:@"_id:'%@'", serializedObject.objectId] : @"New Object";
                description = [NSString stringWithFormat:format401, [[KCSUser activeUser] username], objectTitle, self.backingCollection.collectionName];
            }
            NSError* error = [KCSErrorUtilities createError:jsonResponse description:description errorCode:response.responseCode domain:KCSAppDataErrorDomain requestId:response.requestId];
            completionBlock(nil, error);
        } else {
            if (jsonResponse != nil && serializedObject != nil) {
                id newObj = [KCSObjectMapper populateExistingObject:serializedObject withNewData:jsonResponse];
                completionBlock(@[newObj], nil);
            } else {
                completionBlock(nil, nil);
            }
        }
    };
    return [processBlock copy];
}

- (BOOL) isNoNetworkError:(NSError*)error
{
    BOOL isNetworkError = NO;
    if ([[error domain] isEqualToString:KCSNetworkErrorDomain]) { //KCSNetworkErrorDomain
        NSError* underlying = [error userInfo][NSUnderlyingErrorKey];
        if (underlying) {
            //not sure what kind this is, so try again later
            //error objects should have an underlying eror when coming from KCSAsyncRequest
            return [self isNoNetworkError:underlying];
        }
    } else if ([[error domain] isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case kCFURLErrorUnknown:
            case kCFURLErrorTimedOut:
            case kCFURLErrorNotConnectedToInternet:
            case kCFURLErrorDNSLookupFailed:
                KCSLogNetwork(@"Got a network error (%d) on save, adding to queue.");
                isNetworkError = YES;
                break;
            default:
                KCSLogNetwork(@"Got a network error (%d) on save, but NOT queueing.", error.code);
        }
        //TODO: ios7 background update on timer if can't resend
    }
    return isNetworkError;
}

- (BOOL) shouldEnqueue:(NSError*)error
{
    return self.offlineUpdateEnabled && [KCSAppdataStore caches].offlineUpdateEnabled && [self isNoNetworkError:error] == YES;
}

- (void) saveMainEntity:(KCSSerializedObject*)serializedObj progress:(KCSSaveGraph*)progress withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    BOOL isPostRequest = serializedObj.isPostRequest;
    
    //Step 3: save entity
    RestRequestForObjBlock_t requestBlock = ^KCSRESTRequest *(id obj) {
        
        NSString *objectId = serializedObj.objectId;
        NSDictionary *dictionaryToMap = serializedObj.dataToSerialize;
        
        KCSCollection* collection = self.backingCollection;
        NSString *resource = [collection urlForEndpoint:objectId];
        
        // If we need to post this, then do so
        KCSRESTMethod HTTPMethod = (isPostRequest) ? kPostRESTMethod : kPutRESTMethod;
        
        // Prepare our request
        KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:HTTPMethod];
        
        // This is a JSON request
        [request setContentType:KCS_JSON_TYPE];
        
        // Make sure to include the UTF-8 encoded JSONData...
        KCS_SBJsonWriter *writer = [[KCS_SBJsonWriter alloc] init];
        NSData* bodyData = [writer dataWithObject:dictionaryToMap];
        if (!bodyData && [writer error]) {
            request = (id) [writer error];
        } else {
            [request addBody:[writer dataWithObject:dictionaryToMap]];
        }
        return request;
    };
    
    ProcessDataBlock_t processBlock = [self makeProcessDictBlock:serializedObj];
    
    KCSConnectionCompletionBlock completionAction = ^(KCSConnectionResponse* response) {
        KCSLogTrace(@"In collection callback with response: %@", [response jsonResponseValue]);
        processBlock(response, completionBlock);
    };
    
    KCSConnectionFailureBlock failureAction = ^(NSError* error) {
        if ([self shouldEnqueue:error] == YES) {
            //enqueue save
            NSString* _id = [[KCSAppdataStore caches] addUnsavedObject:serializedObj.handleToOriginalObject entity:serializedObj.dataToSerialize route:[self.backingCollection route] collection:self.backingCollection.collectionName method:(isPostRequest ? KCSRESTMethodPOST : KCSRESTMethodPUT) headers:@{KCSRequestLogMethod} error:error];
            
            if (_id != nil) {
                error = [error updateWithInfo:@{KCS_ERROR_UNSAVED_OBJECT_IDS_KEY : @[_id]}];
            }
            
            completionBlock(nil, error);
        } else {
            completionBlock(nil, error);
        }
    };
    
    KCSRESTRequest* request = requestBlock(nil);
    if ([request isKindOfClass:[NSString class]]) {
        NSError* error = [KCSErrorUtilities createError:nil description:(NSString*)request errorCode:KCSBadRequestError domain:KCSAppDataErrorDomain requestId:nil];
        completionBlock(nil, error);
    } else {
        id objKey = [[serializedObj userInfo] objectForKey:@"entityProgress"];
        
        [[request withCompletionAction:completionAction failureAction:failureAction progressAction:^(KCSConnectionProgress* cxnProgress) {
            [objKey setPc:cxnProgress.percentComplete];
            if (progressBlock != nil) {
                progressBlock(@[], progress.percentDone);
            }
        }] start];
    }
}

- (void) saveEntityWithResources:(KCSSerializedObject*)so progress:(KCSSaveGraph*)progress withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    //just go right on to main entity here sine this store does not do resources
    [self saveMainEntity:so progress:progress withCompletionBlock:completionBlock withProgressBlock:progressBlock];
}

- (KCSSerializedObject*) makeSO:(id<KCSPersistable>)object error:(NSError**)error
{
    return [KCSObjectMapper makeKinveyDictionaryFromObject:object error:error];
}

- (void) saveEntity:(id<KCSPersistable>)objToSave progressGraph:(KCSSaveGraph*)progress doSaveBlock:(KCSCompletionBlock)doSaveblock alreadySavedBlock:(KCSCompletionWrapperBlock_t)alreadySavedBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    //Step 0: Serialize Object
    NSError* error = nil;
    KCSSerializedObject* so = [self makeSO:objToSave error:&error];
    if (so == nil && error) {
        doSaveblock(@[], error);
        return;
    }
    id objKey = [progress markEntity:so];
    __weak id saveGraph = objKey;
    DBAssert(objKey != nil, @"should have a valid obj key here");
    NSString* cname = self.backingCollection.collectionName;
    [objKey ifNotLoaded:^{
        [self saveEntityWithResources:so progress:progress
                  withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
                      [objKey finished:objectsOrNil error:errorOrNil];
            [objKey doAfterWaitingResaves:^{
                doSaveblock(objectsOrNil, errorOrNil);
            }];
            
        } withProgressBlock:progressBlock];
    }
    otherwiseWhenLoaded:alreadySavedBlock
andResaveAfterReferencesSaved:^{
        KCSSerializedObject* soPrime = [KCSObjectMapper makeResourceEntityDictionaryFromObject:objToSave forCollection:cname error:NULL]; //TODO: figure out if this is needed?
        [soPrime restoreReferences:so];
        [self saveMainEntity:soPrime progress:progress withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
            [saveGraph resaveComplete];
        } withProgressBlock:^(NSArray *objects, double percentComplete) {
            //TODO: as above
        }];
    }];
}

- (void)saveObject:(id)object withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    KCSSTORE_VALIDATE_PRECONDITION
    
    NSArray* objectsToSave = [NSArray wrapIfNotArray:object];
    NSUInteger totalItemCount = [objectsToSave count];
    
    if (totalItemCount == 0) {
        //TODO: does this need an error?
        completionBlock(@[], nil);
    }
    
    __block int completedItemCount = 0;
    NSMutableArray* completedObjects = [NSMutableArray arrayWithCapacity:totalItemCount];
    
    KCSSaveGraph* progress = _previousProgress == nil ? [[KCSSaveGraph alloc] initWithEntityCount:totalItemCount] : _previousProgress;
    
    __block NSError* topError = nil;
    __block BOOL done = NO;
    [objectsToSave enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        //Step 0: Serialize Object
        [self saveEntity:obj
           progressGraph:progress
             doSaveBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
                 if (done) {
                     //don't do the completion blocks for all the objects if its previously finished
                     return;
                 }
                 if (errorOrNil != nil) {
                     topError = errorOrNil;
                 }
                 if (objectsOrNil != nil) {
                     [completedObjects addObjectsFromArray:objectsOrNil];
                 }
                 completedItemCount++;
                 BOOL shouldStop = errorOrNil != nil && self.treatSingleFailureAsGroupFailure;
                 if (completedItemCount == totalItemCount || shouldStop) {
                     done = YES;
                     completionBlock(completedObjects, topError);
                 }
                 
             }
       alreadySavedBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
           if (done) {
               //don't do the completion blocks for all the objects if its previously finished
               return;
           }
           [completedObjects addObjectsFromArray:objectsOrNil];
           completedItemCount++;
           if (completedItemCount == totalItemCount) {
               done = YES;
               completionBlock(completedObjects, topError);
           }
       }
       withProgressBlock:progressBlock];
    }];
}

#pragma mark - Removing
- (void) removeObject:(id)object withCompletionBlock:(KCSCountBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    BOOL okayToProceed = [self validatePreconditionsAndSendErrorTo:^(id objs, NSError *error) {
        completionBlock(0, error);
    }];
    if (okayToProceed == NO) {
        return;
    }
    
    if ([object isKindOfClass:[NSArray class]]) {
        //input is an array
        NSArray* objects = object;
        if (objects.count == 0) {
            completionBlock(0, nil);
        }
        if ([object[0] isKindOfClass:[NSString class]]) {
            //input is _id array
            object = [KCSQuery queryOnField:KCSEntityKeyId usingConditional:kKCSIn forValue:objects];
        } else if ([object[0] conformsToProtocol:@protocol(KCSPersistable)] == YES) {
            //input is object array?
            NSMutableArray* ids = [NSMutableArray arrayWithCapacity:objects.count];
            for (NSObject<KCSPersistable>* obj in objects) {
                [ids addObject:[obj kinveyObjectId]];
            }
            object = [KCSQuery queryOnField:KCSEntityKeyId usingConditional:kKCSIn forValue:ids];
        } else {
            [[NSException exceptionWithName:NSInvalidArgumentException reason:@"input is not a homogenous array of id strings or objects" userInfo:nil] raise];
        }
    } else if ([object conformsToProtocol:@protocol(KCSPersistable)]) {
        //if its just a single object get the _id
        object = [object kinveyObjectId];
    }
    
    KCSDataStore* store2 = [[KCSDataStore alloc] initWithCollection:self.backingCollection.collectionName];
    
    if ([object isKindOfClass:[KCSQuery class]]) {
        [store2 deleteByQuery:[KCSQuery2 queryWithQuery1:object] completion:^(NSUInteger count, NSError *error) {
            if (error) {
                if ([self shouldEnqueue:error]) {
                    //enqueue save
                    id errorValue = [[KCSAppdataStore caches] addUnsavedDeleteQuery:[KCSQuery2 queryWithQuery1:object] route:[self.backingCollection route] collection:self.backingCollection.collectionName method:KCSRESTMethodDELETE headers:@{KCSRequestLogMethod} error:error];
                    
                    if (errorValue != nil) {
                        error = [error updateWithInfo:@{KCS_ERROR_UNSAVED_OBJECT_IDS_KEY : @[errorValue]}];
                    }
                }
                completionBlock(0, error);
            } else {
                completionBlock(count, nil);
            }
        }];
    } else {
        [store2 deleteEntity:object completion:^(NSUInteger count, NSError *error) {
            if (error) {
                if ([self shouldEnqueue:error]) {
                    //enqueue save
                    id errorValue = [[KCSAppdataStore caches] addUnsavedDelete:object route:[self.backingCollection route] collection:self.backingCollection.collectionName method:KCSRESTMethodDELETE headers:@{KCSRequestLogMethod} error:error];
                    if (errorValue != nil) {
                        error = [error updateWithInfo:@{KCS_ERROR_UNSAVED_OBJECT_IDS_KEY : @[errorValue]}];
                    }
                }
                completionBlock(0, error);
            } else {
                completionBlock(count, nil);
            }

        }];
    }
#warning put back Progress block
    
//    KCSQuery* deleteQuery = nil;
//    NSString* deleteId = [object isKindOfClass:[NSString class]] ? object : nil;
//    if ([object isKindOfClass:[KCSQuery class]]) {
//        deleteQuery = object;
//    } else {
//        NSArray *objectsToProcess = [NSArray wrapIfNotArray:object];
//        if (objectsToProcess.count == 0) {
//            completionBlock(nil, nil);
//            return;
//        }
//        
//        NSMutableArray* ids = [NSMutableArray arrayWithCapacity:objectsToProcess.count];
//        [objectsToProcess enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
//            NSString* _id = [obj kinveyObjectId];
//            if (_id != nil) {
//                [ids addObject:_id];
//            }
//        }];
//        
//        deleteQuery = [KCSQuery queryOnField:@"_id" usingConditional:kKCSIn forValue:ids];
//    }
//    NSString *resource = nil;
//    NSString *format = nil;
//    
//    KCSCollection* collection = self.backingCollection;
//    if ([collection.collectionName isEqualToString:@""]){
//        format = @"%@";
//    } else {
//        format = @"%@/";
//    }
//    
//    resource = [collection.baseURL stringByAppendingFormat:format, collection.collectionName];
//    
//    // Add the Query portion of the request
//    if (deleteQuery.query != nil && deleteQuery.query.count > 0){
//        resource = [resource stringByAppendingQueryString:[deleteQuery parameterStringRepresentation]];
//    }
//    
//    
//    KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:kDeleteRESTMethod];
    
    
//    KCSConnectionCompletionBlock cBlock = ^(KCSConnectionResponse *response){
//                
//        KCSLogTrace(@"In collection callback with response: %@", response);
//        NSObject* jsonData = [response jsonResponseValue];
//        
//        if (response.responseCode != KCS_HTTP_STATUS_NO_CONTENT && response.responseCode != KCS_HTTP_STATUS_OK){
//            NSError* error = [KCSErrorUtilities createError:(NSDictionary*)jsonData description:@"Deletion was unsuccessful." errorCode:response.responseCode domain:KCSAppDataErrorDomain requestId:response.requestId];
//            completionBlock(nil, error);
//            return;
//        }
//        NSArray* jsonArray = nil;
//        if ([jsonData isKindOfClass:[NSArray class]]){
//            jsonArray = (NSArray *)jsonData;
//        } else {
//            if ([(NSDictionary *)jsonData count] == 0){
//                jsonArray = @[];
//            } else {
//                jsonArray = @[jsonData];
//            }
//        }
//        
//        completionBlock(jsonArray, nil);
//    };
//    KCSConnectionFailureBlock fBlock = ^(NSError *error){
//        if ([self shouldEnqueue:error]) {
//            //enqueue save
//            id errorValue = nil;
//            if (deleteId) {
//                 errorValue = [[KCSAppdataStore caches] addUnsavedDelete:deleteId route:KCSRESTRouteAppdata collection:self.backingCollection.collectionName method:KCSRESTMethodDELETE headers:@{KCSRequestLogMethod} error:error];
//            } else {
//                errorValue = [[KCSAppdataStore caches] addUnsavedDeleteQuery:[KCSQuery2 queryWithQuery1:deleteQuery] route:KCSRESTRouteAppdata collection:self.backingCollection.collectionName method:KCSRESTMethodDELETE headers:@{KCSRequestLogMethod} error:error];
//            }
//           
//            if (errorValue != nil) {
//                error = [error updateWithInfo:@{KCS_ERROR_UNSAVED_OBJECT_IDS_KEY : @[errorValue]}];
//            }
//            
//            completionBlock(nil, error);
//        } else {
//            completionBlock(nil, error);
//        }
//    };
//    KCSConnectionProgressBlock pBlock = makeProgressBlock(progressBlock);
//    
//    // Make the request happen
//    [[request withCompletionAction:cBlock failureAction:fBlock progressAction:pBlock] start];
}

#pragma mark - Information
- (void)countWithBlock:(KCSCountBlock)countBlock
{
    [self countWithQuery:nil completion:countBlock];
}

- (void)countWithQuery:(KCSQuery*)query completion:(KCSCountBlock)countBlock
{
    if (countBlock == nil) {
        return;
    } else if (self.backingCollection == nil) {
        dispatch_async(dispatch_get_current_queue(), ^{
            countBlock(0, [self noCollectionError]);
        });
        return;
    }
    
    KCSCollection* collection = self.backingCollection;
    NSString* queryString = query != nil ? [query parameterStringRepresentation] : @"";
    NSString* params = [@"_count" stringByAppendingString:queryString];
    
    KCSRESTRequest *request = [collection restRequestForMethod:kGetRESTMethod apiEndpoint:params];
    
    KCSConnectionCompletionBlock cBlock = ^(KCSConnectionResponse *response){
        NSDictionary *jsonResponse = (NSDictionary*) [response jsonResponseValue];
        
        if (response.responseCode != KCS_HTTP_STATUS_OK){
            NSError* error = [KCSErrorUtilities createError:jsonResponse description:@"Count was unsuccessful." errorCode:response.responseCode domain:KCSAppDataErrorDomain requestId:response.requestId];
            countBlock(0, error);
            return;
        }
        
        NSNumber* val = jsonResponse[@"count"];
        
        countBlock([val unsignedLongValue], nil);
    };
    
    KCSConnectionFailureBlock fBlock = ^(NSError *error){
        countBlock(0, error);
    };
    
    KCSConnectionProgressBlock pBlock = ^(KCSConnectionProgress *collection) {};
    
    // Make the request happen
    [[request withCompletionAction:cBlock failureAction:fBlock progressAction:pBlock] start];
}

@end
