//
//  AppleScriptRunner.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import AppKit
import Foundation

struct AppleScriptResult: Sendable {
    fileprivate enum Value: Sendable {
        case boolean(Bool)
        case string(String)
        case data(Data)
        case missing
    }

    fileprivate let values: [Value]

    func boolean(at index: Int) -> Bool? {
        guard values.indices.contains(index - 1), case .boolean(let value) = values[index - 1] else { return nil }
        return value
    }

    func string(at index: Int) -> String? {
        guard values.indices.contains(index - 1), case .string(let value) = values[index - 1] else { return nil }
        return value
    }

    func data(at index: Int) -> Data? {
        guard values.indices.contains(index - 1), case .data(let value) = values[index - 1] else { return nil }
        return value
    }
}

enum AppleScriptRunner {
    @MainActor
    static func run(_ script: String) async -> AppleScriptResult? {
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        guard let descriptor = appleScript?.executeAndReturnError(&error) else { return nil }
        return decodedResult(from: descriptor)
    }

    private static func decodedResult(from descriptor: NSAppleEventDescriptor) -> AppleScriptResult {
        guard descriptor.descriptorType == typeAEList else {
            return AppleScriptResult(values: [])
        }
        guard descriptor.numberOfItems > 0 else {
            return AppleScriptResult(values: [])
        }
        let values = (1...descriptor.numberOfItems).map { index -> AppleScriptResult.Value in
            guard let item = descriptor.atIndex(index) else { return .missing }
            switch item.descriptorType {
            case typeBoolean, typeTrue, typeFalse:
                return .boolean(item.booleanValue)
            case typeNull:
                return .missing
            default:
                if let string = item.stringValue {
                    return .string(string)
                }
                return .data(item.data)
            }
        }
        return AppleScriptResult(values: values)
    }
}
