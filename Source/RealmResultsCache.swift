//
//  RealmResultsCache.swift
//  redbooth-ios-sdk
//
//  Created by Isaac Roldan on 4/8/15.
//  Copyright © 2015 Redbooth Inc. All rights reserved.
//

import Foundation
import RealmSwift


protocol RealmResultsCacheDelegate: class {
    func didInsertSection<T: Object>(section: Section<T>, index: Int)
    func didDeleteSection<T: Object>(section: Section<T>, index: Int)
    func didInsert<T: Object>(object: T, indexPath: NSIndexPath)
    func didUpdate<T: Object>(object: T, oldIndexPath: NSIndexPath, newIndexPath: NSIndexPath, changeType: RealmResultsChangeType)
    func didDelete<T: Object>(object: T, indexPath: NSIndexPath)
}

class RealmResultsCache<T: Object> {
    var request: RealmRequest<T>
    var sectionKeyPath: String? = ""
    var sections: [Section<T>] = []
    var temporarySections: [Section<T>] = []
    let defaultKeyPathValue = "default"
    weak var delegate: RealmResultsCacheDelegate?
    
    init(request: RealmRequest<T>, sectionKeyPath: String?) {
        self.request = request
        self.sectionKeyPath = sectionKeyPath
    }
    
    func populateSections(objects: [T]) {
        for object in objects {
            let section = getOrCreateSection(object)
            section.insertSorted(object)
        }
    }
    
    func reset(objects: [T]) {
        sections.removeAll()
        populateSections(objects)
    }
    
    private func getOrCreateSection(object: T) -> Section<T> {
        let key = keyPathForObject(object)
        var section = sectionForKeyPath(key)
        if section == nil {
            section = createNewSection(key)
        }
        return section!
    }
    
    
    private func indexForSectionKeyPath(keypath: String) -> Int {
        let section = createNewSection(keypath)
        let index = indexForSection(section)!
        sections.removeAtIndex(index)
        return index
    }
    
    private func indexForSection(section: Section<T>) -> Int? {
        return sections.indexOf(section)
    }
    
    private func sectionForKeyPath(keyPath: String, create: Bool = true) -> Section<T>? {
        let section = sections.filter{$0.keyPath == keyPath}
        if let s = section.first {
            return s
        }
        return nil
    }
    
    private func sortSections() {
        sections.sortInPlace { $0.keyPath.localizedCaseInsensitiveCompare($1.keyPath) == NSComparisonResult.OrderedAscending }
    }
    
    private func toNSSortDescriptor(sort: SortDescriptor) -> NSSortDescriptor {
        return NSSortDescriptor(key: sort.property, ascending: sort.ascending)
    }
    
    private func createNewSection(keyPath: String, notifyDelegate: Bool = true) -> Section<T> {
        let newSection = Section<T>(keyPath: keyPath, sortDescriptors: request.sortDescriptors.map(toNSSortDescriptor))
        sections.append(newSection)
        sortSections()
        let index = indexForSection(newSection)!
        if notifyDelegate {
            delegate?.didInsertSection(newSection, index: index)
        }
        return newSection
    }
    
    private func keyPathForObject(object: T) -> String {
        var keyPathValue = defaultKeyPathValue
        if let keyPath = sectionKeyPath {
            //TODO: if keyPath.isEmpty { return }
            if NSThread.currentThread().isMainThread {
                keyPathValue = String(object.valueForKeyPath(keyPath)!)
            }
            else {
                dispatch_sync(dispatch_get_main_queue()) {
                    keyPathValue = String(object.valueForKeyPath(keyPath)!)
                }
            }
        }
        return keyPathValue
    }
    
    private func sectionForRealmChange(object: RealmChange) -> Section<T>? {
        for section in sections {
            if let _ = section.objectForPrimaryKey(object.primaryKey) {
                return section
            }
        }
        return nil
    }
    
    private func sectionForOutdateObject(object: T) -> Section<T>? {
        let primaryKey = T.primaryKey()!
        let primaryKeyValue = (object as Object).valueForKey(primaryKey)!
        for section in sections {
            for sectionObject in section.objects {
                let value = sectionObject.valueForKey(primaryKey)!
                if value.isEqual(primaryKeyValue) {
                    return section
                }
            }
        }
        let key = keyPathForObject(object)
        return sectionForKeyPath(key)
    }
    
    func insert(objects: [T]) {
        let mirrorsArray = sortedMirrors(objects)
        for object in mirrorsArray {
            let section = getOrCreateSection(object) //Calls the delegate when there is an insertion
            let rowIndex = section.insertSorted(object)
            let sectionIndex = indexForSection(section)!
            let indexPath = NSIndexPath(forRow: rowIndex, inSection: sectionIndex)
            delegate?.didInsert(object, indexPath: indexPath)
        }
    }
    
    func sortedMirrors(mirrors: [T]) -> [T] {
        let mutArray = NSMutableArray(array: mirrors)
        let sorts = request.sortDescriptors.map(toNSSortDescriptor)
        mutArray.sortUsingDescriptors(sorts)
        return mutArray as AnyObject as! [T]
    }
    
    func delete(objects: [T]) {
        
        var outdated: [T] = []
        for object in objects {
            guard let section = sectionForOutdateObject(object) else { return }
            let index = section.indexForOutdatedObject(object)
            outdated.append(section.objects.objectAtIndex(index) as! T)
        }
        
        let mirrorsArray = sortedMirrors(outdated).reverse() as [T]
        
        for object in mirrorsArray {
            guard let section = sectionForOutdateObject(object) else { return }
            let index = section.deleteOutdatedObject(object)
            let indexPath = NSIndexPath(forRow: index, inSection: indexForSection(section)!)
            delegate?.didDelete(object, indexPath: indexPath)
            if section.objects.count == 0 {
                sections.removeAtIndex(indexPath.section)
                delegate?.didDeleteSection(section, index: indexPath.section)
            }
        }
    }
    
    func updateType(object: T) -> RealmCacheUpdateType {
        let oldSection = sectionForOutdateObject(object)!
        let oldIndexRow = oldSection.indexForOutdatedObject(object)

        let newKeyPathValue = keyPathForObject(object)
        let newSection = sectionForKeyPath(newKeyPathValue)
        
        
        let indexOutdated = oldSection.indexForOutdatedObject(object)
        let outdatedCopy = oldSection.objects.objectAtIndex(indexOutdated) as! T
        
        oldSection.deleteOutdatedObject(object)
        let newIndexRow = newSection?.insertSorted(object)
        newSection?.delete(object)
        oldSection.insertSorted(outdatedCopy)
        
        if oldSection == newSection && oldIndexRow == newIndexRow  {
            return .Update
        }
        return .Move
    }
    
    func update(objects: [T]) {
        for object in objects {
            let oldSectionOptional = sectionForOutdateObject(object)
            
            guard let oldSection = oldSectionOptional else {
                insert([object])
                return
            }
            
            let oldSectionIndex = indexForSection(oldSection)!
            let oldIndexRow = oldSection.indexForOutdatedObject(object)
            let oldIndexPath = NSIndexPath(forRow: oldIndexRow, inSection: oldSectionIndex)

            oldSection.deleteOutdatedObject(object)
            let newIndexRow = oldSection.insertSorted(object)
            let newIndexPath = NSIndexPath(forRow: newIndexRow, inSection: oldSectionIndex)
            delegate?.didUpdate(object, oldIndexPath: oldIndexPath, newIndexPath: newIndexPath, changeType: .Update)
        }
    }
}

enum RealmCacheUpdateType: String {
    case Move
    case Update
}