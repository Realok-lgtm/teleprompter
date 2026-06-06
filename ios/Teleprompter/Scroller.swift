import SwiftUI
import QuartzCore

/// Drives the teleprompter auto-scroll with a CADisplayLink for smooth motion.
final class Scroller: ObservableObject {
    @Published var offset: CGFloat = 0
    @Published var playing = false

    /// 1...20 from the speed slider.
    var speed: CGFloat = 5
    /// Maximum scrollable distance (set from the measured text height).
    var maxOffset: CGFloat = 0

    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0

    func toggle() { playing ? pause() : play() }

    func play() {
        guard !playing, maxOffset > 0 else { return }
        playing = true
        lastTime = 0
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func pause() {
        playing = false
        link?.invalidate()
        link = nil
    }

    func restart() {
        pause()
        offset = 0
    }

    @objc private func step(_ link: CADisplayLink) {
        if lastTime == 0 { lastTime = link.timestamp; return }
        let dt = link.timestamp - lastTime
        lastTime = link.timestamp
        offset += speed * 18 * CGFloat(dt)   // speed 1...20 -> px/sec
        if offset >= maxOffset {
            offset = maxOffset
            pause()
        }
    }
}
