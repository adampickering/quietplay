import SwiftUI
import UIKit

struct RemoteInputView: UIViewControllerRepresentable {
    let onSelect: () -> Void
    let onLeft: () -> Void
    let onRight: () -> Void
    let onPlayPause: () -> Void
    let onExit: () -> Void

    func makeUIViewController(context: Context) -> RemoteInputController {
        let vc = RemoteInputController()
        apply(to: vc)
        return vc
    }

    func updateUIViewController(_ vc: RemoteInputController, context: Context) {
        apply(to: vc)
    }

    private func apply(to vc: RemoteInputController) {
        vc.onSelect = onSelect
        vc.onLeft = onLeft
        vc.onRight = onRight
        vc.onPlayPause = onPlayPause
        vc.onExit = onExit
    }
}

final class RemoteInputController: UIViewController {
    var onSelect: (() -> Void)?
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onExit: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            switch press.type {
            case .select:
                onSelect?()
                handled = true
            case .leftArrow:
                onLeft?()
                handled = true
            case .rightArrow:
                onRight?()
                handled = true
            case .playPause:
                onPlayPause?()
                handled = true
            case .menu:
                onExit?()
                handled = true
            default:
                break
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }
}
