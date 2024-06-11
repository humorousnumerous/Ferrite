//
//  SourceRequest+CoreDataProperties.swift
//  Ferrite
//
//  Created by Brian Dashore on 6/10/24.
//
//

import CoreData
import Foundation

public extension SourceRequest {
    @nonobjc class func fetchRequest() -> NSFetchRequest<SourceRequest> {
        NSFetchRequest<SourceRequest>(entityName: "SourceRequest")
    }

    @NSManaged var method: String?
    @NSManaged var headers: [String: String]?
    @NSManaged var body: String?
    @NSManaged var parentHtmlParser: SourceHtmlParser?
    @NSManaged var parentRssParser: SourceRssParser?
    @NSManaged var parentJsonParser: SourceJsonParser?
}

extension SourceRequest: Identifiable {}
