import CoreGraphics
import Testing
@testable import ScreenInkCore

@Suite struct ExportRegionTests {
    let screen = CGRect(x: 0, y: 0, width: 300, height: 200)

    @Test func dragInAnyDirectionGivesTheSameRect() {
        let expected = CGRect(x: 40, y: 60, width: 60, height: 40)
        #expect(ExportRegion.rect(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 100, y: 100), in: screen) == expected)
        #expect(ExportRegion.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 40, y: 60), in: screen) == expected)
    }

    @Test func dragPastTheEdgeIsClippedToTheScreen() {
        let rect = ExportRegion.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: -50, y: 500), in: screen)
        #expect(rect == CGRect(x: 0, y: 10, width: 10, height: 190))
    }

    @Test func clickOrThinDragIsNil() {
        #expect(ExportRegion.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10), in: screen) == nil)
        #expect(ExportRegion.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 80), in: screen) == nil)
    }

    @Test func pixelRectScalesAndRoundsOutward() {
        let rect = CGRect(x: 10.25, y: 5.5, width: 20, height: 10)
        let pixels = ExportRegion.pixelRect(for: rect, scale: 2, imageSize: CGSize(width: 600, height: 400))
        #expect(pixels == CGRect(x: 20, y: 11, width: 41, height: 20))
    }

    @Test func pixelRectStaysInsideTheImage() {
        let rect = CGRect(x: 290, y: 190, width: 20, height: 20)
        let pixels = ExportRegion.pixelRect(for: rect, scale: 1, imageSize: CGSize(width: 300, height: 200))
        #expect(pixels == CGRect(x: 290, y: 190, width: 10, height: 10))
        #expect(ExportRegion.pixelRect(for: CGRect(x: 400, y: 0, width: 10, height: 10), scale: 1,
            imageSize: CGSize(width: 300, height: 200)) == nil)
    }
}
