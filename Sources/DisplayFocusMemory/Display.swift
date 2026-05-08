import AppKit
import CoreGraphics

struct PhysicalDisplay: Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let isBuiltin: Bool
}

enum DisplayResolver {
    static func displays() -> [PhysicalDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            let id = CGDirectDisplayID(number.uint32Value)
            return PhysicalDisplay(
                id: id,
                frame: CGDisplayBounds(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0
            )
        }
    }

    static func display(containing point: CGPoint) -> PhysicalDisplay? {
        displays().first { $0.frame.contains(point) }
    }

    static func displayWithLargestOverlap(for windowFrame: CGRect) -> PhysicalDisplay? {
        displays()
            .map { display in
                (display: display, area: display.frame.intersection(windowFrame).area)
            }
            .filter { $0.area > 0 }
            .max { $0.area < $1.area }?
            .display
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
