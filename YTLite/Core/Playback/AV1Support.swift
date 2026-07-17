import VideoToolbox

/// Hardware AV1 decode capability. YouTube serves 1440p+/4K only as VP9 or
/// AV1; AVPlayer can never decode VP9, and decodes AV1 solely in hardware
/// (A17 Pro+, HLS support since iOS 17.4). `av01` formats are admitted to
/// the DASH ladder only on devices that pass this check — elsewhere the
/// ladder stays avc1-only and tops out at 1080p.
enum AV1Support {
    static let isHardwareSupported: Bool = {
        guard #available(iOS 17.4, *) else {
            return false
        }
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    }()
}
