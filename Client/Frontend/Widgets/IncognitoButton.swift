/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import SwiftUI

struct IncognitoButton: View {
    let isIncognito: Bool
    let action: () -> Void

    var body: some View {
        IncognitoButtonView(isIncognito: isIncognito, action: action)
            .tapTargetFrame()
    }
}

private enum UX {
    // The amount of pixels the toggle button will expand over the normal size. This results in the larger -> contract animation.
    static let ExpandDelta: CGFloat = 5
    static let ShowDuration: TimeInterval = 0.4
    static let HideDuration: TimeInterval = 0.2

    static let BackgroundSize = CGSize(width: 32, height: 32)
}

private let EllipsePointerStyleProvider: UIButton.PointerStyleProvider = { button, effect, style in
    UIPointerStyle(effect: effect, shape: .path(UIBezierPath(ovalIn: button.bounds)))
}

/// Wrapper for the `ToggleButton` UIKit control.
private struct IncognitoButtonView: UIViewRepresentable {
    let isIncognito: Bool
    let action: () -> Void

    init(isIncognito: Bool, action: @escaping () -> Void) {
        self.isIncognito = isIncognito
        self.action = action
    }

    class Coordinator {
        var onTap: () -> Void
        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        @objc func action() {
            onTap()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: action)
    }

    func makeUIView(context: Context) -> ToggleButton {
        let button = ToggleButton(frame: .init(origin: .zero, size: .init(width: 40, height: 40)))
        button.addTarget(
            context.coordinator, action: #selector(Coordinator.action), for: .primaryActionTriggered
        )
        return button
    }

    func updateUIView(_ button: ToggleButton, context: Context) {
        context.coordinator.onTap = action

        button.setSelected(isIncognito)
    }
}

private class ToggleButton: UIButton {
    var selectedBackgroundColor = UIColor.label

    func setSelected(_ selected: Bool, animated: Bool = true) {
        tintColor = selected ? .label.swappedForStyle : .label
        imageView?.tintColor = tintColor
        accessibilityValue =
            selected ? .TabTrayToggleAccessibilityValueOn : .TabTrayToggleAccessibilityValueOff

        guard isSelected != selected else {
            return
        }

        self.isSelected = selected
        pointerStyleProvider =
            selected
            ? { button, style, effect in
                // produce a lift effect clipped to the circular background
                let path = UIBezierPath(
                    ovalIn: self.backgroundView.frame.insetBy(
                        dx: UX.ExpandDelta + 1, dy: UX.ExpandDelta + 1))
                let params = UIPreviewParameters()
                params.visiblePath = path
                return UIPointerStyle(
                    effect: .lift(UITargetedPreview(view: style.preview.view, parameters: params)),
                    shape: .path(path))
            } : EllipsePointerStyleProvider

        if animated {
            animateSelection(selected)
        }
    }

    fileprivate func updateMaskPathForSelectedState(_ selected: Bool) {
        let path = CGMutablePath()
        if selected {
            var rect = CGRect(size: UX.BackgroundSize)
            rect.center = maskShapeLayer.position
            path.addEllipse(in: rect)
        } else {
            path.addEllipse(in: CGRect(origin: maskShapeLayer.position, size: .zero))
        }
        self.maskShapeLayer.path = path
    }

    fileprivate func animateSelection(_ selected: Bool) {
        var endFrame = CGRect(size: UX.BackgroundSize)
        endFrame.center = maskShapeLayer.position

        if selected {
            let animation = CAKeyframeAnimation(keyPath: "path")

            let startPath = CGMutablePath()
            startPath.addEllipse(in: CGRect(origin: maskShapeLayer.position, size: .zero))

            let largerPath = CGMutablePath()
            let largerBounds = endFrame.insetBy(dx: -UX.ExpandDelta, dy: -UX.ExpandDelta)
            largerPath.addEllipse(in: largerBounds)

            let endPath = CGMutablePath()
            endPath.addEllipse(in: endFrame)

            animation.timingFunction = CAMediaTimingFunction(
                name: CAMediaTimingFunctionName.easeOut)
            animation.values = [
                startPath,
                largerPath,
                endPath,
            ]
            animation.duration = UX.ShowDuration
            self.maskShapeLayer.path = endPath
            self.maskShapeLayer.add(animation, forKey: "grow")
        } else {
            let animation = CABasicAnimation(keyPath: "path")
            animation.duration = UX.HideDuration
            animation.fillMode = CAMediaTimingFillMode.forwards

            let fromPath = CGMutablePath()
            fromPath.addEllipse(in: endFrame)
            animation.fromValue = fromPath
            animation.timingFunction = CAMediaTimingFunction(
                name: CAMediaTimingFunctionName.easeInEaseOut)

            let toPath = CGMutablePath()
            toPath.addEllipse(in: CGRect(origin: self.maskShapeLayer.bounds.center, size: .zero))

            self.maskShapeLayer.path = toPath
            self.maskShapeLayer.add(animation, forKey: "shrink")
        }
    }

    lazy fileprivate var backgroundView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.layer.addSublayer(self.backgroundLayer)
        return view
    }()

    lazy fileprivate var maskShapeLayer: CAShapeLayer = {
        let circle = CAShapeLayer()
        return circle
    }()

    lazy fileprivate var backgroundLayer: CALayer = {
        let backgroundLayer = CALayer()
        backgroundLayer.mask = self.maskShapeLayer
        return backgroundLayer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        insertSubview(backgroundView, belowSubview: imageView!)
        pointerStyleProvider = EllipsePointerStyleProvider

        accessibilityLabel = .TabTrayToggleAccessibilityLabel
        accessibilityHint = .TabTrayToggleAccessibilityHint
        let maskImage = UIImage(named: "incognito")?.withRenderingMode(.alwaysTemplate)
        setImage(maskImage, for: [])
        isPointerInteractionEnabled = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let zeroFrame = CGRect(size: frame.size)
        backgroundView.frame = zeroFrame

        // Set the background color here to respect light/dark mode automatically.
        backgroundLayer.backgroundColor = selectedBackgroundColor.cgColor

        // Make the gradient larger than normal to allow the mask transition to show when it blows up
        // a little larger than the resting size
        backgroundLayer.bounds = backgroundView.frame.insetBy(
            dx: -UX.ExpandDelta, dy: -UX.ExpandDelta)
        maskShapeLayer.bounds = backgroundView.frame
        backgroundLayer.position = CGPoint(x: zeroFrame.midX, y: zeroFrame.midY)
        maskShapeLayer.position = CGPoint(x: zeroFrame.midX, y: zeroFrame.midY)

        updateMaskPathForSelectedState(isSelected)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
