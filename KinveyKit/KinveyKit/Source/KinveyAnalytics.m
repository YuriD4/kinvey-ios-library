//
//  KinveyAnalytics.m
//  KinveyKit
//
//  Created by Brian Wilson on 11/9/11.
//  Copyright (c) 2011-2013 Kinvey. All rights reserved.
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


#import <UIKit/UIKit.h>
#import "KinveyAnalytics.h"
#import "KCSKinveyUDID.h"
#import "NSString+KinveyAdditions.h"

// For hardware platform information
#include <sys/types.h>
#include <sys/sysctl.h>


@implementation KCSAnalytics
@synthesize UUID = _UUID;
@synthesize UDID = _UDID;

- (instancetype)init
{
    self = [super init];
    if (self){
        _UDID = [KCSKinveyUDID uniqueIdentifier];
        _UUID = nil;
        _analyticsHeaderName = @"X-Kinvey-Device-Information";
    }
    return self;
}


- (NSString *)generateUUID
{
    return [NSString UUID];
}

// Always return the same UUID for all users.
- (NSString *)UUID
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:KCS_UUID_USER_DEFAULTS_KEY] == nil) {
        [defaults setObject:[self generateUUID] forKey:KCS_UUID_USER_DEFAULTS_KEY];
        [defaults synchronize];
    }
    
    // Return the stored version
    return [defaults objectForKey:KCS_UUID_USER_DEFAULTS_KEY];

}

- (NSDictionary *)deviceInformation
{
    UIDevice *cd = [UIDevice currentDevice];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];

    // Available Features
    [d setObject:@(cd.multitaskingSupported) forKey:@"multitaskingSupported"];
    
    // Identifying Device / OS
    [d setObject:cd.name forKey:@"name"];
    [d setObject:cd.systemName forKey:@"systemName"];
    [d setObject:cd.systemVersion forKey:@"systemVersion"];
    [d setObject:cd.model forKey:@"model"];
    [d setObject:cd.localizedModel forKey:@"localizedModel"];
    [d setObject:[self platform] forKey:@"platform"];

    // Device Orientation
    [d setObject:@(cd.orientation) forKey:@"orientation"];
    [d setObject:@(cd.generatesDeviceOrientationNotifications) forKey:@"generatesDeviceOrientationNotifications"];
    
    
    // Battery
    [d setObject:@(cd.batteryLevel) forKey:@"batteryLevel"];
    [d setObject:@(cd.batteryMonitoringEnabled) forKey:@"batteryMonitoringEnabled"];
    [d setObject:@(cd.batteryState) forKey:@"batteryState"];
    
    
    // Proximity Sensor State
    [d setObject:@(cd.proximityMonitoringEnabled) forKey:@"proximityMonitoringEnabled"];
    [d setObject:@(cd.proximityState) forKey:@"proximityState"];
    
    // Record timestamp of when data was collected
    [d setObject:@([NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970) forKey:@"timestamp"];
    
    return d;
}


// From: http://www.cocos2d-iphone.org/forum/topic/21923
// NB: This is not 100% awesome and needs cleaned up
- (NSString *) platform {
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithCString:machine encoding:NSASCIIStringEncoding];
    free(machine);
    return platform;
}


- (NSString *)headerString
{
    /*
     * Model: The hardware model that's making the request
     * Platform: The platform of the device making the request
     * SystemName: The name of the system making the request
     * SystemVersion: The version of the system making the request
     * UDID: The unique device ID making the request
     */
    // Switch spaces to '_', space separate them in the following order
    // model name SystemName SystemVersion
    NSDictionary *deviceInfo = [self deviceInformation];
    NSString *headerString = [NSString stringWithFormat:@"%@/%@ %@ %@ %@",
                              [[deviceInfo objectForKey:@"model"] stringByReplacingOccurrencesOfString:@" " withString:@"_"],
                              [[deviceInfo objectForKey:@"platform"] stringByReplacingOccurrencesOfString:@" " withString:@"_"],
                              [[deviceInfo objectForKey:@"systemName"] stringByReplacingOccurrencesOfString:@" " withString:@"_"],
                              [[deviceInfo objectForKey:@"systemVersion"] stringByReplacingOccurrencesOfString:@" " withString:@"_"],
                              [self.UDID stringByReplacingOccurrencesOfString:@" " withString:@"_"]];
    
    return headerString;
}


@end
