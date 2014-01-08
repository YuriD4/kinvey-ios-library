//
//  KinveyCollectionStoreTests.m
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


#import "KinveyAppdataStoreTests.h"
#import <KinveyKit/KinveyKit.h>
#import "ASTTestClass.h"

#import "TestUtils.h"

#import "KCSMockConnection.h"
#import "KCS_SBJson.h"

@implementation KinveyAppdataStoreTests

- (void) setUp
{
    BOOL setup = [TestUtils setUpKinveyUnittestBackend];
    STAssertTrue(setup, @"should be set-up");
    
    _collection = [[KCSCollection alloc] init];
    _collection.collectionName = [NSString stringWithFormat:@"testObjects%i", arc4random()];
    _collection.objectTemplate = [ASTTestClass class];
    
    _store = [KCSAppdataStore storeWithCollection:_collection options:nil];

}

-(void)testSaveOne
{
    self.done = NO;
    [_store loadObjectWithID:@"testobj" withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNil(objectsOrNil, @"expecting a nil objects");
        STAssertNotNil(errorOrNil, @"expecting an error");
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
    
    ASTTestClass *obj = [self makeObject:@"description" count:-88 objId:@"testobj"];
    
    self.done = NO;
    [_store saveObject:obj withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
    
    self.done = NO;
    [_store loadObjectWithID:@"testobj" withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNotNil(objectsOrNil, @"expecting a non-nil objects");
        STAssertEquals((int) [objectsOrNil count], 1, @"expecting one object of id 'testobj' to be found");
        STAssertEquals((int) [[objectsOrNil objectAtIndex:0] objCount], -88, @"expecting save to have completed sucessfully");
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
}

-(void)testSaveMany
{
    NSMutableArray* baseObjs = [NSMutableArray array];
    [baseObjs addObject:[self makeObject:@"one" count:10]];
    [baseObjs addObject:[self makeObject:@"two" count:10]];
    [baseObjs addObject:[self makeObject:@"two" count:30]];
    [baseObjs addObject:[self makeObject:@"two" count:70]];
    [baseObjs addObject:[self makeObject:@"one" count:5]];
    
    self.done = NO;
    [_store saveObject:baseObjs withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        self.done = YES;
        STAssertNotNil(objectsOrNil, @"expecting a non-nil objects");
        STAssertEquals((int) [objectsOrNil count], 5, @"expecting five objects returned for saving five objects");
    } withProgressBlock:nil];
    [self poll];
}


NSString* largeStringOfSize(int size) 
{
    NSMutableString* string  = [NSMutableString stringWithCapacity:size];
    while (string.length < size) {
        [string appendFormat:@"%i",arc4random()];
    }
    return string;
}

NSString* largeString() 
{
    return largeStringOfSize(1e6);
}

- (void) upTimeout
{
    KCSClientConfiguration* conifg = [KCSClient sharedClient].configuration;
    NSMutableDictionary* d = [NSMutableDictionary dictionaryWithDictionary:conifg.options];
    d[KCS_CONNECTION_TIMEOUT] = @1000;
    conifg.options = d;
    [[KCSClient sharedClient] setConfiguration:conifg];
}

- (void)testQueryHuge
{
    [self upTimeout];
    
    self.done = NO;
    KCSQuery* query = [KCSQuery queryOnField:@"foo" withExactMatchForValue:largeString()];
    [_store queryWithQuery:query withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNoError
        self.done = YES;
    } withProgressBlock:^(NSArray *objects, double percentComplete) {
        NSLog(@"progress = %f", percentComplete);
    }];
    [self poll:120];
}

NSArray* largeArray() 
{
    int size = 1e4;
    NSMutableArray* array = [NSMutableArray arrayWithCapacity:size];
    for (int i=0; i<size; i++) {
        [array addObject:largeStringOfSize(1e3)];
    }
    return array;
}

- (void)testQueryLargeIn
{
    [self upTimeout];
    self.done = NO;
    KCSQuery* query = [KCSQuery queryOnField:@"foo" usingConditional:kKCSIn forValue:largeArray()];
    [_store queryWithQuery:query withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNoError
        self.done = YES;
    } withProgressBlock:^(NSArray *objects, double percentComplete) {
        NSLog(@"progress = %f", percentComplete);
    }];
    [self poll:120];
}

- (void)testRemoveOne
{
    self.done = NO;
    __block ASTTestClass* obj = [self makeObject:@"abc" count:100];
    [_store saveObject:obj withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNoError;
        obj = [objectsOrNil objectAtIndex:0];
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
    
    NSString* objId = obj.objId;
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:4]];
    
    self.done = NO;
    [_store removeObject:obj withCompletionBlock:^(unsigned long count, NSError *errorOrNil) {
        STAssertNoError;
        KTAssertEqualsInt(count, 1, @"should delete one object");
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
    
    self.done = NO;
    [_store loadObjectWithID:objId withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        NSLog(@"--- %@ -- %@", objectsOrNil, errorOrNil);
        STAssertNotNil(errorOrNil, @"should have an error");
        STAssertEquals((int)KCSNotFoundError, [errorOrNil code], @"should have been not found");
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
}

- (void)testRemoveXAll
{
    self.done = NO;
    NSMutableArray* all = [NSMutableArray arrayWithCapacity:10];
    for (int i=0; i < 10; i++) {
        ASTTestClass* obj = [self makeObject:@"testRemoveAll" count:i];
        [all addObject:obj];
    }
    __block NSArray* vals = nil;
    [_store saveObject:all withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNoError;
        vals = objectsOrNil;
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
    
    
    self.done = NO;
    [_store removeObject:vals withCompletionBlock:^(unsigned long count, NSError *errorOrNil) {
        STAssertNoError;
        KTAssertEqualsInt(count, 10, @"should delete one object");

        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
    
    self.done = NO;
    [_store countWithBlock:^(unsigned long count, NSError *errorOrNil) {
        STAssertEquals((unsigned long) 0, count, @"should have deleted all");
        self.done = YES;
    }];
    [self poll];

}

- (void) testBlErrors
{
    KCSAppdataStore* store = [KCSAppdataStore storeWithCollection:[KCSCollection collectionFromString:@"bl-errors" ofClass:[NSMutableDictionary class]] options:@{}];
    self.done = NO;
    [store queryWithQuery:[KCSQuery query] withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNotNil(errorOrNil, @"should have an error");
        KTAssertEqualsInt(errorOrNil.code, 550, @"should be a 550");
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
}

- (ASTTestClass*)makeObject:(NSString*)desc count:(int)count
{
    ASTTestClass *obj = [[ASTTestClass alloc] init];
    obj.objDescription = desc;
    obj.objCount = count;
    return obj;
}

- (ASTTestClass*)makeObject:(NSString*)desc count:(int)count objId:(NSString*)objId
{
    ASTTestClass *obj = [[ASTTestClass alloc] init];
    obj.objDescription = desc;
    obj.objCount = count;
    obj.objId = objId;
    return obj;
}

- (void) testGroupBy
{
    NSMutableArray* baseObjs = [NSMutableArray array];
    [baseObjs addObject:[self makeObject:@"one" count:10]];
    [baseObjs addObject:[self makeObject:@"two" count:10]];
    [baseObjs addObject:[self makeObject:@"two" count:10]];
    [_store saveObject:baseObjs withCompletionBlock:[self pollBlock] withProgressBlock:nil];
    [self poll];
    
    
    self.done = NO;
    [_store group:[NSArray arrayWithObject:@"objDescription"] reduce:[KCSReduceFunction COUNT] completionBlock:^(KCSGroup *valuesOrNil, NSError *errorOrNil) {
        STAssertNil(errorOrNil, @"got error: %@", errorOrNil);
        
        NSNumber* value = [valuesOrNil reducedValueForFields:[NSDictionary dictionaryWithObjectsAndKeys:@"one", @"objDescription", nil]];
        STAssertEquals([value intValue], 1, @"expecting one objects of 'one'");
        
        value = [valuesOrNil reducedValueForFields:[NSDictionary dictionaryWithObjectsAndKeys:@"two", @"objDescription", nil]];
        STAssertEquals([value intValue], 2, @"expecting two objects of 'two'");
        
        self.done = YES;
    } progressBlock:nil];
    [self poll];
    
    self.done = NO;
    [_store group:[NSArray arrayWithObject:@"objDescription"] reduce:[KCSReduceFunction SUM:@"objCount"] completionBlock:^(KCSGroup *valuesOrNil, NSError *errorOrNil) {
        STAssertNil(errorOrNil, @"got error: %@", errorOrNil);
        
        NSNumber* value = [valuesOrNil reducedValueForFields:[NSDictionary dictionaryWithObjectsAndKeys:@"one", @"objDescription", nil]];
        STAssertEquals([value intValue],10, @"expecting one objects of 'one'");
        
        value = [valuesOrNil reducedValueForFields:[NSDictionary dictionaryWithObjectsAndKeys:@"two", @"objDescription", nil]];
        STAssertEquals([value intValue], 20, @"expecting two objects of 'two'");
        
        self.done = YES;
    } progressBlock:nil];
    [self poll];
}

- (void) testGroupByWithCondition
{
    NSMutableArray* baseObjs = [NSMutableArray array];
    [baseObjs addObject:[self makeObject:@"one" count:10]];
    [baseObjs addObject:[self makeObject:@"two" count:10]];
    [baseObjs addObject:[self makeObject:@"two" count:30]];
    [baseObjs addObject:[self makeObject:@"two" count:70]];
    [baseObjs addObject:[self makeObject:@"one" count:5]];
    [_store saveObject:baseObjs withCompletionBlock:[self pollBlock] withProgressBlock:nil];
    [self poll];
    
    
    self.done = NO;
    KCSQuery* condition = [KCSQuery queryOnField:@"objCount" usingConditional:kKCSGreaterThan forValue:[NSNumber numberWithInt:10]];
    [_store group:[NSArray arrayWithObject:@"objDescription"] reduce:[KCSReduceFunction COUNT] condition:condition completionBlock:^(KCSGroup *valuesOrNil, NSError *errorOrNil) {
        STAssertNil(errorOrNil, @"got error: %@", errorOrNil);
        
        NSNumber* value = [valuesOrNil reducedValueForFields:[NSDictionary dictionaryWithObjectsAndKeys:@"one", @"objDescription", nil]];
        STAssertEquals([value intValue], NSNotFound, @"expecting one objects of 'one'");
        
        value = [valuesOrNil reducedValueForFields:[NSDictionary dictionaryWithObjectsAndKeys:@"two", @"objDescription", nil]];
        STAssertEquals([value intValue], 2, @"expecting two objects of 'two'");
        
        self.done = YES;
    } progressBlock:nil];
    [self poll];
    
    self.done = NO;
    [_store group:[NSArray arrayWithObject:@"objDescription"] reduce:[KCSReduceFunction SUM:@"objCount"] condition:condition completionBlock:^(KCSGroup *valuesOrNil, NSError *errorOrNil) {
        STAssertNil(errorOrNil, @"got error: %@", errorOrNil);
        
        NSNumber* value = [valuesOrNil reducedValueForFields:[NSDictionary dictionaryWithObjectsAndKeys:@"one", @"objDescription", nil]];
        STAssertEquals([value intValue], NSNotFound, @"expecting one objects of 'one'");
        
        value = [valuesOrNil reducedValueForFields:[NSDictionary dictionaryWithObjectsAndKeys:@"two", @"objDescription", nil]];
        STAssertEquals([value intValue], 100, @"expecting two objects of 'two'");
        
        self.done = YES;
    } progressBlock:nil];
    [self poll];
    
}

- (void) testGroupByMultipleFields
{
    NSMutableArray* baseObjs = [NSMutableArray array];
    [baseObjs addObject:[self makeObject:@"one" count:10]];
    [baseObjs addObject:[self makeObject:@"one" count:10]];
    [baseObjs addObject:[self makeObject:@"two" count:10]];
    [baseObjs addObject:[self makeObject:@"two" count:30]];
    //    [baseObjs addObject:[self makeObject:@"two" count:70]];
    [baseObjs addObject:[self makeObject:@"one" count:5]];
    [baseObjs addObject:[self makeObject:@"two" count:70]];    
    [_store saveObject:baseObjs withCompletionBlock:[self pollBlock] withProgressBlock:nil];
    [self poll];
    
    
    self.done = NO;
    [_store group:[NSArray arrayWithObjects:@"objDescription", @"objCount", nil] reduce:[KCSReduceFunction COUNT] completionBlock:^(KCSGroup *valuesOrNil, NSError *errorOrNil) {
        STAssertNil(errorOrNil, @"got error: %@", errorOrNil);
        
        NSNumber* value = [valuesOrNil reducedValueForFields:@{@"objDescription":@"one", @"objCount" :@10}];
        STAssertEquals([value intValue], 2, @"expecting two objects of 'one' & count == 0");
        
        value = [valuesOrNil reducedValueForFields:@{@"objDescription":@"two",@"objCount":@30}];
        STAssertEquals([value intValue], 1, @"expecting just one object of 'two', because this should bail after finding the first match of two");
        
        self.done = YES;
    } progressBlock:nil];
    [self poll];
    
    self.done = NO;
    KCSQuery* condition = [KCSQuery queryOnField:@"objCount" usingConditional:kKCSGreaterThanOrEqual forValue:@10];
    [_store group:@[@"objDescription", @"objCount"] reduce:[KCSReduceFunction SUM:@"objCount"] condition:condition completionBlock:^(KCSGroup *valuesOrNil, NSError *errorOrNil) {
        STAssertNil(errorOrNil, @"got error: %@", errorOrNil);
        
        NSNumber* value = [valuesOrNil reducedValueForFields:[NSDictionary dictionaryWithObjectsAndKeys:@"one", @"objDescription", [NSNumber numberWithInt:10], @"objCount", nil]];
        STAssertEquals([value intValue], 20, @"expecting to have sumed objects of 'one' and count == 10");
        
        value = [valuesOrNil reducedValueForFields:@{@"objDescription" : @"two"}];
        STAssertTrue([value intValue] == 30 || [value intValue] == 70, @"expecting just the first obj of 'two'");
        
        self.done = YES;
    } progressBlock:nil];
    [self poll];
    
}

- (void) testLoadById
{
    NSMutableArray* baseObjs = [NSMutableArray array];
    [baseObjs addObject:[self makeObject:@"one" count:10 objId:@"a1"]];
    [baseObjs addObject:[self makeObject:@"one" count:10 objId:@"a2"]];
    [baseObjs addObject:[self makeObject:@"two" count:10 objId:@"a3"]];
    [baseObjs addObject:[self makeObject:@"two" count:30 objId:@"a4"]];
    [baseObjs addObject:[self makeObject:@"two" count:70 objId:@"a5"]];
    [baseObjs addObject:[self makeObject:@"one" count:5  objId:@"a6"]];
    [baseObjs addObject:[self makeObject:@"two" count:70 objId:@"a7"]];    
    [_store saveObject:baseObjs withCompletionBlock:[self pollBlock] withProgressBlock:nil];
    [self poll];
    
    self.done = NO;
    __block NSArray* objs = nil;
    [_store loadObjectWithID:@"a6" withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNoError;
        objs = objectsOrNil;
        STAssertNotNil(objs, @"expecting to load some objects");
        STAssertEquals((int) [objs count], 1, @"should only load one object");
        STAssertEquals((int) [[objs objectAtIndex:0] objCount], 5, @"expecting 6 from a6");
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];

   
    
    self.done = NO;
    objs = nil;
    [_store loadObjectWithID:[NSArray arrayWithObjects:@"a1",@"a2",@"a3", nil] withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNoError
        objs = objectsOrNil;
        STAssertNotNil(objs, @"expecting to load some objects");
        STAssertEquals((int) [objs count], 3, @"should only load one object");
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
}

//TODO: test progress as failure completion blocks;

- (void) testEmptyResponse
{
    self.done = NO;
    [_store queryWithQuery:[KCSQuery queryOnField:@"count" withExactMatchForValue:@"NEVER MATCH"] withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNoError;
        STAssertEquals((NSUInteger)0, objectsOrNil.count, @"should be empty array");
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
}

- (void) testStreamingResults
{
    NSMutableArray* baseObjs = [NSMutableArray array];
    [baseObjs addObject:[self makeObject:@"one" count:10 objId:@"a1"]];
    [baseObjs addObject:[self makeObject:@"one" count:10 objId:@"a2"]];
    [baseObjs addObject:[self makeObject:@"two" count:10 objId:@"a3"]];
    [baseObjs addObject:[self makeObject:@"two" count:30 objId:@"a4"]];
    [baseObjs addObject:[self makeObject:@"two" count:70 objId:@"a5"]];
    [baseObjs addObject:[self makeObject:@"one" count:5  objId:@"a6"]];
    [baseObjs addObject:[self makeObject:@"two" count:70 objId:@"a7"]];
    [_store saveObject:baseObjs withCompletionBlock:[self pollBlock] withProgressBlock:nil];
    [self poll];
    
    self.done = NO;
    __block float done = -1;
    __block NSArray* objs = nil;
    [_store queryWithQuery:[KCSQuery query] withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNoError
        objs = objectsOrNil;
        STAssertNotNil(objs, @"expecting to load some objects");
        self.done = YES;
    } withProgressBlock:^(NSArray *objects, double percentComplete) {
        NSLog(@"testStreamingResults: percentcomplete:%f", percentComplete);
        STAssertTrue(percentComplete > done, @"should be monotonically increasing");
        STAssertTrue(percentComplete <= 1.0, @"should be less than equal 1");
        done = percentComplete;
        
        STAssertNotNil(objects, @"should have objects");
        STAssertTrue(objects.count >=1, @"should have at least object");
        id obj = objects[0];
        STAssertTrue([obj isKindOfClass:[ASTTestClass class]], @"class should be test class type");
    }];
    [self poll];
}

#pragma mark - Count

- (void) testCountWithQuery
{
    NSMutableArray* baseObjs = [NSMutableArray array];
    [baseObjs addObject:[self makeObject:@"one" count:10 objId:@"a1"]];
    [baseObjs addObject:[self makeObject:@"one" count:10 objId:@"a2"]];
    [baseObjs addObject:[self makeObject:@"two" count:10 objId:@"a3"]];
    [baseObjs addObject:[self makeObject:@"two" count:30 objId:@"a4"]];
    [baseObjs addObject:[self makeObject:@"two" count:70 objId:@"a5"]];
    [baseObjs addObject:[self makeObject:@"one" count:5  objId:@"a6"]];
    [baseObjs addObject:[self makeObject:@"two" count:70 objId:@"a7"]];
    [_store saveObject:baseObjs withCompletionBlock:[self pollBlock] withProgressBlock:nil];
    [self poll];
    
    self.done = NO;
    KCSQuery* q = [KCSQuery queryOnField:@"objDescription" withExactMatchForValue:@"one"];
    [_store countWithQuery:q completion:^(unsigned long count, NSError *errorOrNil) {
        STAssertNoError
        unsigned long exp = 3;
        STAssertEquals(exp, count, @"expeting count");
        self.done = YES;
    }];
    [self poll];

    self.done = NO;
    [q addQueryOnField:@"objCount" withExactMatchForValue:@(10)];
    [_store countWithQuery:q completion:^(unsigned long count, NSError *errorOrNil) {
        STAssertNoError
        unsigned long exp = 2;
        STAssertEquals(exp, count, @"expeting count");
        self.done = YES;
    }];
    [self poll];
}
@end
