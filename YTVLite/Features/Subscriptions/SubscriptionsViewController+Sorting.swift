import Foundation

extension SubscriptionsViewController {
    func sortDate(for video: Video) -> Date {
        if let cached = sortDatesByVideoId[video.id] {
            return cached
        }
        let date = video.publishedAt.flatMap {
            VideoFormatters.approximateDate(fromRelative: $0)
        } ?? .distantPast
        sortDatesByVideoId[video.id] = date
        return date
    }

    func mergeSortedVideos(
        _ lhs: [Video],
        _ rhs: [Video]
    ) -> [Video] {
        guard !lhs.isEmpty else {
            return rhs
        }
        guard !rhs.isEmpty else {
            return lhs
        }

        var merged: [Video] = []
        merged.reserveCapacity(lhs.count + rhs.count)
        var lhsIndex = 0
        var rhsIndex = 0

        while lhsIndex < lhs.count, rhsIndex < rhs.count {
            let lhsVideo = lhs[lhsIndex]
            let rhsVideo = rhs[rhsIndex]
            if sortDate(for: lhsVideo) >= sortDate(for: rhsVideo) {
                merged.append(lhsVideo)
                lhsIndex += 1
            } else {
                merged.append(rhsVideo)
                rhsIndex += 1
            }
        }

        if lhsIndex < lhs.count {
            merged.append(contentsOf: lhs[lhsIndex...])
        }
        if rhsIndex < rhs.count {
            merged.append(contentsOf: rhs[rhsIndex...])
        }
        return merged
    }
}
