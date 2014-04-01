 //
//  KCSFileStore.m
//  KinveyKit
//
//  Created by Michael Katz on 6/17/13.
//  Copyright (c) 2013-2014 Kinvey. All rights reserved.
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


#import "KCSFileStore.h"

#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif

#import "NSMutableDictionary+KinveyAdditions.h"
#import "KCSLogManager.h"

#import "NSArray+KinveyAdditions.h"

#import "KCSHiddenMethods.h"
#import "KCSMetadata.h"

#import "KCSAppdataStore.h"
#import "KCSErrorUtilities.h"
#import "NSDate+KinveyAdditions.h"
#import "NSString+KinveyAdditions.h"

#import "KinveyFileStoreInteral.h"
#import "KCSPlatformUtils.h"
#import "KCSFileUtils.h"

#import "KCSRequest2.h"
#import "KCSNetworkResponse.h"

NSString* const KCSFileId = KCSEntityKeyId;
NSString* const KCSFileACL = KCSEntityKeyMetadata;
NSString* const KCSFileMimeType = @"mimeType";
NSString* const KCSFileFileName = @"_filename";
NSString* const KCSFileSize = @"size";
NSString* const KCSFileOnlyIfNewer = @"fileStoreNewer";
NSString* const KCSFileResume = @"fileStoreResume";
NSString* const KCSFileLocalURL = @"fileStoreLocalURL";
NSString* const KCSFilePublic = @"_public";
NSString* const KCSFileLinkExpirationTimeInterval = @"ttl_in_seconds";


#define kServerLMT @"serverlmt"
#define kRequiredHeaders @"_requiredHeaders"
#define kBytesWritten @"bytesWritten"
#define TIME_INTERVAL 10

NSString* kcsMimeType(id filenameOrURL)
{
    CFStringRef MIMEType = nil;
    if (filenameOrURL != nil) {
        CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[filenameOrURL pathExtension], NULL);
        if (UTI != nil) {
            MIMEType = UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType);
            CFRelease(UTI);
        }
    }
    NSString* mimeType = MIMEType ? (NSString*)CFBridgingRelease(MIMEType) : @"application/octet-stream";
    
    return mimeType;

}

#if BUILD_FOR_UNIT_TEST
static id lastRequest = nil;
#endif

@interface KCSHeadRequest : NSObject <NSURLConnectionDataDelegate, NSURLConnectionDelegate>
@property (nonatomic, copy) StreamCompletionBlock completionBlock;
- (void) headersForURL:(NSURL*)url completionBlock:(StreamCompletionBlock)completionBlock;
@end
@implementation KCSHeadRequest
- (void)headersForURL:(NSURL *)url completionBlock:(StreamCompletionBlock)completionBlock
{
    self.completionBlock = completionBlock;
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    NSURLConnection* connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    [connection start];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    _completionBlock(NO, @{}, error);
}

- (void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse* hResponse = (NSHTTPURLResponse*)response;
    NSMutableDictionary* responseDict = [NSMutableDictionary dictionary];

    NSDictionary* headers =  [hResponse allHeaderFields];
    BOOL statusOk = hResponse.statusCode >= 200 && hResponse.statusCode <= 300;
    if (statusOk) {
        NSString* serverLMTStr = headers[@"Last-Modified"];
        if (serverLMTStr != nil) {
            NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
            [formatter setLenient:YES];
            NSDate* serverLMT = [formatter dateFromString:serverLMTStr];
            if (serverLMT == nil) {
                [formatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss zzz"];
                serverLMT = [formatter dateFromString:serverLMTStr];
            }
            if (serverLMT != nil) {
                responseDict[kServerLMT] = serverLMT;
            }
        }
    }
    [connection cancel];
    _completionBlock(statusOk, responseDict, nil);
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection
{
    _completionBlock(YES, @{}, nil);
}
@end


@implementation KCSFileStore
static NSMutableSet* _ongoingDownloads;

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _ongoingDownloads = [NSMutableSet set];
    });
}

#pragma mark - Uploads
+ (void) _uploadStream:(NSInputStream*)stream
                 toURL:(NSURL*)url
       requiredHeaders:(NSDictionary*)requiredHeaders
            uploadFile:(KCSFile*)uploadFile
               options:(NSDictionary*)options
       completionBlock:(KCSFileUploadCompletionBlock)completionBlock
         progressBlock:(KCSProgressBlock)progressBlock
{
    KCSFileRequest* fileRequest = [[KCSFileRequest alloc] init];
#if BUILD_FOR_UNIT_TEST
    lastRequest =
#endif
    [fileRequest uploadStream:stream length:uploadFile.length contentType:uploadFile.mimeType toURL:url requiredHeaders:requiredHeaders completionBlock:^(BOOL done, NSDictionary *returnInfo, NSError *error) {
        uploadFile.bytesWritten = [returnInfo[kBytesWritten] longLongValue];
        completionBlock(uploadFile, error);
    } progressBlock:^(NSArray *objects, double percentComplete, NSDictionary *additionalContext) {
        if (progressBlock) {
            progressBlock(objects, percentComplete);
        }
    }];
}

+ (void) _uploadData:(NSData*)data toURL:(NSURL*)url requiredHeaders:(NSDictionary*)requiredHeaders uploadFile:(KCSFile*)uploadFile options:(NSDictionary*)options completionBlock:(KCSFileUploadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSInputStream* stream = [NSInputStream inputStreamWithData:data];
    [self _uploadStream:stream toURL:url requiredHeaders:requiredHeaders uploadFile:uploadFile options:options completionBlock:completionBlock progressBlock:progressBlock];
}

+ (void) _uploadFile:(NSURL*)localFile toURL:(NSURL*)url requiredHeaders:(NSDictionary*)requiredHeaders uploadFile:(KCSFile*)uploadFile options:(NSDictionary*)options completionBlock:(KCSFileUploadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSInputStream* stream = [NSInputStream inputStreamWithURL:localFile];
    [self _uploadStream:stream toURL:url requiredHeaders:requiredHeaders uploadFile:uploadFile options:options completionBlock:completionBlock progressBlock:progressBlock];
}

+ (KCSRequest2*) _getUploadLoc:(NSMutableDictionary *)options completion:(KCSRequestCompletionBlock)completion apiMethod:(NSString*)apiMethod
{
    //remove unwanted keys
    NSMutableDictionary* body = [NSMutableDictionary dictionaryWithDictionary:options];
    [body removeObjectForKey:KCSFileResume];
    
    NSString* fileId = body[KCSFileId];
    
    //KCSNetworkRequest* request = [[KCSNetworkRequest alloc] init];
    KCSRequest2* request = [KCSRequest2 requestWithCompletion:completion
                                                        route:KCSRESTRouteBlob
                                                      options:@{KCSRequestOptionClientMethod : apiMethod}
                                                  credentials:[KCSUser activeUser]];
    request.method = KCSRESTMethodPOST;
    if (fileId) {
        request.path = @[fileId];
        request.method = KCSRESTMethodPUT;
    } else {
        request.method = KCSRESTMethodPOST;
    }
    
    KCSMetadata* metadata = [body popObjectForKey:KCSEntityKeyMetadata];
    if (metadata) {
        body[@"_acl"] = [metadata aclValue];
    }
    
    request.body = body;
    request.headers = @{@"x-Kinvey-content-type" : body[@"mimeType"]};

    return request;
}

KCSFile* fileFromResults(NSDictionary* results)
{
    KCSFile* uploadFile = [[KCSFile alloc] init];
    uploadFile.length = [results[@"size"] unsignedIntegerValue];
    uploadFile.mimeType = results[KCSFileMimeType];
    uploadFile.fileId = results[KCSFileId];
    uploadFile.filename = results[KCSFileFileName];
    uploadFile.publicFile = results[KCSFilePublic];
    
    NSDictionary* kmd = results[@"_kmd"];
    NSDictionary* acl = results[@"_acl"];
    KCSMetadata* metadata = [[KCSMetadata alloc] initWithKMD:kmd acl:acl];
    uploadFile.metadata = metadata;

    return uploadFile;
}

+ (void)uploadData:(NSData *)data options:(NSDictionary *)uploadOptions completionBlock:(KCSFileUploadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSParameterAssert(data);
    NSParameterAssert(completionBlock);
    if (uploadOptions && uploadOptions[KCSFileSize]) {
        [[NSException exceptionWithName:@"KCSInvalidParameter" reason:@"Specifing upload file size (`KCSFileSize`) is not supported. Size is determined by the data." userInfo:nil] raise];
    }

    NSMutableDictionary* opts = [NSMutableDictionary dictionaryWithDictionary:uploadOptions];
    opts[KCSFileSize] = @(data.length);
    NSString* mimeType = opts[KCSFileMimeType];
    ifNil(mimeType, kcsMimeType(opts[KCSFileFileName]));
    setIfEmpty(opts, KCSFileMimeType, mimeType);
    
    KCSRequest2* request = [self _getUploadLoc:opts completion:^(KCSNetworkResponse *response, NSError *error) {
        if (error != nil){
            completionBlock(nil, error);
        } else {
            NSDictionary* results = [response jsonObject];
            NSString* url = results[@"_uploadURL"];
            if (url) {
                KCSFile* uploadFile = fileFromResults(results);
                NSDictionary* requiredHeaders = results[kRequiredHeaders];
                [self _uploadData:data toURL:[NSURL URLWithString:url] requiredHeaders:requiredHeaders uploadFile:uploadFile options:opts completionBlock:completionBlock progressBlock:progressBlock];
            } else {
                NSError* error = [KCSErrorUtilities createError:nil description:[NSString stringWithFormat:@"Did not get an _uploadURL id:%@", results[KCSFileId]] errorCode:KCSFileStoreLocalFileError domain:KCSFileStoreErrorDomain requestId:response.requestId];
                completionBlock(nil, error);
            }
        }
    } apiMethod:KCSRequestMethodString];
    [request start];
}

+ (void) uploadFile:(NSURL*)fileURL options:(NSDictionary*)uploadOptions completionBlock:(KCSFileUploadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSParameterAssert(fileURL != nil);
    NSParameterAssert(completionBlock != nil);
    if (uploadOptions && uploadOptions[KCSFileSize]) {
        [[NSException exceptionWithName:@"KCSInvalidParameter" reason:@"Specifing upload file size (`KCSFileSize`) is not supported. Size is determined by the size of the file's data." userInfo:nil] raise];
    }
    
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]];
    if (!exists) {
        NSError* error = [KCSErrorUtilities createError:nil description:[NSString stringWithFormat:@"fileURL does not exist '%@'", fileURL] errorCode:KCSFileStoreLocalFileError domain:KCSFileStoreErrorDomain requestId:nil];
        completionBlock(nil, error);
        return;
    }
    
    NSError* error = nil;
    NSDictionary* attr = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:&error];
    if (error != nil) {
         error = [KCSErrorUtilities createError:nil description:[NSString stringWithFormat:@"Trouble loading attributes at '%@'", fileURL] errorCode:KCSFileStoreLocalFileError domain:KCSFileStoreErrorDomain requestId:nil sourceError:error];
        completionBlock(nil, error);
        return;
    }
    
    NSMutableDictionary* opts = [NSMutableDictionary dictionaryWithDictionary:uploadOptions];
    opts[KCSFileSize] = attr[NSFileSize]; //overwrite size
    setIfEmpty(opts, KCSFileFileName, [fileURL lastPathComponent]);
    
    NSString* mimeType = kcsMimeType(fileURL);
    
    setIfEmpty(opts, KCSFileMimeType, mimeType);

    KCSRequest2 * request = [self _getUploadLoc:opts completion:^(KCSNetworkResponse *response, NSError *error) {
        if (error != nil){
            completionBlock(nil, error);
        } else {
            NSDictionary* results = [response jsonObject];
            NSString* url = results[@"_uploadURL"];
            if (url) {
                KCSFile* uploadFile = fileFromResults(results);
                uploadFile.localURL = fileURL;
                NSDictionary* requiredHeaders = results[kRequiredHeaders];
                
                [self _uploadFile:fileURL toURL:[NSURL URLWithString:url] requiredHeaders:requiredHeaders uploadFile:uploadFile options:opts completionBlock:completionBlock progressBlock:progressBlock];
            } else {
                NSError* error = [KCSErrorUtilities createError:nil description:[NSString stringWithFormat:@"Did not get an _uploadURL id:%@", results[KCSFileId]] errorCode:KCSFileStoreLocalFileError domain:KCSFileStoreErrorDomain requestId:response.requestId];
                completionBlock(nil, error);
            }
        }
    } apiMethod:KCSRequestMethodString];
    [request start];
}

#pragma mark - Downloads
+ (void) _downloadToFile:(NSURL*)localFile
                 fromURL:(NSURL*)url
                  fileId:(NSString*)fileId
                filename:(NSString*)filename
                mimeType:(NSString*)mimeType
             onlyIfNewer:(BOOL)onlyIfNewer
         downloadedBytes:(NSNumber*)bytes
         completionBlock:(KCSFileDownloadCompletionBlock)completionBlock
           progressBlock:(KCSProgressBlock)progressBlock
{
    if (!localFile) {
        [[NSException exceptionWithName:NSInternalInconsistencyException reason:@"no local file to download to." userInfo:nil] raise];
    }
    
    if ([_ongoingDownloads containsObject:fileId]) {
        NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"Download already in progress."};
        NSError* error = [NSError errorWithDomain:KCSFileStoreErrorDomain code:KCSFileError userInfo:userInfo];
        completionBlock(nil, error);
        return;
    }
    
    KCSFile* intermediateFile = [[KCSFile alloc] initWithLocalFile:localFile
                                                            fileId:fileId
                                                          filename:filename
                                                          mimeType:mimeType];
    intermediateFile.remoteURL = url;
    
    if (onlyIfNewer) {
        BOOL fileAlreadyExists = [[NSFileManager defaultManager] fileExistsAtPath:[localFile path]];
        if (fileAlreadyExists) {
            NSError* error = nil;
            NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[localFile path] error:&error];
            if (error == nil && attributes != nil) {
                NSDate* localLMT = attributes[NSFileModificationDate];
                if (localLMT != nil) {
                    //get lmt from server
                    ifNil(mimeType, kcsMimeType(localFile));
                    KCSHeadRequest* hr = [[KCSHeadRequest alloc] init];
                    [hr headersForURL:url completionBlock:^(BOOL done, NSDictionary *returnInfo, NSError *error) {
                        if (done && returnInfo && returnInfo[kServerLMT]) {
                            NSDate* serverLMT = returnInfo[kServerLMT];
                            if (ABS([localLMT timeIntervalSinceDate:serverLMT]) < TIME_INTERVAL) {
                                //don't re-download the file
                                intermediateFile.mimeType = mimeType;
                                intermediateFile.length = [attributes[NSFileSize] unsignedIntegerValue];
                                [_ongoingDownloads removeObject:fileId];
                                completionBlock(@[intermediateFile], nil);
                            } else {
                                //redownload the file
                                [self _downloadToFile:localFile fromURL:url fileId:fileId filename:filename mimeType:mimeType onlyIfNewer:NO downloadedBytes:nil completionBlock:completionBlock progressBlock:progressBlock];
                            }
                        } else {
                            // do download the whole if we can't determine the server lmt (assume it's new)
                            [self _downloadToFile:localFile fromURL:url fileId:fileId filename:filename mimeType:mimeType onlyIfNewer:NO downloadedBytes:nil completionBlock:completionBlock progressBlock:progressBlock];
                        }
                    }];
                    return; // stop here, otherwise keep doing the righteous path
                }
            }
        }

    }

    [_ongoingDownloads addObject:fileId];
    KCSLogTrace(@"Download location found, downloading file from: %@", url);
    
    KCSFileRequest* fileRequest = [[KCSFileRequest alloc] init];
#if BUILD_FOR_UNIT_TEST
    id fileop =
#endif
    [fileRequest downloadStream:intermediateFile
                        fromURL:url
            alreadyWrittenBytes:bytes
                completionBlock:^(BOOL done, NSDictionary *returnInfo, NSError *error) {
                    [_ongoingDownloads removeObject:fileId];
                    if (intermediateFile.mimeType == nil && returnInfo[KCSFileMimeType] != nil) {
                        intermediateFile.mimeType = returnInfo[KCSFileMimeType];
                    } else if (intermediateFile.mimeType == nil) {
                        intermediateFile.mimeType = kcsMimeType(intermediateFile.filename);
                    }
                    intermediateFile.bytesWritten = [returnInfo[kBytesWritten] unsignedLongLongValue];
                    intermediateFile.length = [[[NSFileManager defaultManager] attributesOfItemAtPath:[localFile path] error:NULL] fileSize];
                    
#if TARGET_OS_IPHONE
                    if (intermediateFile.localURL) {
                        NSError* error = nil;
                        [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey : [KCSFileUtils fileProtectionKey]} ofItemAtPath:[intermediateFile.localURL path] error:&error];
                        if (error) {
                            KCSLogError(@"Error setting file permissions: %@", error);
                        }
                    }
#endif
                    
                    completionBlock(@[intermediateFile], error);
                } progressBlock:^(NSArray *objects, double percentComplete, NSDictionary *additionalContext) {
                    if (progressBlock != nil) {
                        progressBlock(objects, percentComplete);
                    }
                }];
    
#if BUILD_FOR_UNIT_TEST
    lastRequest = fileop;
#endif
}


+ (void) _downloadToData:(NSURL*)url
                  fileId:(NSString*)fileId
                filename:(NSString*)filename
                mimeType:(NSString*)mimeType
         completionBlock:(KCSFileDownloadCompletionBlock)completionBlock
           progressBlock:(KCSProgressBlock)progressBlock
{
    if ([_ongoingDownloads containsObject:fileId]) {
        NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"Download already in progress.", KCSFileId : fileId};
        NSError* error = [NSError errorWithDomain:KCSFileStoreErrorDomain code:KCSFileError userInfo:userInfo];
        completionBlock(nil, error);
        return;
    } else {
        [_ongoingDownloads addObject:fileId];
    }
    
    NSURL* localFile = [KCSFileUtils fileURLForName:fileId];
    
    NSAssert(localFile != nil, @"%@ is not a valid file name for temp storage", fileId);

    KCSFile* intermediateFile = [[KCSFile alloc] initWithLocalFile:localFile
                                                            fileId:fileId
                                                          filename:filename
                                                          mimeType:mimeType];
    
    
    KCSLogTrace(@"Download location found, downloading file from: %@", url);
    KCSFileRequest* fileRequest = [[KCSFileRequest alloc] init];
    [fileRequest downloadStream:intermediateFile fromURL:url alreadyWrittenBytes:nil completionBlock:^(BOOL done, NSDictionary *returnInfo, NSError *error) {
        [_ongoingDownloads removeObject:fileId];
        
        if (error) {
            completionBlock(nil, error);
        } else {
            NSData* data = [NSData dataWithContentsOfURL:localFile];
            if (data == nil) {
                KCSLogError(@"Error reading temp file for data download: %@", localFile);
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"Error reading temp file for data download.", NSLocalizedRecoverySuggestionErrorKey : @"Retry download."};
                NSError* error = [NSError errorWithDomain:KCSFileStoreErrorDomain code:KCSFileError userInfo:userInfo];
                completionBlock(nil, error);
                return;
            }
            
            KCSFile* file = [[KCSFile alloc] initWithData:data
                                                   fileId:fileId
                                                 filename:filename
                                                 mimeType:mimeType];
            NSError* error = nil;
            [[NSFileManager defaultManager] removeItemAtURL:localFile error:&error];
            KCSLogNSError(@"error removing temp download cache", error);
            completionBlock(@[file], nil);
        }
    } progressBlock:^(NSArray *objects, double percentComplete, NSDictionary *additionalContext) {
        if (progressBlock) {
            progressBlock(objects, percentComplete);
        }
    }];
}

+ (void) _getDownloadObject:(NSString*)fileId options:(NSDictionary*)options intermediateCompletionBlock:(KCSCompletionBlock)completionBlock
{
    KCSAppdataStore* store = [KCSAppdataStore storeWithCollection:[KCSCollection fileMetadataCollection] options:nil];
    
    if (options) {
        KCSQuery* query = [KCSQuery queryOnField:KCSEntityKeyId withExactMatchForValue:fileId];
        if (options[KCSFileLinkExpirationTimeInterval]) {
            KCSQueryTTLModifier* ttl = [[KCSQueryTTLModifier alloc] initWithTTL:options[KCSFileLinkExpirationTimeInterval]];
            query.ttlModifier = ttl;
        }
#if BUILD_FOR_UNIT_TEST
        if (fieldExistsAndIsYES(options, KCSFileStoreTestExpries)) {
            KCSQueryTTLModifier* ttl = [[KCSQueryTTLModifier alloc] initWithTTL:@0.1];
            query.ttlModifier = ttl;
        }
#endif
        [store queryWithQuery:query withCompletionBlock:completionBlock withProgressBlock:nil];
    } else {
        [store loadObjectWithID:fileId withCompletionBlock:completionBlock withProgressBlock:nil];
    }
}

+ (void) _downloadFile:(NSString*)toFilename fileId:(NSString*)fileId options:(NSDictionary*)options completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    __block NSString* destinationName = toFilename;
    [self _getDownloadObject:fileId options:options intermediateCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        if (errorOrNil != nil) {
            NSError* fileError = [KCSErrorUtilities createError:nil
                                       description:[NSString stringWithFormat:@"Error downloading file, id='%@'", fileId]
                                         errorCode:errorOrNil.code
                                            domain:KCSFileStoreErrorDomain
                                         requestId:nil
                                       sourceError:errorOrNil];
            completionBlock(nil, fileError);
        } else {
            if (objectsOrNil == nil || objectsOrNil.count == 0) {
                completionBlock(@[],nil);
                return;
            }
            
            if (objectsOrNil.count != 1) {
                KCSLogError(@"returned %u results for file metadata at id '%@', expecting only 1.", objectsOrNil.count, fileId);
            }
            
#if BUILD_FOR_UNIT_TEST
            if (fieldExistsAndIsYES(options, KCSFileStoreTestExpries)) {
                KCSLogDebug(@"SLEEPING TO EXPIRE LINK");
                [NSThread sleepForTimeInterval:10];
            }
#endif
            
            KCSFile* file = objectsOrNil[0];
            if (file && file.remoteURL) {
                
                ifNil(destinationName, file.filename);
                NSURL*  destinationFile = [KCSFileUtils fileURLForName:destinationName];
                DBAssert(destinationFile != nil, @"Should have a valid destination file: '%@'", destinationName);
                
                
                if (fieldExistsAndIsYES(options, KCSFileOnlyIfNewer)) {
                    
                    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:[destinationFile path]];
                    if (fileExists) {
                        
                        NSDate* serverDate = file.metadata.lastModifiedTime;
                        NSDictionary* fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[destinationFile path] error:NULL];
                        NSDate* fileDate = fileAttributes ? [fileAttributes fileModificationDate]: nil;

                        if (![serverDate isLaterThan:fileDate]) {
                            //return existing file
                            KCSLogTrace(@"File %@ is older or same as file on disk. Using local file cache", fileId);
                            file.localURL = destinationFile;
                            if (progressBlock) {
                                progressBlock(@[file],1.0);
                            }
                            completionBlock(@[file], nil);
                            return;
                        } // else re-download the file (NOTE: requires fall through to below)
                    }
                }
                
                //TODO: handle onlyIfNewer - check time on downloadObject
                [self _downloadToFile:destinationFile fromURL:file.remoteURL fileId:fileId filename:destinationName mimeType:file.mimeType onlyIfNewer:NO downloadedBytes:nil completionBlock:completionBlock progressBlock:progressBlock];
            } else {
                NSError* error = [KCSErrorUtilities createError:nil description:@"No download url provided by Kinvey" errorCode:KCSFileError domain:KCSFileStoreErrorDomain requestId:nil];
                completionBlock(nil, error);
            }
        }
    }];
}

+ (void) _downloadData:(NSString*)fileId completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [self _getDownloadObject:fileId options:nil intermediateCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        if (errorOrNil != nil) {
            NSError* fileError = [KCSErrorUtilities createError:nil
                                                    description:[NSString stringWithFormat:@"Error downloading file, id='%@'", fileId]
                                                      errorCode:errorOrNil.code
                                                         domain:KCSFileStoreErrorDomain
                                                      requestId:nil
                                                    sourceError:errorOrNil];
            completionBlock(nil, fileError);
        } else {
            if (objectsOrNil.count != 1) {
                KCSLogError(@"returned %u results for file metadata at id '%@', expecting only 1.", objectsOrNil.count, fileId);
            }
            
            KCSFile* file = objectsOrNil[0];
            if (file && file.remoteURL) {
                [self _downloadToData:file.remoteURL fileId:fileId filename:file.filename mimeType:file.mimeType completionBlock:completionBlock progressBlock:progressBlock];
            } else {
                NSError* error = [KCSErrorUtilities createError:nil description:@"No download url provided by Kinvey" errorCode:KCSFileError domain:KCSFileStoreErrorDomain requestId:nil];
                completionBlock(nil, error);
            }
        }
    }];
}

+ (void)downloadFileByQuery:(KCSQuery *)query completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [self downloadFileByQuery:query filenames:nil options:nil completionBlock:completionBlock progressBlock:progressBlock];
}

+ (void)downloadFileByQuery:(KCSQuery *)query filenames:(NSArray*)filenames options:(NSDictionary*)options completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSParameterAssert(query != nil);
    NSParameterAssert(completionBlock != nil);
    
    KCSAppdataStore* store = [KCSAppdataStore storeWithCollection:[KCSCollection fileMetadataCollection] options:nil];
    [store queryWithQuery:query withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        if (errorOrNil != nil) {
            NSError* fileError = [KCSErrorUtilities createError:nil
                                                    description:[NSString stringWithFormat:@"Error downloading file(S), query='%@'", [query description]]
                                                      errorCode:errorOrNil.code
                                                         domain:KCSFileStoreErrorDomain
                                                      requestId:nil
                                                    sourceError:errorOrNil];
            completionBlock(nil, fileError);
        } else {
            if (objectsOrNil == nil || objectsOrNil.count == 0) {
                completionBlock(objectsOrNil, errorOrNil);
                return; //short circuit since there is no work
            }
            
            NSUInteger totalBytes = [[objectsOrNil valueForKeyPath:@"@sum.length"] unsignedIntegerValue];
            NSMutableArray* files = [NSMutableArray arrayWith:objectsOrNil.count copiesOf:[NSNull null]];

            //get ids to match the out-of order return file objects
            NSArray* destinationIds = nil;
            if (query.query != nil) {
                //parse the query object
                NSDictionary* idQuery = query.query[KCSEntityKeyId];
                //need to also check for dictionary b/c id query could be a exact match on id
                if (idQuery != nil && [idQuery isKindOfClass:[NSDictionary class]]) {
                    NSArray* inIds = idQuery[@"$in"]; // mongo ql dependency
                    if (inIds && [inIds isKindOfClass:[NSArray class]]) {
                        destinationIds = inIds;
                    }
                }
            }
            
            __block NSUInteger completedCount = 0;
            __block NSError* firstError = nil;
            [objectsOrNil enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                KCSFile* thisFile = obj;
                if (thisFile && thisFile.remoteURL) {
                    
                    NSURL* destinationFile = nil;
                    NSString* destinationFilename = thisFile.filename;
                    
                    if (destinationIds != nil && filenames != nil) {
                        NSUInteger specifiedFileIndex = [destinationIds indexOfObject:thisFile.fileId];
                        if (specifiedFileIndex != NSNotFound && specifiedFileIndex < filenames.count) {
                            destinationFilename = filenames[specifiedFileIndex];
                        }
                    }
                    
                    destinationFile = [KCSFileUtils fileURLForName:destinationFilename];

                    //TODO: onlyIfNewer check download object
                    [self _downloadToFile:destinationFile fromURL:thisFile.remoteURL fileId:thisFile.fileId filename:destinationFilename mimeType:thisFile.mimeType onlyIfNewer:NO downloadedBytes:nil completionBlock:^(NSArray *downloadedResources, NSError *error) {
                        if (error != nil && firstError == nil) {
                            firstError = error;
                        }
                        DBAssert(downloadedResources.count == 1, @"should only get 1 per download");
                        if (downloadedResources != nil && downloadedResources.count > 0) {
                            files[idx] = downloadedResources[0];
                        }
                        if (++completedCount == objectsOrNil.count) {
                            //only call completion when all done
                            completionBlock(files, firstError);
                        }
                    } progressBlock:^(NSArray *objects, double percentComplete) {
                        if (progressBlock != nil) {
                            DBAssert(objects.count == 1, @"should only get 1 per download");
                            files[idx] = objects[0];
                            double progress = 0;
                            for (KCSFile* progFile in objects) {
                                progress += percentComplete * ((double) thisFile.length / (double) totalBytes);
                            }
                            progressBlock(files,progress);
                        }
                    }];
                }
            }];
        }
    } withProgressBlock:nil];
}

+ (void)downloadFileByName:(id)nameOrNames completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSParameterAssert(nameOrNames != nil);
    NSParameterAssert(completionBlock != nil);
    
    NSArray* names = [NSArray wrapIfNotArray:nameOrNames];
    KCSQuery* nameQuery = [KCSQuery queryOnField:KCSFileFileName usingConditional:kKCSIn forValue:names];
    [self downloadFileByQuery:nameQuery completionBlock:completionBlock progressBlock:progressBlock];
}

+ (void)downloadFile:(id)idOrIds options:(NSDictionary *)options completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSParameterAssert(idOrIds != nil);
    NSParameterAssert(completionBlock != nil);
    
    BOOL idIsString = [idOrIds isKindOfClass:[NSString class]];
    BOOL idIsArray = [idOrIds isKindOfClass:[NSArray class]];

    id filename = (options != nil) ? options[KCSFileFileName] : nil;
    
    if (idIsString || (idIsArray && [idOrIds count] == 1)) {        
        [self _downloadFile:filename fileId:idOrIds options:options completionBlock:completionBlock progressBlock:progressBlock];
    } else if (idIsArray) {
        KCSQuery* idQuery = [KCSQuery queryOnField:KCSFileId usingConditional:kKCSIn forValue:idOrIds];
        [self downloadFileByQuery:idQuery filenames:filename options:options completionBlock:completionBlock progressBlock:progressBlock];
    } else {
        [[NSException exceptionWithName:@"KCSInvalidParameter" reason:@"idOrIds is not single id or array of ids" userInfo:nil] raise];
    }
    
}

+ (void)downloadDataByQuery:(KCSQuery *)query completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSParameterAssert(query != nil);
    NSParameterAssert(completionBlock != nil);

    KCSAppdataStore* store = [KCSAppdataStore storeWithCollection:[KCSCollection fileMetadataCollection] options:nil];
    [store queryWithQuery:query withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        if (errorOrNil != nil) {
            NSError* fileError = [KCSErrorUtilities createError:nil
                                                    description:[NSString stringWithFormat:@"Error downloading file(S), query='%@'", [query description]]
                                                      errorCode:errorOrNil.code
                                                         domain:KCSFileStoreErrorDomain
                                                      requestId:nil
                                                    sourceError:errorOrNil];
            completionBlock(nil, fileError);
        } else {
            if (objectsOrNil == nil || objectsOrNil.count == 0) {
                completionBlock(objectsOrNil, errorOrNil);
                return; //short circuit since there is no work
            }
            
            NSUInteger totalBytes = [[objectsOrNil valueForKeyPath:@"@sum.length"] unsignedIntegerValue];
            NSMutableArray* files = [NSMutableArray arrayWithCapacity:objectsOrNil.count];
            __block NSUInteger completedCount = 0;
            __block NSError* firstError = nil;
            [objectsOrNil enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                KCSFile* thisFile = obj;
                if (thisFile && thisFile.remoteURL) {
                    [self _downloadToData:thisFile.remoteURL fileId:thisFile.fileId filename:thisFile.filename mimeType:thisFile.mimeType completionBlock:^(NSArray *downloadedResources, NSError *error) {
                        if (error != nil && firstError == nil) {
                            firstError = error;
                        }
                        DBAssert(downloadedResources == nil || downloadedResources.count == 1, @"should only get 1 per download");
                        if (downloadedResources != nil && downloadedResources.count > 0) {
                            [files addObject:downloadedResources[0]];
                        }
                        if (++completedCount == objectsOrNil.count) {
                            //only call completion when all done
                            completionBlock(files, firstError);
                        }
                    } progressBlock:^(NSArray *objects, double percentComplete) {
                        if (progressBlock != nil) {
                            DBAssert(objects.count == 1, @"should only get 1 per download");
                            files[idx] = objects[0];
                            double progress = 0;
                            for (KCSFile* progFile in objects) {
                                progress += percentComplete * ((double) thisFile.length / (double) totalBytes);
                            }
                            progressBlock(files,progress);
                        }
                    }];
                }
            }];
        }
    } withProgressBlock:nil];
}

+ (void)downloadDataByName:(id)nameOrNames completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSParameterAssert(nameOrNames != nil);
    NSParameterAssert(completionBlock != nil);
    
    NSArray* names = [NSArray wrapIfNotArray:nameOrNames];
    KCSQuery* nameQuery = [KCSQuery queryOnField:KCSFileFileName usingConditional:kKCSIn forValue:names];
    [self downloadDataByQuery:nameQuery completionBlock:completionBlock progressBlock:progressBlock];
}

+ (void)downloadData:(id)idOrIds completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSParameterAssert(idOrIds != nil);
    NSParameterAssert(completionBlock != nil);
    
    BOOL idIsString = [idOrIds isKindOfClass:[NSString class]];
    BOOL idIsArray = [idOrIds isKindOfClass:[NSArray class]];
    
    if (idIsString || (idIsArray && [idOrIds count] == 1)) {
        [self _downloadData:idOrIds completionBlock:completionBlock progressBlock:progressBlock];
    } else if (idIsArray) {
        KCSQuery* idQuery = [KCSQuery queryOnField:KCSFileId usingConditional:kKCSIn forValue:idOrIds];
        [self downloadDataByQuery:idQuery completionBlock:completionBlock progressBlock:progressBlock];
    } else {
        [[NSException exceptionWithName:@"KCSInvalidParameter" reason:@"idOrIds is not single id or array of ids" userInfo:nil] raise];
    }
}

+ (void)downloadFileWithResolvedURL:(NSURL *)url options:(NSDictionary *)options completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSParameterAssert(url);
    NSParameterAssert(completionBlock);
    
    ifNil(options, @{});
    
    NSURL* downloadsDir = [KCSFileUtils filesFolder];
    
    //NOTE: this logic is heavily based on GCS url structure
    NSArray* pathComponents = [url pathComponents];
    NSString* filename = options[KCSFileFileName];
    ifNil(filename, [url lastPathComponent]);
    DBAssert(filename != nil, @"should have a valid filename");
    NSURL* destinationFile = options[KCSFileLocalURL];
    ifNil(destinationFile, [NSURL URLWithString:filename relativeToURL:downloadsDir]);
    NSString* fileId = pathComponents[MAX(pathComponents.count - 2, 1)];
    
    BOOL onlyIfNewer = fieldExistsAndIsYES(options, KCSFileOnlyIfNewer);
    NSNumber* bytes = nil;
    if (fieldExistsAndIsYES(options, KCSFileResume)) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:[destinationFile path]]) {
            if (![KCSPlatformUtils supportsResumeData]) {
                //iOS 6 --
                NSError* error = nil;
                NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[destinationFile path] error:&error];
                if (error == nil) {
                    bytes = attributes[NSFileSize];
                }
            } else {
                //iOS 7
                bytes = @(-1001);
            }
        }
    }
    
    
    [self _downloadToFile:destinationFile fromURL:url fileId:fileId filename:filename mimeType:nil onlyIfNewer:onlyIfNewer downloadedBytes:bytes completionBlock:completionBlock progressBlock:progressBlock];
}

+ (void)downloadDataWithResolvedURL:(NSURL *)url completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSParameterAssert(url);
    NSParameterAssert(completionBlock);
    
    [self downloadFileWithResolvedURL:url options:nil completionBlock:^(NSArray *downloadedResources, NSError *error) {
        if (!error && downloadedResources != nil && downloadedResources.count > 0) {
            KCSFile* file = downloadedResources[0];
            NSURL* localFile = file.localURL;
            if ([[NSFileManager defaultManager] fileExistsAtPath:[localFile path]]) {
                NSData* data = [NSData dataWithContentsOfURL:localFile];
                file.data = data;
                NSError* fileError = nil;
                [[NSFileManager defaultManager] removeItemAtPath:[localFile path] error:&fileError];
                if (fileError == nil) {
                    file.localURL = nil;
                } else {
                    NSString* errMessage = [NSString stringWithFormat:@"Error cleaning up file on download data %@", file.localURL];
                    KCSLogNSError(errMessage, fileError);
                }
                completionBlock(@[file], error);
            }
        } else {
            completionBlock(downloadedResources, error);
        }
    } progressBlock:progressBlock];
}

+ (void)resumeDownload:(NSURL *)partialLocalFile from:(NSURL *)resolvedURL completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSParameterAssert(partialLocalFile);
    NSParameterAssert(resolvedURL);
    NSParameterAssert(completionBlock);
    
    [self downloadFileWithResolvedURL:resolvedURL options:@{KCSFileLocalURL : partialLocalFile, KCSFileResume : @(YES)} completionBlock:completionBlock progressBlock:progressBlock];
}

#pragma mark - Streaming
+ (void) getStreamingURL:(NSString *)fileId completionBlock:(KCSFileStreamingURLCompletionBlock)completionBlock
{
    [self getStreamingURL:fileId options:nil completionBlock:completionBlock];
}

+ (void) getStreamingURL:(NSString *)fileId options:(NSDictionary*)options completionBlock:(KCSFileStreamingURLCompletionBlock)completionBlock
{
    NSParameterAssert(fileId != nil);
    NSParameterAssert(completionBlock != nil);
    
    [self _getDownloadObject:fileId options:options intermediateCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        if (errorOrNil != nil) {
            completionBlock(nil, errorOrNil);
        } else {
            if (objectsOrNil.count != 1) {
                KCSLogError(@"returned %u results for file metadata at id '%@'", objectsOrNil.count, fileId);
            }
            
            KCSFile* file = objectsOrNil[0];
            completionBlock(file, nil);
        }
    }];
}

+ (void)getStreamingURLByName:(NSString *)fileName completionBlock:(KCSFileStreamingURLCompletionBlock)completionBlock
{
    NSParameterAssert(fileName != nil);
    NSParameterAssert(completionBlock != nil);

    KCSQuery* nameQuery = [KCSQuery queryOnField:KCSFileFileName withExactMatchForValue:fileName];
    KCSAppdataStore* store = [KCSAppdataStore storeWithCollection:[KCSCollection fileMetadataCollection] options:nil];
    [store queryWithQuery:nameQuery withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        if (errorOrNil != nil) {
            completionBlock(nil, errorOrNil);
        } else {
            if (objectsOrNil.count != 1) {
                KCSLogError(@"returned %u results for file metadata with query: %@", objectsOrNil.count, nameQuery);
                errorOrNil = [KCSErrorUtilities createError:nil description:[NSString stringWithFormat:@"No matching file or more than one matching file by name: %@", fileName] errorCode:KCSNotFoundError domain:KCSResourceErrorDomain requestId:nil];
                completionBlock(nil, errorOrNil);
            } else {
                completionBlock( objectsOrNil[0], nil);
            }
        }

    } withProgressBlock:nil];
}

#pragma mark - Deletes
+ (void)deleteFile:(NSString *)fileId completionBlock:(KCSCountBlock)completionBlock
{
    NSParameterAssert(fileId != nil);
    NSParameterAssert(completionBlock != nil);
    
    KCSRequest2* request = [KCSRequest2 requestWithCompletion:^(KCSNetworkResponse *response, NSError *error) {
        if (error != nil){
            error = [KCSErrorUtilities createError:nil
                                       description:[NSString stringWithFormat:@"Error Deleting file, id='%@'", fileId]
                                         errorCode:error.code
                                            domain:KCSFileStoreErrorDomain
                                         requestId:nil
                                       sourceError:error];
            completionBlock(0, error);
        } else {
            NSDictionary* results = [response jsonObject];
            completionBlock([results[@"count"] unsignedLongValue], nil);
        }
    }
                                                        route:KCSRESTRouteBlob
                                                      options:@{KCSRequestLogMethod}
                                                  credentials:[KCSUser activeUser]];
    request.method = KCSRESTMethodDELETE;
    request.path = @[fileId];
    request.body = @{};
    [request start];
}

#pragma mark - for Linked Data

+ (void)uploadKCSFile:(KCSFile *)file options:(NSDictionary*)options completionBlock:(KCSFileUploadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    NSMutableDictionary* newOptions = [NSMutableDictionary dictionaryWithDictionary:options];
    setIfValNotNil(newOptions[KCSFileMimeType], file.mimeType);
    setIfValNotNil(newOptions[KCSFileFileName], file.filename);
    setIfValNotNil(newOptions[KCSFileId], file.fileId);
    setIfValNotNil(newOptions[KCSFileACL], file.metadata);
    
    if (file.data != nil) {
        [self uploadData:file.data options:newOptions completionBlock:completionBlock progressBlock:progressBlock];
    } else if (file.localURL != nil) {
        [self uploadFile:file.localURL options:newOptions completionBlock:completionBlock progressBlock:progressBlock];
    } else {
        [[NSException exceptionWithName:@"KCSFileStoreInvalidParameter" reason:@"Input file did not specify a data or local URL value" userInfo:nil] raise];
    }
}


+ (void)downloadKCSFile:(KCSFile*) file completionBlock:(KCSFileDownloadCompletionBlock)completionBlock progressBlock:(KCSProgressBlock) progressBlock
{
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    setIfValNotNil(options[KCSFileMimeType], file.mimeType);
    setIfValNotNil(options[KCSFileFileName], file.filename);
    setIfValNotNil(options[KCSFileId], file.fileId);
    setIfValNotNil(options[KCSFileFileName], file.filename);
    if (file.length > 0) {
        setIfValNotNil(options[KCSFileSize], @(file.length));
    }
    
    if (file.localURL) {
        if (file.fileId) {
            [self downloadFile:file.fileId options:options completionBlock:completionBlock progressBlock:progressBlock];
        } else {
            [self downloadFileByName:file.filename completionBlock:completionBlock progressBlock:progressBlock];
        }
    } else {
        if (file.fileId) {
            [self downloadData:file.fileId completionBlock:completionBlock progressBlock:progressBlock];
        } else {
            [self downloadDataByName:file.filename completionBlock:completionBlock progressBlock:progressBlock];
        }
    }
}

#pragma mark - test Helpers

#if BUILD_FOR_UNIT_TEST
+ (id) lastRequest
{
    return lastRequest;
}
#endif

#pragma mark - Cache Management
+ (void) clearCachedFiles
{
    [KCSFileUtils clearFiles];
}

@end

#pragma mark - Helpers

@implementation KCSCollection (KCSFileStore)
NSString* const KCSFileStoreCollectionName = @"_blob";

+ (instancetype)fileMetadataCollection
{
    return [KCSCollection collectionFromString:@"_blob" ofClass:[KCSFile class]];
}

@end

