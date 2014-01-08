//
//  OfflineTests.m
//  KinveyKit
//
//  Created by Michael Katz on 11/12/13.
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

#import <SenTestingKit/SenTestingKit.h>

#import "TestUtils2.h"

#import "KinveyCoreInternal.h"
#import "KinveyDataStoreInternal.h"

#import "KCSEntityPersistence.h"
#import "KCSOfflineUpdate.h"

@interface KCSUser (TestUtils)
+ (void) mockUser;
@end

@implementation KCSUser (TestUtils)
+ (void)mockUser
{
    KCSUser* user = [[KCSUser alloc] init];
    user.username = @"mock";
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
    [KCSClient sharedClient].currentUser = user;
#pragma clang diagnostic pop
}

@end


@interface OfflineDelegate : NSObject <KCSOfflineUpdateDelegate>
@property (atomic) BOOL shouldSaveCalled;
@property (atomic) BOOL willSaveCalled;
@property (atomic) BOOL didSaveCalled;
@property (atomic) BOOL shouldEnqueueCalled;
@property (atomic) BOOL didDeleteCalled;
@property (atomic) NSUInteger didEnqueCalledCount;
@property (atomic, retain) NSError* error;
@property (nonatomic, copy) void (^callback)(void);
@property (nonatomic) BOOL shouldDeleteCalled;
@property (nonatomic) BOOL willDeleteCalled;
@end
@implementation OfflineDelegate

- (BOOL)shouldSaveObject:(NSString *)objectId inCollection:(NSString *)collectionName lastAttemptedSaveTime:(NSDate *)saveTime
{
    self.shouldSaveCalled = YES;
    return YES;
}

- (void)willSaveObject:(NSString *)objectId inCollection:(NSString *)collectionName
{
    self.willSaveCalled = YES;
}

- (void)didSaveObject:(NSString *)objectId inCollection:(NSString *)collectionName
{
    self.didSaveCalled = YES;
    _callback();
}

- (BOOL)shouldEnqueueObject:(NSString *)objectId inCollection:(NSString *)collectionName onError:(NSError *)error
{
    self.shouldEnqueueCalled = YES;
    self.error = error;
    
    return YES;
}

- (void)didEnqueueObject:(NSString *)objectId inCollection:(NSString *)collectionName
{
    self.didEnqueCalledCount++;
    _callback();
}

- (BOOL)shouldDeleteObject:(NSString *)objectId inCollection:(NSString *)collectionName lastAttemptedSaveTime:(NSDate *)saveTime
{
    self.shouldDeleteCalled = YES;
    return YES;
}

- (void)willDeleteObject:(NSString *)objectId inCollection:(NSString *)collectionName
{
    self.willDeleteCalled = YES;
}

- (void)didDeleteObject:(NSString *)objectId inCollection:(NSString *)collectionName
{
    self.didDeleteCalled = YES;
    _callback();
}

@end

@interface OfflineTests : SenTestCase
@property (nonatomic, strong) KCSOfflineUpdate* update;
@property (nonatomic, strong) KCSEntityPersistence* persistence;
@property (nonatomic, strong) OfflineDelegate* delegate;
@end

@implementation OfflineTests

- (void)setUp
{
    [super setUp];
    [KCSUser mockUser];
    
    self.persistence = [[KCSEntityPersistence alloc] initWithPersistenceId:@"offlinetests"];
    [self.persistence clearCaches];
    self.delegate = [[OfflineDelegate alloc] init];
    @weakify(self);
    self.delegate.callback = ^{
        @strongify(self);
        self.done = YES;
    };
    
    self.update = [[KCSOfflineUpdate alloc] initWithCache:nil peristenceLayer:self.persistence];
    self.update.delegate = self.delegate;
    self.update.useMock = YES;
}

- (void)tearDown
{
    // Put teardown code here; it will be run once, after the last test case.
    [super tearDown];
}

- (void) testBasic
{
    NSDictionary* entity = @{@"a":@"x"};
    [self.update addObject:entity route:@"R" collection:@"C" headers:@{KCSRequestLogMethod} method:@"POST" error:nil];
    
    [self.update start];
    self.done = NO;
    [self poll];
    
    STAssertEquals([self.persistence unsavedCount], (int)0, @"should be zero");
}

- (void) testRestartNotConnected
{
    [KCSMockServer sharedServer].offline = YES;
       
    NSDictionary* entity = @{@"a":@"x"};
    [self.update addObject:entity route:@"R" collection:@"C" headers:@{KCSRequestLogMethod} method:@"POST" error:nil];
    
    [self.update start];
    self.done = NO;
    [self poll];
    
    STAssertFalse(self.delegate.didSaveCalled, @"should not have been saved");
    KTAssertEqualsInt(self.delegate.didEnqueCalledCount, 2);
    
    STAssertEquals([self.persistence unsavedCount], (int)1, @"should be one");
}


- (void) testSaveKickedOff
{
    [KCSMockServer sharedServer].offline = YES;
    
    NSDictionary* entity = @{@"a":@"x"};
    [self.update addObject:entity route:@"R" collection:@"C" headers:@{KCSRequestLogMethod} method:@"POST" error:nil];
    
    
    
    self.done = NO;
    [self.update start];
    [self poll];
    STAssertTrue(self.delegate.shouldDeleteCalled, @"should be called");
    STAssertFalse(self.delegate.didDeleteCalled, @"shoul dnot calle delete");
    STAssertFalse(self.delegate.didSaveCalled, @"should not have been saved");
    STAssertEquals([self.persistence unsavedCount], (int)1, @"should be one");


    self.done = NO;
    [KCSMockServer sharedServer].offline = NO;
    [KCSMockReachability changeReachability:YES];
    [self poll];
    
    STAssertEquals([self.persistence unsavedCount], (int)0, @"should be zero");
    STAssertTrue(self.delegate.didSaveCalled, @"should not have been saved");
}

- (void) testKickoffEventSavesObjRemovesThatObjFromQueue
{
    KTNIY
}


- (void) testDelete
{
    [KCSMockServer sharedServer].offline = YES;
    [[KCSMockServer sharedServer] setResponse:[KCSMockServer makeDeleteResponse:1] forRoute:@"r/:kid/c/X"];

    self.done = NO;
    BOOL u = [self.update removeObject:@"X" objKey:@"X" route:@"r" collection:@"c" headers:@{KCSRequestLogMethod} method:@"DELETE" error:nil];
    STAssertTrue(u, @"should be added");
    
    [self.update start];
    [self poll];
    STAssertFalse(self.delegate.didSaveCalled, @"should not have been saved");
    STAssertFalse(self.delegate.didDeleteCalled, @"should not have been saved");
    STAssertEquals([self.persistence unsavedCount], (int)1, @"should be one");
    
    self.done = NO;
    [KCSMockServer sharedServer].offline = NO;
    [KCSMockReachability changeReachability:YES];
    [self poll];
    
    STAssertEquals([self.persistence unsavedCount], (int)0, @"should be zero");
    STAssertFalse(self.delegate.didSaveCalled, @"should not have been saved");
    STAssertTrue(self.delegate.didDeleteCalled, @"should not have been saved");

}
@end
