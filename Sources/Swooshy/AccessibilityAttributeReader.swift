import ApplicationServices
import CoreGraphics
import Foundation

enum AXAttributeReader {
    static func element(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func elements(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let children = value as? [AnyObject] else {
            return []
        }

        return children.compactMap { child in
            guard CFGetTypeID(child) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeDowncast(child, to: AXUIElement.self)
        }
    }

    static func string(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    static func point(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let axValue = value else { return nil }

        guard CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        let pointValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(pointValue) == .cgPoint else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(pointValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let axValue = value else { return nil }

        guard CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        let sizeValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(sizeValue) == .cgSize else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return size
    }

    static func bool(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let value else { return nil }

        if let boolValue = value as? Bool {
            return boolValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }

        return nil
    }
}
