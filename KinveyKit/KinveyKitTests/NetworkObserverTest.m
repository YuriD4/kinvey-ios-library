//
//  NetworkObserverTest.m
//  KinveyKit
//
//  Created by Michael Katz on 1/9/14.
//  Copyright (c) 2014 Kinvey. All rights reserved.
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
#import "KinveyCoreInternal.h"
#import "TestUtils2.h"

@interface NetworkObserverTest : SenTestCase
@property (atomic) NSInteger count;
@end

@implementation NetworkObserverTest

- (void)setUp
{
    [super setUp];
    // Put setup code here; it will be run once, before the first test case.
}

- (void)tearDown
{
    // Put teardown code here; it will be run once, after the last test case.
    [super tearDown];
}

- (void)testExample
{
    __block BOOL startHappened = NO;
    __block BOOL endHappened = NO;
    
    [[NSNotificationCenter defaultCenter] addObserverForName:KCSNetworkConnectionDidStart object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        startHappened = YES;
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:KCSNetworkConnectionDidEnd object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        endHappened = YES;
        KTPollDone
    }];
    dispatch_async(dispatch_queue_create("testq", 0), ^{
        KCSRequest2* request = [KCSRequest2 requestWithCompletion:^(KCSNetworkResponse *response, NSError *error) {
        } route:KCSRestRouteTestReflection options:@{KCSRequestOptionUseMock: @(YES), KCSRequestLogMethod} credentials:mockCredentails()];
        [request start];
    });

    KTPollStart
    STAssertTrue(startHappened, @"should get start");
    STAssertTrue(endHappened, @"should get end");
}

@end
