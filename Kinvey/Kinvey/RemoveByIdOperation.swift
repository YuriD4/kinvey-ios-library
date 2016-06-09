//
//  RemoveByIdOperation.swift
//  Kinvey
//
//  Created by Victor Barros on 2016-04-25.
//  Copyright © 2016 Kinvey. All rights reserved.
//

import Foundation

internal class RemoveByIdOperation<T: Persistable>: RemoveOperation<T> {
    
    let objectId: String
    
    override func buildRequest() -> HttpRequest {
        return client.networkRequestFactory.buildAppDataRemoveById(collectionName: T.kinveyCollectionName(), objectId: objectId)
    }
    
    internal init(objectId: String, writePolicy: WritePolicy, sync: Sync? = nil, cache: Cache? = nil, client: Client) {
        self.objectId = objectId
        let query = Query(format: "\(T.idKey) == %@", objectId)
        super.init(query: query, writePolicy: writePolicy, sync: sync, cache: cache, client: client)
    }
    
}
