//
//  KCSEntityPersistence.m
//  KinveyKit
//
//  Created by Michael Katz on 5/14/13.
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


#import "KCSEntityPersistence.h"

#import "KinveyCoreInternal.h"

#import "KCS_FMDatabase.h"
#import "KCS_FMDatabaseAdditions.h"

#define KCS_CACHE_VERSION @"0.003"

@interface KCSEntityPersistence ()
@property (nonatomic, strong) KCS_FMDatabase* db;
@property (nonatomic, strong) KCS_SBJsonWriter* jsonWriter;
@property (nonatomic, strong) KCS_SBJsonParser* jsonParser;
@end

@interface KCSCacheValueDB : NSObject
@property (nonatomic) NSUInteger count;
@property (retain, nonatomic) NSDictionary* object;
@property (nonatomic) BOOL unsaved;
@property (nonatomic, strong) NSDate* lastReadTime;
@property (nonatomic, strong) NSString* objId;
@property (nonatomic, strong) NSString* classname;
@end
@implementation KCSCacheValueDB

- (instancetype) init
{
    self = [super init];
    if (self) {
        _count = 1;
        _lastReadTime = [NSDate date];
    }
    return self;
}

@end

@implementation KCSEntityPersistence


- (NSString*) dbPath
{
    return [KCSFileUtils localPathForDB:[NSString stringWithFormat:@"com.kinvey.%@_cache.sqlite3", _persistenceId]];
}

- (instancetype) initWithPersistenceId:(NSString*)key
{
    self = [super init];
    if (self) {
        _persistenceId = key;
        _jsonWriter = [[KCS_SBJsonWriter alloc] init];
        _jsonParser = [[KCS_SBJsonParser alloc] init];
        
        [self initDB];
    }
    return self;
}

- (instancetype) init
{
    DBAssert(YES, @"should always init cache v2 with a name");
    return [self initWithPersistenceId:@"null"];
}

- (void) createMetadata
{
    BOOL e = [_db executeUpdate:@"CREATE TABLE metadata (id VARCHAR(255) PRIMARY KEY, version VARCHAR(255), time TEXT)"];
    if (!e || [_db hadError]) { KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);}
    e = [_db executeUpdate:@"INSERT INTO metadata VALUES (:id, :version, :time)" withArgumentsInArray:@[@"1", KCS_CACHE_VERSION, @"2"]];
    if (!e || [_db hadError]) { KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
}

- (void) initDB
{
    NSString* path = [self dbPath];
    _db = [KCS_FMDatabase databaseWithPath:path];
    if (![_db openWithFlags:[KCSFileUtils dbFlags]]) {
        if ([_db hadError]) { KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);}
        return;
    }
    
    if (![_db tableExists:@"metadata"]) {
        KCSLogDebug(KCS_LOG_CONTEXT_FILESYSTEM, @"Creating New Cache %@", path);
        [self createMetadata];
    } else {
        KCS_FMResultSet *rs = [_db executeQuery:@"SELECT version FROM metadata"];
        if ([_db hadError]) { KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);}
        NSString* version = nil;
        if ([rs next]) {
            NSDictionary* d = [rs resultDictionary];
            version = d[@"version"];
        }
        
        if ([version isEqualToString:KCS_CACHE_VERSION] == NO) {
            [self clearCaches];
            return;
        }
    }

    if (![_db tableExists:@"queries"]) {
        BOOL e = [_db executeUpdate:@"CREATE TABLE queries (id VARCHAR(255) PRIMARY KEY, ids TEXT, routeKey TEXT)"];
        if (!e) {
            KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }
    if (![_db tableExists:@"savequeue"]) {
        BOOL e = [_db executeUpdate:@"CREATE TABLE savequeue (key VARCHAR(255) PRIMARY KEY, id VARCHAR(255), routeKey TEXT, method TEXT, headers TEXT, time VARCHAR(255), obj TEXT)"];
        if (!e) {
            KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }
    if (![_db tableExists:@"groups"]) {
        BOOL e = [_db executeUpdate:@"CREATE TABLE groups (key TEXT PRIMARY KEY, results TEXT)"];
        if (!e) {
            KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }
    if (![_db tableExists:@"clientmetadata"]) {
        BOOL e = [_db executeUpdate:@"CREATE TABLE clientmetadata (key VARCHAR(255) PRIMARY KEY, metadata TEXT)"];
        if (!e) {
            KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }
}

- (void)dealloc
{
    [_db close];
}

#pragma mark - Metadata
- (BOOL) setClientMetadata:(NSDictionary*)metadata
{
    NSError* error = nil;
    NSString* metaStr = [self.jsonWriter stringWithObject:metadata error:&error];
    if (error != nil) {
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"could not serialize: %@", metadata);
        return NO;
    }
    BOOL e = [_db executeUpdate:@"REPLACE INTO clientmetadata VALUES (:key, :metadata)" withArgumentsInArray:@[@"client", metaStr]];
    if (!e || [_db hadError]) { KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    return e;
}

- (NSDictionary*) clientMetadata
{
    NSString* q = [NSString stringWithFormat:@"SELECT metadata FROM clientmetadata WHERE key='client'"];
    
    KCS_FMResultSet* rs = [_db executeQuery:q];
    if ([_db hadError]) {
        KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"DB error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    
    NSDictionary* obj = nil;
    if ([rs next]) {
        NSDictionary* d = [rs resultDictionary];
        if (d) {
            obj = [self dictObjForJson:d[@"metadata"]];
        }
    }

    return obj;
}

#pragma mark - Save Queue

- (NSString*) addUnsavedEntity:(NSDictionary*)entity route:(NSString*)route collection:(NSString*)collection method:(NSString*)method headers:(NSDictionary*)headers
{
    NSString* _id = [entity isKindOfClass:[NSString class]] ? entity : entity[KCSEntityKeyId];
    if (_id == nil) {
        KCSLogInfo(KCS_LOG_CONTEXT_DATA, @"nil `_id` in %@. Adding local id.", entity);
        _id = [KCSDBTools KCSMongoObjectId];
        entity = [entity dictionaryByAddingDictionary:@{KCSEntityKeyId : _id}];
    }
    
    NSError* error = nil;
    NSString* entityStr = [self.jsonWriter stringWithObject:entity error:&error];
    if (error != nil) {
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"could not serialize: %@", entity);
        DBAssert(NO, @"No object");
    }

    NSString* headerStr = [self.jsonWriter stringWithObject:headers error:&error];
    if (error != nil) {
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"could not serialize: %@", headers);
        DBAssert(NO, @"No object");
    }
    
    NSString* routeKey = [self tableForRoute:route collection:collection];

    NSString* update = @"REPLACE INTO savequeue VALUES (:key, :id, :routeKey, :method, :headers, :time, :obj)";
    NSDictionary* valDictionary = @{@"key":[routeKey stringByAppendingString:_id],
                                    @"id":_id,
                                    @"obj":entityStr,
                                    @"time":[NSDate date],
                                    @"routeKey": routeKey,
                                    @"headers": headerStr,
                                    @"method":method};
    BOOL updated = [_db executeUpdate:update withParameterDictionary:valDictionary];
    if (!updated) {
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"Error insert/updating %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    return updated ? _id : nil;
}

- (BOOL) addUnsavedDelete:(NSString*)key route:(NSString*)route collection:(NSString*)collection method:(NSString*)method headers:(NSDictionary*)headers
{
    DBAssert(key, @"should save with a key");
    
    NSError* error = nil;
    NSString* headerStr = [self.jsonWriter stringWithObject:headers error:&error];
    if (error != nil) {
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"could not serialize: %@", headers);
        DBAssert(NO, @"No object");
    }
    
    NSString* routeKey = [self tableForRoute:route collection:collection];
    
    NSString* update = @"REPLACE INTO savequeue VALUES (:key, :id, :routeKey, :method, :headers, :time, :obj)";
    NSDictionary* valDictionary = @{@"key":[routeKey stringByAppendingString:key],
                                    @"id":key,
                                    @"obj":key,
                                    @"time":[NSDate date],
                                    @"routeKey": routeKey,
                                    @"headers": headerStr,
                                    @"method":method};
    BOOL updated = [_db executeUpdate:update withParameterDictionary:valDictionary];
    if (!updated) {
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"Error insert/updating %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    return updated;
}


- (NSDictionary*) dictObjForJson:(NSString*)s
{
    NSError* error = nil;
    NSDictionary* obj = [self.jsonParser objectWithString:s error:&error];
    if (error) {
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"DB deserialization error %@", error);
    }
    return obj;
}

- (NSArray*) unsavedEntities
{
    NSString* query = @"SELECT * from savequeue ORDER BY time";
    KCS_FMResultSet* results = [_db executeQuery:query];
    if ([_db hadError]) {
        KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"DB error (looking up unsaved entities) %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    
    //    NSDictionary* obj = nil;
    NSMutableArray* entities = [NSMutableArray array];
    while ([results next]) {
        NSDictionary* d = [results resultDictionary];
        if (d) {
            NSDictionary* obj = [self dictObjForJson:d[@"obj"]];
            if (!obj) obj = d[@"obj"];
            NSDictionary* headers = [self dictObjForJson:d[@"headers"]];
            NSString* routeKey = d[@"routeKey"];
            NSArray* routes = [routeKey componentsSeparatedByString:@"_"];
            NSString* route = routes[0];
            NSString* collection = routes[1];
            NSDictionary* entity = @{@"obj":obj,
                                     @"headers":headers,
                                     @"time":d[@"time"],
                                     @"method":d[@"method"],
                                     @"_id":d[@"id"],
                                     @"route":route,
                                     @"collection":collection};
            if (entity) {
                [entities addObject:entity];
            }
        }
    }
    return entities;
}

- (int) unsavedCount
{
    int result = [_db intForQuery:@"SELECT COUNT(*) FROM savequeue"];
    if ([_db hadError]) {
        KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"DB error in unsaved count %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    return result;
}

- (BOOL) removeUnsavedEntity:(NSString*)unsavedId route:(NSString*)route collection:(NSString*)collection
{
    KCSLogDebug(KCS_LOG_CONTEXT_FILESYSTEM, @"Deleting obj %@ from unsaved queue", unsavedId);
    
    NSString* routeKey = [self tableForRoute:route collection:collection];
    NSString* entityKey = [routeKey stringByAppendingString:unsavedId];
    
    NSString* update = [NSString stringWithFormat:@"DELETE FROM savequeue WHERE key='%@'", entityKey];
    BOOL updated = [_db executeUpdate:update];
    if (updated == NO) {
        KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    return updated;

}

#pragma mark - Updates
- (NSString*) tableForRoute:(NSString*)route collection:(NSString*)collection
{
    collection = [collection stringByReplacingOccurrencesOfString:@"-" withString:@"%2D"];
    return [NSString stringWithFormat:@"%@_%@",route,collection];
}

- (BOOL) updateWithEntity:(NSDictionary*)entity route:(NSString*)route collection:(NSString*)collection
{
    NSString* _id = entity[KCSEntityKeyId];
    if (_id == nil) {
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"nil `_id` in %@", entity);
        DBAssert(YES, @"No id!");
    }
    NSError* error = nil;
    NSString* objStr = [self.jsonWriter stringWithObject:entity error:&error];
    if (error != nil) {
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"could not serialize: %@", entity);
        DBAssert(YES, @"No object");
        return NO;
    }
    
    KCSLogDebug(KCS_LOG_CONTEXT_DATA, @"Insert/update %@/%@", _persistenceId, _id);
    NSDictionary* valDictionary = @{@"id":_id,
                                    @"obj":objStr,
                                    @"time":[NSDate date],
                                    @"dirty":@NO, //TODO
                                    @"count":@1, //TODO
                                    @"classname":@"" //TODO
                                    };
    
    NSString* table = [self tableForRoute:route collection:collection];

    if (![_db tableExists:table]) {
        NSString* update = [NSString stringWithFormat:@"CREATE TABLE %@ (id VARCHAR(255) PRIMARY KEY, obj TEXT, time VARCHAR(255), saved BOOL, count INT, classname TEXT)", table];
        BOOL created = [_db executeUpdate:update];
        if (created == NO) {
            KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }

    
    NSString* update = [NSString stringWithFormat:@"REPLACE INTO %@ VALUES (:id, :obj, :time, :dirty, :count, :classname)", table];
    BOOL updated = [_db executeUpdate:update withParameterDictionary:valDictionary];
    if (updated == NO) {
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"Error insert/updating %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    return updated;
}

- (NSDictionary*) entityForId:(NSString*)_id route:(NSString*)route collection:(NSString*)collection
{
    NSString* table = [self tableForRoute:route collection:collection];
    NSString* q = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE id='%@'", table, _id];
    
    KCSLogDebug(KCS_LOG_CONTEXT_DATA, @"DB fetching %@ from %@/%@", _id, route, collection);
    
    KCS_FMResultSet* rs = [_db executeQuery:q];
    if ([_db hadError]) {
        KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"DB error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    
    NSDictionary* obj = nil;
    if ([rs next]) {
        NSDictionary* d = [rs resultDictionary];
        if (d) {
            obj = [self dictObjForJson:d[@"obj"]];
        }
    }
    return obj;
}

- (BOOL) removeEntity:(NSString*)_id route:(NSString*)route collection:(NSString*)collection
{
//    KCSCacheValueDB* val = [self dbObjectForId:objId];
//    val.count--;
//    if (val.count == 0) {
    KCSLogDebug(KCS_LOG_CONTEXT_FILESYSTEM, @"Deleting obj %@ from cache", _id);
    NSString* table = [self tableForRoute:route collection:collection];
    NSString* update = [NSString stringWithFormat:@"DELETE FROM %@ WHERE id='%@'", table, _id];
    BOOL updated = [_db executeUpdate:update];
    if (updated == NO) {
        KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    return updated;
    //    }

}

#pragma mark - queries
- (NSString*)queryKey:(NSString*)query routeKey:(NSString*)routeKey
{
    return [@([[NSString stringWithFormat:@"%@_%@", routeKey, query] hash]) stringValue];
}

- (BOOL) setIds:(NSArray*)theseIds forQuery:(NSString*)query route:(NSString*)route collection:(NSString*)collection
{
    KCSLogDebug(KCS_LOG_CONTEXT_DATA, @"update query: '%@'", query);
    
    NSArray* oldIds = [self idsForQuery:query route:route collection:collection];
    if (oldIds && oldIds.count > 0) {
        NSMutableArray* removedIds = [oldIds mutableCopy];
        [removedIds removeObjectsInArray:theseIds];
        [self removeIds:removedIds route:route collection:collection];
    }
    
    NSError* error = nil;
    NSString* jsonStr = [self.jsonWriter stringWithObject:theseIds error:&error];
    if (error) {
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"could not serialize: %@", theseIds);
    }
    
    NSString* routeKey = [self tableForRoute:route collection:collection];
    NSString* queryKey = [self queryKey:query routeKey:routeKey];

    BOOL updated = [_db executeUpdate:@"REPLACE INTO queries VALUES (:id, :ids, :routeKey)" withArgumentsInArray:@[queryKey, jsonStr, routeKey]];
    if (updated == NO) {
        KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    return updated;
}

- (NSArray*)idsForQuery:(NSString*)query route:(NSString*)route collection:(NSString*)collection
{
    NSString* routeKey = [self tableForRoute:route collection:collection];
    NSString* queryKey = [self queryKey:query routeKey:routeKey];

    NSString* q = [NSString stringWithFormat:@"SELECT ids FROM queries WHERE id='%@'", queryKey];
    NSString* result = [_db stringForQuery:q];
    if ([_db hadError]) {
        KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        return @[];
    } else {
        NSError* error = nil;
        NSArray* ids = [self.jsonParser objectWithString:result error:&error];
        KCSLogError(KCS_LOG_CONTEXT_DATA, @"Error converting id array string into array: %@", error);
        return ids;
    }
}

- (NSUInteger) removeIds:(NSArray*)ids route:(NSString*)route collection:(NSString*)collection
{
    NSUInteger count = 0;
    for (NSString* _id in ids) {
        BOOL u = [self removeEntity:_id route:route collection:collection];
        if (u) count++;
    }
    return count;
}

- (BOOL) removeQuery:(NSString*)query route:(NSString*)route collection:(NSString*)collection
{
    KCSLogDebug(KCS_LOG_CONTEXT_DATA, @"remove query: '%@'", query);
    //TODO: deal with cleaning up unneeded entities - this just removes the query - not the associated objects
    
    NSString* routeKey = [self tableForRoute:route collection:collection];
    NSString* queryKey = [self queryKey:query routeKey:routeKey];
    
    BOOL updated = [_db executeUpdateWithFormat:@"DELETE FROM queries WHERE id=%@", queryKey];
    if (updated == NO) {
        KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    return updated;
}

#pragma mark - Import
- (BOOL) import:(NSArray *)entities route:(NSString *)route collection:(NSString *)collection
{
    if (entities == nil) return NO;
    //TODO set the all?
    for (NSDictionary* entity in entities) {
        BOOL updated = [self updateWithEntity:entity route:route collection:collection];
        if (updated == NO) {
            return NO;
        }
    }
    return YES;
}

- (NSArray*) export:(NSString*)route collection:(NSString*)collection
{
    NSString* table = [self tableForRoute:route collection:collection];
    
    if (![_db tableExists:table]) {
        KCSLogWarn(KCS_LOG_CONTEXT_DATA, @"No persisted table for '%@'", collection);
        return @[];
    }

    NSString* query = [NSString stringWithFormat:@"SELECT * FROM %@", table];
    KCS_FMResultSet* rs = [_db executeQuery:query];
    if ([_db hadError]) {
        KCSLogError(KCS_LOG_CONTEXT_FILESYSTEM, @"DB error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        return @[];
    }
    
    NSMutableArray* results = [NSMutableArray array];
    while ([rs next]) {
        NSDictionary* d = [rs resultDictionary];
        if (d) {
            id obj = [self dictObjForJson:d[@"obj"]];
            if (obj) {
                [results addObject:obj];
            }
        }
    }
    return results;
}

#pragma mark - Management
- (void) clearCaches
{
    KCSLogDebug(KCS_LOG_CONTEXT_FILESYSTEM, @"Clearing Caches");
    [_db close];
    
    NSError* error = nil;
    
    NSURL* url = [NSURL fileURLWithPath:[self dbPath]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[url path]]) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:&error];
    }
    DBAssert(!error, @"error clearing cache: %@", error);
    
    [self initDB];
}
 
@end
