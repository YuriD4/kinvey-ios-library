//
//  FileStore.swift
//  Kinvey
//
//  Created by Victor Barros on 2016-02-04.
//  Copyright © 2016 Kinvey. All rights reserved.
//

import Foundation
import PromiseKit

/// Class to interact with the `Files` collection in the backend.
public class FileStore {
    
    public typealias FileCompletionHandler = (File?, ErrorType?) -> Void
    public typealias FileDataCompletionHandler = (File?, NSData?, ErrorType?) -> Void
    public typealias FilePathCompletionHandler = (File?, NSURL?, ErrorType?) -> Void
    public typealias UIntCompletionHandler = (UInt?, ErrorType?) -> Void
    public typealias FileArrayCompletionHandler = ([File]?, ErrorType?) -> Void
    
    private let client: Client
    private let cache: FileCache?
    
    /// Factory method that returns a `FileStore`.
    public class func getInstance(client: Client = sharedClient) -> FileStore {
        return FileStore(client: client)
    }
    
    private init(client: Client) {
        self.client = client
        self.cache = client.cacheManager.fileCache(filePath: client.filePath())
    }

#if os(iOS)
    /// Uploads a `UIImage` in a PNG format.
    public func upload(file: File, image: UIImage, completionHandler: FileCompletionHandler? = nil) -> Request {
        let data = UIImagePNGRepresentation(image)!
        file.mimeType = "image/png"
        return upload(file, data: data, completionHandler: completionHandler)
    }
#endif
    
    /// Uploads a file using the file path.
    public func upload(file: File, path: String, completionHandler: FileCompletionHandler? = nil) -> Request {
        return upload(file, stream: NSInputStream(fileAtPath: path)!, completionHandler: completionHandler)
    }
    
    /// Uploads a file using a input stream.
    public func upload(file: File, stream: NSInputStream, completionHandler: FileCompletionHandler? = nil) -> Request {
        let data = NSMutableData()
        stream.open()
        var buffer = [UInt8](count: 4096, repeatedValue: 0)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            data.appendBytes(buffer, length: read)
        }
        stream.close()
        return upload(file, data: data, completionHandler: completionHandler)
    }
    
    private func fillFile(file: File, json: [String : AnyObject]) {
        if let fileId = json["_id"] as? String {
            file.fileId = fileId
        }
        if let filename = json["_filename"] as? String {
            file.fileName = filename
        }
        if let publicAccessible = json["_public"] as? Bool {
            file.publicAccessible = publicAccessible
        }
        if let acl = json["_acl"] as? [String : AnyObject] {
            file.acl = Acl(JSON: acl)
        }
        if let kmd = json["_kmd"] as? [String : AnyObject] {
            file.metadata = Metadata(JSON: kmd)
        }
        if let uploadURL = json["_uploadURL"] as? String {
            file.uploadURL = NSURL(string: uploadURL)
        }
        if let downloadURL = json["_downloadURL"] as? String {
            file.download = downloadURL
        }
        if let requiredHeaders = json["_requiredHeaders"] as? [String : String] {
            file.uploadHeaders = requiredHeaders
        }
        if let expiresAt = json["_expiresAt"] as? String {
            let dateFormatter = NSDateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            file.expiresAt = dateFormatter.dateFromString(expiresAt)
        }
    }
    
    private func getFileMetadata(file: File, ttl: TTL? = nil) -> (Request, Promise<File>) {
        let request = self.client.networkRequestFactory.buildBlobDownloadFile(file, ttl: ttl)
        return (request, Promise<File> { fulfill, reject in
            request.execute({ (data, response, error) -> Void in
                if let response = response where response.isOK, let json = self.client.responseParser.parse(data) {
                    self.fillFile(file, json: json)
                    fulfill(file)
                } else if let error = error {
                    reject(error)
                } else {
                    reject(Error.InvalidResponse)
                }
            })
        })
    }
    
    /// Uploads a file using a `NSData`.
    public func upload(file: File, data: NSData, completionHandler: FileCompletionHandler? = nil) -> Request {
        let requests = MultiRequest()
        Promise<(file: File, skip: Int?)> { fulfill, reject in //creating bucket
            let createUpdateFileEntry = {
                let request = self.client.networkRequestFactory.buildBlobUploadFile(file)
                requests += request
                request.execute({ (data, response, error) -> Void in
                    if let response = response where response.isOK, let json = self.client.responseParser.parse(data) {
                        self.fillFile(file, json: json)
                        fulfill((file: file, skip: nil))
                    } else if let error = error {
                        reject(error)
                    } else {
                        reject(Error.InvalidResponse)
                    }
                })
            }
            
            if let _ = file.fileId {
                let request = NSMutableURLRequest(URL: file.uploadURL!)
                request.HTTPMethod = "PUT"
                if let uploadHeaders = file.uploadHeaders {
                    for header in uploadHeaders {
                        request.setValue(header.1, forHTTPHeaderField: header.0)
                    }
                }
                request.setValue("0", forHTTPHeaderField: "Content-Length")
                request.setValue("bytes */\(data.length)", forHTTPHeaderField: "Content-Range")
                
                if self.client.logNetworkEnabled {
                    do {
                        print("\(request)")
                    }
                }
                
                let dataTask = self.client.urlSession.dataTaskWithRequest(request) { (data, response, error) in
                    if self.client.logNetworkEnabled, let response = response as? NSHTTPURLResponse {
                        do {
                            print("\(response.description(data))")
                        }
                    }
                    
                    let regexRange = try! NSRegularExpression(pattern: "[bytes=]?(\\d+)-(\\d+)", options: [])
                    if let response = response as? NSHTTPURLResponse where 200 <= response.statusCode && response.statusCode < 300 {
                        createUpdateFileEntry()
                    } else if let response = response as? NSHTTPURLResponse
                        where response.statusCode == 308,
                        let rangeString = response.allHeaderFields["Range"] as? String,
                        let textCheckingResult = regexRange.matchesInString(rangeString, options: [], range: NSMakeRange(0, rangeString.characters.count)).first
                        where textCheckingResult.numberOfRanges == 3
                    {
                        let rangeNSString = rangeString as NSString
                        let endRangeString = rangeNSString.substringWithRange(textCheckingResult.rangeAtIndex(2))
                        if let endRange = Int(endRangeString) {
                            fulfill((file: file, skip: endRange))
                        } else {
                            reject(Error.InvalidResponse)
                        }
                    } else if let error = error {
                        reject(error)
                    } else {
                        reject(Error.InvalidResponse)
                    }
                }
                requests += NSURLSessionTaskRequest(client: client, task: dataTask)
                dataTask.resume()
            } else {
                createUpdateFileEntry()
            }
        }.then { file, skip in //uploading data
            return Promise<File> { fulfill, reject in
                let request = NSMutableURLRequest(URL: file.uploadURL!)
                request.HTTPMethod = "PUT"
                if let uploadHeaders = file.uploadHeaders {
                    for header in uploadHeaders {
                        request.setValue(header.1, forHTTPHeaderField: header.0)
                    }
                }
                let uploadData: NSData
                if let skip = skip {
                    let startIndex = skip + 1
                    uploadData = data.subdataWithRange(NSMakeRange(startIndex, data.length - startIndex))
                    request.setValue("bytes \(startIndex)-\(data.length - 1)/\(data.length)", forHTTPHeaderField: "Content-Range")
                } else {
                    uploadData = data
                }
                let uploadTask = self.client.urlSession.uploadTaskWithRequest(request, fromData: uploadData) { (data, response, error) -> Void in
                    if let response = response as? NSHTTPURLResponse where 200 <= response.statusCode && response.statusCode < 300 {
                        fulfill(file)
                    } else if let error = error {
                        reject(error)
                    } else {
                        reject(Error.InvalidResponse)
                    }
                }
                requests += NSURLSessionTaskRequest(client: self.client, task: uploadTask)
                uploadTask.resume()
            }
        }.then { file in //fetching download url
            return self.getFileMetadata(file).1
        }.then { file in
            completionHandler?(file, nil)
        }.error { error in
            completionHandler?(file, error)
        }
        return requests
    }
    
    /// Refresh a `File` instance.
    public func refresh(file: File, ttl: TTL? = nil, completionHandler: FileCompletionHandler? = nil) -> Request {
        let fileMetadata = getFileMetadata(file, ttl: ttl)
        let request = fileMetadata.0
        fileMetadata.1.then { file in
            completionHandler?(file, nil)
        }.error { error in
            completionHandler?(file, error)
        }
        return request
    }
    
    private func downloadFile(file: File, cacheEnabled: Bool = true, downloadURL: NSURL, completionHandler: FilePathCompletionHandler? = nil) -> NSURLSessionTaskRequest {
        let downloadTaskRequest = NSURLSessionTaskRequest(client: client, url: downloadURL)
        Promise<NSURL> { fulfill, reject in
            downloadTaskRequest.downloadTaskWithURL(file) { (url: NSURL?, response, error) in
                if let response = response where response.isOK || response.isNotModified, let url = url {
                    if let pathURL = file.pathURL where response.isNotModified {
                        fulfill(pathURL)
                    } else if cacheEnabled {
                        let fileManager = NSFileManager()
                        if let fileId = file.fileId,
                            let baseFolder = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true).first
                        {
                            do {
                                var baseFolderURL = NSURL(fileURLWithPath: baseFolder)
                                baseFolderURL = baseFolderURL.URLByAppendingPathComponent(self.client.appKey!).URLByAppendingPathComponent("files")
                                if !fileManager.fileExistsAtPath(baseFolderURL.path!) {
                                    try fileManager.createDirectoryAtURL(baseFolderURL, withIntermediateDirectories: true, attributes: nil)
                                }
                                let toURL = baseFolderURL.URLByAppendingPathComponent(fileId)
                                if let path = toURL.path where fileManager.fileExistsAtPath(path) {
                                    do {
                                        try fileManager.removeItemAtPath(path)
                                    }
                                }
                                try fileManager.moveItemAtURL(url, toURL: toURL)
                                
                                if let cache = self.cache {
                                    cache.save(file) {
                                        file.path = (toURL.path! as NSString).stringByAbbreviatingWithTildeInPath
                                        file.etag = response.etag
                                    }
                                }
                                
                                fulfill(toURL)
                            } catch let error {
                                reject(error)
                            }
                        } else {
                            reject(Error.InvalidResponse)
                        }
                    } else {
                        fulfill(url)
                    }
                } else if let error = error {
                    reject(error)
                } else {
                    reject(Error.InvalidResponse)
                }
            }
        }.then { url in
            completionHandler?(file, url, nil)
        }.error { error in
            completionHandler?(file, nil, error)
        }
        return downloadTaskRequest
    }
    
    private func downloadFile(file: File, downloadURL: NSURL, completionHandler: FileDataCompletionHandler? = nil) -> NSURLSessionTaskRequest {
        let downloadTaskRequest = NSURLSessionTaskRequest(client: client, url: downloadURL)
        Promise<NSData> { fulfill, reject in
            downloadTaskRequest.downloadTaskWithURL(file) { (data: NSData?, response, error) -> Void in
                if let response = response where response.isOK, let data = data {
                    fulfill(data)
                } else if let error = error {
                    reject(error)
                } else {
                    reject(Error.InvalidResponse)
                }
            }
        }.then { data in
            completionHandler?(file, data, nil)
        }.error { error in
            completionHandler?(file, nil, error)
        }
        return downloadTaskRequest
    }
    
    public func cachedFile(fileId: String) -> File? {
        if let cache = cache {
            return cache.get(fileId)
        }
        return nil
    }
    
    public func cachedFile(inout file: File) {
        guard let fileId = file.fileId else {
            fatalError("File.fileId is required")
        }
        
        if let cachedFile = cachedFile(fileId) {
            file = cachedFile
        }
    }
    
    /// Downloads a file using the `downloadURL` of the `File` instance.
    public func download(file: File, cacheEnabled: Bool = true, ttl: TTL? = nil, completionHandler: FilePathCompletionHandler? = nil) -> Request {
        var file = file
        return download(&file, cacheEnabled: cacheEnabled, ttl: ttl, completionHandler: completionHandler)
    }
    
    private func requiresFileId(inout file: File) {
        guard let _ = file.fileId else {
            fatalError("File.fileId is required")
        }
    }
    
    /// Downloads a file using the `downloadURL` of the `File` instance.
    public func download(inout file: File, cacheEnabled: Bool = true, ttl: TTL? = nil, completionHandler: FilePathCompletionHandler? = nil) -> Request {
        requiresFileId(&file)
        
        if let fileId = file.fileId, let cachedFile = cachedFile(fileId) {
            file = cachedFile
            dispatch_async(dispatch_get_main_queue()) {
                completionHandler?(file, file.pathURL, nil)
            }
        }
        
        if let downloadURL = file.downloadURL, let expiresAt = file.expiresAt where expiresAt.timeIntervalSinceNow > 0 {
            return downloadFile(file, cacheEnabled: cacheEnabled, downloadURL: downloadURL, completionHandler: completionHandler)
        } else {
            let fileMetadata = getFileMetadata(file, ttl: ttl)
            fileMetadata.1.then { file in
                return Promise {
                    if let downloadURL = file.downloadURL, let expiresAt = file.expiresAt where expiresAt.timeIntervalSinceNow > 0 {
                        self.downloadFile(file, cacheEnabled: cacheEnabled, downloadURL: downloadURL, completionHandler: completionHandler)
                    } else {
                        completionHandler?(file, nil, Error.InvalidResponse)
                    }
                }
            }.error { error in
                completionHandler?(file, nil, error)
            }
            return fileMetadata.0
        }
    }
    
    /// Downloads a file using the `downloadURL` of the `File` instance.
    public func download(file: File, ttl: TTL? = nil, completionHandler: FileDataCompletionHandler? = nil) -> Request {
        var file = file
        return download(&file, ttl: ttl, completionHandler: completionHandler)
    }
    
    /// Downloads a file using the `downloadURL` of the `File` instance.
    public func download(inout file: File, ttl: TTL? = nil, completionHandler: FileDataCompletionHandler? = nil) -> Request {
        requiresFileId(&file)
        
        if let fileId = file.fileId, let cachedFile = cachedFile(fileId), let path = file.path, let data = NSData(contentsOfFile: path) {
            file = cachedFile
            dispatch_async(dispatch_get_main_queue()) {
                completionHandler?(file, data, nil)
            }
        }
        
        if let downloadURL = file.downloadURL, let expiresAt = file.expiresAt where expiresAt.timeIntervalSinceNow > 0 {
            return downloadFile(file, downloadURL: downloadURL, completionHandler: completionHandler)
        } else {
            let fileMetadata = getFileMetadata(file, ttl: ttl)
            fileMetadata.1.then { file in
                return Promise {
                    if let downloadURL = file.downloadURL, let expiresAt = file.expiresAt where expiresAt.timeIntervalSinceNow > 0 {
                        self.downloadFile(file, downloadURL: downloadURL, completionHandler: completionHandler)
                    } else {
                        completionHandler?(file, nil, Error.InvalidResponse)
                    }
                }
            }.error { error in
                completionHandler?(file, nil, error)
            }
            return fileMetadata.0
        }
    }
    
    /// Deletes a file instance in the backend.
    public func remove(file: File, completionHandler: UIntCompletionHandler? = nil) -> Request {
        let request = client.networkRequestFactory.buildBlobDeleteFile(file)
        Promise<UInt> { fulfill, reject in
            request.execute({ (data, response, error) -> Void in
                if let response = response where response.isOK,
                    let json = self.client.responseParser.parse(data),
                    let count = json["count"] as? UInt
                {
                    if let cache = self.cache {
                        cache.remove(file)
                    }
                    
                    fulfill(count)
                } else if let error = error {
                    reject(error)
                } else {
                    reject(Error.InvalidResponse)
                }
            })
        }.then { count in
            completionHandler?(count, nil)
        }.error { error in
            completionHandler?(nil, error)
        }
        return request
    }
    
    /// Gets a list of files that matches with the query passed by parameter.
    public func find(query: Query = Query(), ttl: TTL? = nil, completionHandler: FileArrayCompletionHandler? = nil) -> Request {
        let request = client.networkRequestFactory.buildBlobQueryFile(query, ttl: ttl)
        Promise<[File]> { fulfill, reject in
            request.execute({ (data, response, error) -> Void in
                if let response = response where response.isOK,
                    let jsonArray = self.client.responseParser.parseArray(data)
                {
                    var files: [File] = []
                    for json in jsonArray {
                        let file = File()
                        self.fillFile(file, json: json)
                        files.append(file)
                    }
                    fulfill(files)
                } else if let error = error {
                    reject(error)
                } else {
                    reject(Error.InvalidResponse)
                }
            })
        }.then { files in
            completionHandler?(files, nil)
        }.error { error in
            completionHandler?(nil, error)
        }
        return request
    }
    
    /**
     Clear cached files from local storage.
     */
    public func clearCache() {
        client.cacheManager.clearAll()
    }
    
}
