import UIKit

final class VideoSeekBar: UIControl {
    var onScrubStart: (() -> Void)?
    var onScrubEnd: ((Double) -> Void)?
    var onScrubChanged: ((Double) -> Void)?

    private(set) var isScrubbing = false

    private let trackView    = UIView()
    private let bufferView   = UIView()
    private let segmentsView = UIView()
    private let progressView = UIView()
    private let thumbView    = UIView()

    private var progress: Double = 0
    private var buffer: Double   = 0
    private var segments: [SeekBarSegment] = []
    private var bufferWidthConstraint: NSLayoutConstraint?
    private var progressWidthConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePan(_:))
        )
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleTrackTap(_:))
        )
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let trackWidth = bounds.width
        let barY = (bounds.height - 4) / 2
        bufferView.frame = CGRect(
            x: 0,
            y: barY,
            width: trackWidth * CGFloat(buffer),
            height: 4
        )
        progressView.frame = CGRect(
            x: 0,
            y: barY,
            width: trackWidth * CGFloat(progress),
            height: 4
        )
        thumbView.center = CGPoint(
            x: trackWidth * CGFloat(progress),
            y: bounds.height / 2
        )
        layoutSegmentViews()
    }

    func setProgress(_ value: Double) {
        progress = max(0, min(1, value))
        setNeedsLayout()
    }

    func setBuffer(_ value: Double) {
        buffer = max(0, min(1, value))
        setNeedsLayout()
    }

    /// Sets the SponsorBlock segment markers in 0-1 range.
    func setSegments(_ newSegments: [SeekBarSegment]) {
        segments = newSegments
        setNeedsLayout()
    }

    @objc
    private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let px = gesture.location(in: self).x
        let pct = max(0, min(1, Double(px / bounds.width)))

        switch gesture.state {
        case .began:
            isScrubbing = true
            thumbView.isHidden = false
            UIView.animate(withDuration: 0.15) {
                self.thumbView.transform = CGAffineTransform(
                    scaleX: 1.3, y: 1.3
                )
            }
            onScrubStart?()
        case .changed:
            progress = pct
            setNeedsLayout()
            onScrubChanged?(pct)
        case .ended, .cancelled:
            UIView.animate(withDuration: 0.15) {
                self.thumbView.transform = .identity
            }
            thumbView.isHidden = true
            isScrubbing = false
            onScrubEnd?(pct)
        default:
            break
        }
    }

    @objc
    private func handleTrackTap(
        _ gesture: UITapGestureRecognizer
    ) {
        let px = gesture.location(in: self).x
        let pct = max(0, min(1, Double(px / bounds.width)))
        progress = pct
        setNeedsLayout()
        onScrubEnd?(pct)
    }

    private func setupViews() {
        configureTrackViews()
        addTrackSubviews()
        activateTrackConstraints()
    }

    private func configureTrackViews() {
        trackView.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        trackView.layer.cornerRadius = 2
        trackView.clipsToBounds = true
        trackView.translatesAutoresizingMaskIntoConstraints = false

        bufferView.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        bufferView.layer.cornerRadius = 2
        bufferView.translatesAutoresizingMaskIntoConstraints = false

        segmentsView.backgroundColor = .clear
        segmentsView.translatesAutoresizingMaskIntoConstraints = false
        segmentsView.isUserInteractionEnabled = false

        progressView.backgroundColor = .white
        progressView.layer.cornerRadius = 2
        progressView.translatesAutoresizingMaskIntoConstraints = false

        thumbView.backgroundColor = .white
        thumbView.layer.cornerRadius = 6
        thumbView.frame = CGRect(x: 0, y: 0, width: 12, height: 12)
        thumbView.isHidden = true
    }

    private func addTrackSubviews() {
        addSubview(trackView)
        addSubview(bufferView)
        addSubview(segmentsView)
        addSubview(progressView)
        addSubview(thumbView)
    }

    private func activateTrackConstraints() {
        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trackView.heightAnchor.constraint(equalToConstant: 4),

            bufferView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bufferView.centerYAnchor.constraint(equalTo: centerYAnchor),
            bufferView.heightAnchor.constraint(equalToConstant: 4),

            segmentsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            segmentsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            segmentsView.centerYAnchor.constraint(equalTo: centerYAnchor),
            segmentsView.heightAnchor.constraint(equalToConstant: 4),

            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    private func layoutSegmentViews() {
        segmentsView.subviews.forEach { $0.removeFromSuperview() }
        let trackWidth = segmentsView.bounds.width
        guard trackWidth > 0 else {
            return
        }
        for seg in segments {
            let segX = CGFloat(seg.start) * trackWidth
            let segW = max(
                2,
                CGFloat(seg.end - seg.start) * trackWidth
            )
            let bar = UIView(
                frame: CGRect(
                    x: segX,
                    y: 0,
                    width: segW,
                    height: 4
                )
            )
            bar.backgroundColor = seg.color
            segmentsView.addSubview(bar)
        }
    }
}

struct SeekBarSegment {
    let start: Double
    let end: Double
    let color: UIColor
}
