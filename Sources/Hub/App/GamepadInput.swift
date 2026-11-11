import GameController

/// Xbox / PlayStation kumandasını Hub gezinmesine bağlar.
/// D-pad / sol çubuk: gezin · A: seç · B: geri · X: widget kaldır
@MainActor
final class GamepadInput {
    private let emit: (InputAction) -> Void
    private var stickLatchX = false
    private var stickLatchY = false

    init(emit: @escaping (InputAction) -> Void) {
        self.emit = emit
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            let controller = note.object as? GCController
            MainActor.assumeIsolated { self?.attach(controller) }
        }
        GCController.controllers().forEach { attach($0) }
    }

    private func attach(_ controller: GCController?) {
        guard let pad = controller?.extendedGamepad else { return }

        func bind(_ button: GCControllerButtonInput, _ action: InputAction) {
            button.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated { self?.emit(action) }
            }
        }
        bind(pad.dpad.up, .up)
        bind(pad.dpad.down, .down)
        bind(pad.dpad.left, .left)
        bind(pad.dpad.right, .right)
        bind(pad.buttonA, .select)
        bind(pad.buttonB, .back)
        bind(pad.buttonX, .delete)
        bind(pad.leftShoulder, .moveLeft)
        bind(pad.rightShoulder, .moveRight)

        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.stick(x: x, y: y) }
        }
    }

    private func stick(x: Float, y: Float) {
        if abs(x) > 0.6, !stickLatchX {
            stickLatchX = true
            emit(x > 0 ? .right : .left)
        } else if abs(x) < 0.3 {
            stickLatchX = false
        }
        if abs(y) > 0.6, !stickLatchY {
            stickLatchY = true
            emit(y > 0 ? .up : .down)
        } else if abs(y) < 0.3 {
            stickLatchY = false
        }
    }
}
