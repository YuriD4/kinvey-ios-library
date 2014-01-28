//
//  ThreadTests.m
//  KinveyKit
//
//  Created by Michael Katz on 1/13/14.
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

#import "EXTScope.h"
#import "TestUtils2.h"
#import "KinveyKit.h"

@interface TestOperation : NSOperation
@property (nonatomic, copy) dispatch_block_t block;
@property (nonatomic) BOOL executing;
@property (nonatomic) BOOL finished;
@end

@implementation TestOperation

- (void)start
{
    [self setExecuting:YES];
    _block();
}

- (BOOL)isConcurrent
{
    return NO;
}

- (BOOL)isReady
{
    return YES;
}

- (void)setFinished:(BOOL)finished
{
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (void)setExecuting:(BOOL)executing
{
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

- (BOOL)isExecuting
{
    return _executing;
}

- (BOOL)isFinished
{
    return _finished;
}

- (BOOL)isCancelled
{
    return NO;
}

@end


@interface ThreadTests : SenTestCase <NSURLSessionDataDelegate>
@property (nonatomic) int count;
@property (nonatomic, retain) NSMutableDictionary* d;
@end

@implementation ThreadTests

static NSOperationQueue* queue;

+ (void)initialize
{
    queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 2;
    [queue setName:@"com.kinvey.KinveyKit.TestQueue"];
}

- (void)setUp
{
    [super setUp];
    _count = 0;
    _d = [NSMutableDictionary dictionary];
    // Put setup code here; it will be run once, before the first test case.
}

- (void)tearDown
{
    // Put teardown code here; it will be run once, after the last test case.
    [super tearDown];
}

- (void) runOp:(TestOperation*)op
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        double delayInSeconds = 2.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
            NSURLSessionConfiguration* config = [NSURLSessionConfiguration defaultSessionConfiguration];
            NSOperationQueue* q = [[NSOperationQueue alloc] init];
            NSURLSession* session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:q];
            //            session.delegate = self;
            NSURLSessionDataTask* task = [session dataTaskWithURL:[NSURL URLWithString:@"http://localhost:3000/locations"]];
            _d[task] = op;
            [task resume];
             
//            [[session dataTaskWithURL:[NSURL URLWithString:@"http://localhost:3000/locations"]
//              
//                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
//                op.finished = YES;
//                NSLog(@"%@ done", op);
//                _count++;
//                self.done = (_count==3);
//            }] resume];
            
        });
        
    });

}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    TestOperation* op = _d[task];
    op.finished = YES;
    NSLog(@"%@ done", op);
    _count++;
    self.done = (_count==3);
}

- (void) makeAndRunOp
{
    TestOperation* op = [[TestOperation alloc] init];
    @weakify(op);
    op.block = ^{
        @strongify(op);
        [self runOp:op];
    };
    [queue addOperation:op];
}

- (void)testExample
{
    if ([[[UIDevice currentDevice] systemVersion] compare:@"7" options:NSNumericSearch] == NSOrderedAscending) {
        return;
    }
    
    NSLog(@"COUNT %d", (int)queue.operationCount);
    NSLog(@"ITEMS %@", queue.operations);
    
    self.done = NO;
    
    [self makeAndRunOp];
    [self makeAndRunOp];
    [self makeAndRunOp];
    
    [self poll];

    
    STAssertEquals(_count, 3, @".");
}

- (void) testThreadTestDataStore
{
    KCSClientConfiguration* config = [KCSClientConfiguration configurationWithAppKey:@"kid_TTmaAVkCeO" secret:@"c194704457f5479e869c3c57d56deaae"];
    [[KCSClient sharedClient] initializeWithConfiguration:config];
    [KCSClient configureLoggingWithNetworkEnabled:YES debugEnabled:YES traceEnabled:YES warningEnabled:YES errorEnabled:YES];
    
    self.done = NO;
    [KCSUser loginWithUsername:@"roger" password:@"roger" withCompletionBlock:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
        STAssertNil(errorOrNil, @"error should be nil");
        self.done = YES;
    }];
    [self poll];
    
    self.done = NO;
    KCSAppdataStore* store = [KCSAppdataStore storeWithCollection:[KCSCollection userCollection] options:nil];

    NSArray* toFetch = @[@"523a0b3fd4af557103001771",@"523a0b3fd4af557103001771",@"523c4c2371037d725e007dac",@"523c4c2371037d725e007dac",@"523c4c2371037d725e007dac",@"523c4c2371037d725e007dac",@"523c4c2371037d725e007dac",@"523c4c2371037d725e007dac",@"523c4c2371037d725e007dac"];
    for (NSString* anId in toFetch){
        [store loadObjectWithID:anId withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
            STAssertNil(errorOrNil, @"no error");
            self.done = ++_count == toFetch.count;
        } withProgressBlock:nil];
    }
    
    [self poll];
}

@end
