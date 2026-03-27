import Foundation
import CommonCrypto

struct RYDVotes {
    let likes: Int
    let dislikes: Int
    let rating: Double
}

final class ReturnYouTubeDislikeService {
    static let shared = ReturnYouTubeDislikeService()
    private init() {}

    private let baseURL = AppURLs.RYD.api
    static let attributionURL = AppURLs.RYD.web

    /// Whether dislike count fetching and vote reporting is enabled.
    static var enabled: Bool {
        get {
            let key = UserDefaultsKeys.RYD.enabled
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.RYD.enabled)
            if newValue { ReturnYouTubeDislikeService.shared.prepareIfNeeded() }
        }
    }

    /// Ensures user is registered with RYD. Safe to call multiple times.
    func prepareIfNeeded() {
        guard !registrationConfirmed else { return }
        let uid = userId
        register(userId: uid) { success in
            AppLog.ryd("pre-registration \(success ? "succeeded" : "failed")")
        }
    }

    // Persistent anonymous user ID — alphanumeric string (not UUID) matching RYD spec
    private var userId: String {
        let key = UserDefaultsKeys.RYD.userId
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let id = String((0..<36).map { _ in charset[Int.random(in: 0..<charset.count)] })
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    // Track whether registration completed
    private var registrationConfirmed: Bool {
        get { UserDefaults.standard.bool(forKey: UserDefaultsKeys.RYD.registered) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.RYD.registered) }
    }

    // MARK: - Fetch vote counts

    func fetchVotes(videoId: String, completion: @escaping (Result<RYDVotes, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/votes?videoId=\(videoId)") else {
            completion(.failure(NSError(domain: "RYD", code: 0))); return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let likes = json["likes"] as? Int,
                  let dislikes = json["dislikes"] as? Int,
                  let rating = json["rating"] as? Double
            else {
                completion(.failure(NSError(domain: "RYD", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Parse error"]))); return
            }
            completion(.success(RYDVotes(likes: likes, dislikes: dislikes, rating: rating)))
        }.resume()
    }

    // MARK: - Report vote (value: 1=like, -1=dislike, 0=neutral/remove)

    func reportVote(videoId: String, value: Int) {
        let uid = userId
        AppLog.ryd("reportVote videoId=\(videoId) value=\(value) userId=\(uid.prefix(8))...")

        if registrationConfirmed {
            sendVoteRequest(userId: uid, videoId: videoId, value: value)
        } else {
            register(userId: uid) { [weak self] success in
                if success {
                    self?.sendVoteRequest(userId: uid, videoId: videoId, value: value)
                } else {
                    AppLog.ryd("registration failed, skipping vote")
                }
            }
        }
    }

    // MARK: - Registration flow

    private func register(userId: String, completion: @escaping (Bool) -> Void) {
        AppLog.ryd("registering userId=\(userId.prefix(8))...")
        guard let url = URL(string: "\(baseURL)/puzzle/registration?userId=\(userId)") else {
            completion(false); return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            if let error = error { AppLog.ryd("reg GET error: \(error)"); completion(false); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let challengeB64 = json["challenge"] as? String,
                  let challengeData = Self.decodeBase64(challengeB64),
                  let difficulty = json["difficulty"] as? Int else {
                let raw = String(data: data ?? Data(), encoding: .utf8) ?? "?"
                AppLog.ryd("reg GET parse failed: \(raw)"); completion(false); return
            }
            AppLog.ryd("reg puzzle difficulty=\(difficulty)")
            DispatchQueue.global(qos: .userInitiated).async {
                guard let self = self,
                      let (solution, fullBuffer) = self.solvePuzzle(challenge: challengeData, difficulty: difficulty) else {
                    AppLog.ryd("reg puzzle solve failed"); completion(false); return
                }
                AppLog.ryd("reg puzzle solved, posting...")
                self.postRegistration(userId: userId,
                                      challengeB64: challengeB64,
                                      difficulty: difficulty,
                                      solution: solution,
                                      completion: completion)
            }
        }.resume()
    }

    private func postRegistration(userId: String, challengeB64: String,
                                   difficulty: Int, solution: Data,
                                   completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/puzzle/registration?userId=\(userId)") else {
            completion(false); return
        }
        let body: [String: Any] = [
            "challenge":  challengeB64,
            "difficulty": difficulty,
            "solution":   solution.base64EncodedString()
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "?"
            AppLog.ryd("reg POST status=\(status) response=\(raw)")
            if status == 200 {
                self?.registrationConfirmed = true
                completion(true)
            } else {
                completion(false)
            }
        }.resume()
    }

    // MARK: - Vote flow

    /// Step 1: POST /interact/vote — server responds with a puzzle challenge
    private func sendVoteRequest(userId: String, videoId: String, value: Int, retryCount: Int = 1) {
        guard let url = URL(string: "\(baseURL)/interact/vote") else { return }
        let body: [String: Any] = ["userId": userId, "videoId": videoId, "value": value]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error = error { AppLog.ryd("vote step1 error: \(error)"); return }
            if status == 401 && retryCount > 0 {
                // Re-register and retry once
                AppLog.ryd("vote got 401, re-registering...")
                self?.registrationConfirmed = false
                self?.register(userId: userId) { success in
                    if success { self?.sendVoteRequest(userId: userId, videoId: videoId, value: value, retryCount: 0) }
                }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let challengeB64 = json["challenge"] as? String,
                  let challengeData = Self.decodeBase64(challengeB64),
                  let difficulty = json["difficulty"] as? Int else {
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "?"
                AppLog.ryd("vote step1 status=\(status) response=\(raw)"); return
            }
            AppLog.ryd("vote puzzle difficulty=\(difficulty)")
            DispatchQueue.global(qos: .userInitiated).async {
                guard let self = self,
                      let (solution, _) = self.solvePuzzle(challenge: challengeData, difficulty: difficulty) else {
                    AppLog.ryd("vote puzzle solve failed"); return
                }
                AppLog.ryd("vote puzzle solved, confirming...")
                self.confirmVote(userId: userId, videoId: videoId,
                                 challengeB64: challengeB64, difficulty: difficulty, solution: solution)
            }
        }.resume()
    }

    /// Step 2: POST /interact/confirmVote with solved puzzle
    private func confirmVote(userId: String, videoId: String,
                              challengeB64: String, difficulty: Int, solution: Data) {
        guard let url = URL(string: "\(baseURL)/interact/confirmVote") else { return }
        let body: [String: Any] = [
            "userId":     userId,
            "videoId":    videoId,
            "challenge":  challengeB64,
            "difficulty": difficulty,
            "solution":   solution.base64EncodedString()
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let raw = data.flatMap { String(data: $0.prefix(200), encoding: .utf8) } ?? "?"
            if let error = error {
                AppLog.ryd("confirmVote error: \(error)")
            } else {
                AppLog.ryd("confirmVote status=\(status) response=\(raw)")
            }
        }.resume()
    }

    // MARK: - Proof-of-work
    //
    // Buffer layout (20 bytes): [uint32 counter LE][first 16 bytes of challenge]
    // Hash = SHA-512(buffer). Solution = first 4 bytes (the counter) as base64.
    // This matches the RYD browser extension implementation exactly.

    private func solvePuzzle(challenge: Data, difficulty: Int) -> (solution: Data, buffer: Data)? {
        let maxCount = Int(pow(2.0, Double(difficulty))) * 3

        // Pre-fill bytes 4..19 with first 16 bytes of challenge
        var buf = [UInt8](repeating: 0, count: 20)
        let challengeBytes = Array(challenge.prefix(16))
        for i in 0..<min(16, challengeBytes.count) {
            buf[4 + i] = challengeBytes[i]
        }

        for i in 0..<maxCount {
            // Write 32-bit counter into first 4 bytes (little-endian)
            buf[0] = UInt8(i & 0xFF)
            buf[1] = UInt8((i >> 8) & 0xFF)
            buf[2] = UInt8((i >> 16) & 0xFF)
            buf[3] = UInt8((i >> 24) & 0xFF)

            let bufData = Data(buf)
            let hash = sha512(bufData)
            if leadingZeroBits(in: hash) >= difficulty {
                let solution = Data(buf[0..<4])
                return (solution, bufData)
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func decodeBase64(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+")
                      .replacingOccurrences(of: "_", with: "/")
        let rem = s.count % 4
        if rem > 0 { s += String(repeating: "=", count: 4 - rem) }
        return Data(base64Encoded: s)
    }

    private func sha512(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_SHA512($0.baseAddress, CC_LONG(data.count), &hash) }
        return Data(hash)
    }

    private func leadingZeroBits(in data: Data) -> Int {
        var count = 0
        for byte in data {
            if byte == 0 { count += 8; continue }
            var b = byte
            while b & 0x80 == 0 { count += 1; b <<= 1 }
            break
        }
        return count
    }
}
