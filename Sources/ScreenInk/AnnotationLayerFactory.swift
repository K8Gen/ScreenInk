import AppKit
import ScreenInkCore

/// Builds the layer tree for one annotation: a container with one `CAShapeLayer` per
/// render part. Opacity and blending apply to the container as a group, so overlapping
/// parts (arrow shaft and head, stroke segments) don't darken each other.
enum AnnotationLayerFactory {
    static func makeLayer(for annotation: Annotation, bounds: CGRect, scale: CGFloat) -> CALayer {
        let container = CALayer()
        container.frame = bounds
        container.contentsScale = scale
        container.allowsGroupOpacity = true
        container.opacity = Float(annotation.style.opacity)
        container.compositingFilter = annotation.style.blend == .multiply ? "multiplyBlendMode" : nil
        for part in annotation.renderParts {
            let shape = CAShapeLayer()
            shape.frame = bounds
            shape.contentsScale = scale
            shape.path = part.path
            shape.fillRule = .nonZero
            shape.strokeColor = nil
            let color = part.fill == .style ? annotation.style.color : annotation.style.color.contrasting
            shape.fillColor = color.cgColor
            container.addSublayer(shape)
        }
        return container
    }
}
