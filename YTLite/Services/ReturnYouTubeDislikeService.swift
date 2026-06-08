import Foundation
import CommonCrypto

struct RYDVotes { let likes: Int; let dislikes: Int; let rating: Double }
private struct PuzzleSolution { let base64: String; let difficulty: Int; let solution: Data }

final class ReturnYouTubeDislikeService {
    static let shared = ReturnYouTubeDislikeService()
    static let attributionURL = AppURLs.RYD.web
    static var enabled: Bool {
        get {
            let key = UserDefaultsKeys.RYD.enabled
            let exists = UserDefaults.standard.object(forKey: key) != nil
            return exists ? UserDefaults.standard.bool(forKey: key) : true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.RYD.enabled)
            if newValue { shared.prepareIfNeeded() }
        }
    }
    private let baseURL = AppURLs.RYD.api
    private var userId: String {
        let key = UserDefaultsKeys.RYD.userId
        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let newId = String((0..<36).map { _ in chars[Int.random(in: 0..<chars.count)] })
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
    private var registrationConfirmed: Bool {
        get { UserDefaults.standard.bool(forKey: UserDefaultsKeys.RYD.registered) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.RYD.registered) }
    }
    private init() {}
}

extension ReturnYouTubeDislikeService {
    private static func decodeBase64(_ string: String) -> Data? {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 { normalized += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: normalized)
    }
    func prepareIfNeeded() {
        guard !registrationConfirmed else {
            return
        }
        let uid = userId
        register(userId: uid) { success in
            AppLog.ryd("pre-registration \(success ? "succeeded" : "failed")")
        }
    }
    func fetchVotes(
        videoId: String,
        completion: @escaping (Result<RYDVotes, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/votes?videoId=\(videoId)") else {
            completion(.failure(NSError(domain: "RYD", code: 0))); return
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                completion(.failure(error)); return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let likes = json["likes"] as? Int,
                  let dislikes = json["dislikes"] as? Int,
                  let rating = json["rating"] as? Double
            else {
                let info = [NSLocalizedDescriptionKey: "Parse error"]
                completion(.failure(NSError(domain: "RYD", code: 1, userInfo: info))); return
            }
            completion(.success(RYDVotes(likes: likes, dislikes: dislikes, rating: rating)))
        }
        task.resume()
    }
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
    private func buildJSONRequest(url: URL, body: [String: Any]) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(HTTPHeaderValue.contentTypeJSON, forHTTPHeaderField: HTTPHeader.contentType)
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }
    private func register(userId: String, completion: @escaping (Bool) -> Void) {
        AppLog.ryd("registering userId=\(userId.prefix(8))...")
        guard let url = URL(string: "\(baseURL)/puzzle/registration?userId=\(userId)") else {
            completion(false); return
        }
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            self?.handleRegistrationResponse(
                data: data, error: error, userId: userId, completion: completion
            )
        }
        task.resume()
    }
    private func handleRegistrationResponse(
        data: Data?,
        error: Error?,
        userId: String,
        completion: @escaping (Bool) -> Void
    ) {
        if let error {
            AppLog.ryd("reg GET error: \(error)"); completion(false); return
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challengeB64 = json["challenge"] as? String,
              let challengeData = Self.decodeBase64(challengeB64),
              let difficulty = json["difficulty"] as? Int
        else {
            let raw = String(data: data ?? Data(), encoding: .utf8) ?? "?"
            AppLog.ryd("reg GET parse failed: \(raw)"); completion(false); return
        }
        AppLog.ryd("reg puzzle difficulty=\(difficulty)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self,
                  let (solution, _) = self.solvePuzzle(
                      challenge: challengeData, difficulty: difficulty
                  )
            else {
                AppLog.ryd("reg puzzle solve failed"); completion(false); return
            }
            AppLog.ryd("reg puzzle solved, posting...")
            let puzzle = PuzzleSolution(
                base64: challengeB64, difficulty: difficulty, solution: solution
            )
            self.postRegistration(userId: userId, puzzle: puzzle, completion: completion)
        }
    }
    private func postRegistration(
        userId: String,
        puzzle: PuzzleSolution,
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/puzzle/registration?userId=\(userId)") else {
            completion(false); return
        }
        let body: [String: Any] = [
            "challenge": puzzle.base64, "difficulty": puzzle.difficulty,
            "solution": puzzle.solution.base64EncodedString()
        ]
        let req = buildJSONRequest(url: url, body: body)
        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "?"
            AppLog.ryd("reg POST status=\(status) response=\(raw)")
            if status == 200 {
                self?.registrationConfirmed = true
                completion(true)
            } else { completion(false) }
        }
        task.resume()
    }
    private func sendVoteRequest(
        userId: String,
        videoId: String,
        value: Int,
        retryCount: Int = 1
    ) {
        guard let url = URL(string: "\(baseURL)/interact/vote") else {
            return
        }
        let body: [String: Any] = ["userId": userId, "videoId": videoId, "value": value]
        let req = buildJSONRequest(url: url, body: body)
        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error {
                AppLog.ryd("vote step1 error: \(error)"); return
            }
            if code == 401 && retryCount > 0 {
                AppLog.ryd("vote got 401, re-registering...")
                self?.registrationConfirmed = false
                self?.register(userId: userId) { success in
                    if success {
                        self?.sendVoteRequest(
                            userId: userId, videoId: videoId, value: value, retryCount: 0
                        )
                    }
                }
                return
            }
            self?.solveVoteChallenge(
                data: data, statusCode: code, userId: userId, videoId: videoId
            )
        }
        task.resume()
    }
    private func solveVoteChallenge(
        data: Data?,
        statusCode: Int,
        userId: String,
        videoId: String
    ) {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challengeB64 = json["challenge"] as? String,
              let challengeData = Self.decodeBase64(challengeB64),
              let difficulty = json["difficulty"] as? Int
        else {
            let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "?"
            AppLog.ryd("vote step1 status=\(statusCode) response=\(raw)"); return
        }
        AppLog.ryd("vote puzzle difficulty=\(difficulty)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self,
                  let (solution, _) = self.solvePuzzle(
                      challenge: challengeData, difficulty: difficulty
                  )
            else {
                AppLog.ryd("vote puzzle solve failed"); return
            }
            AppLog.ryd("vote puzzle solved, confirming...")
            let puzzle = PuzzleSolution(
                base64: challengeB64, difficulty: difficulty, solution: solution
            )
            self.confirmVote(userId: userId, videoId: videoId, puzzle: puzzle)
        }
    }
    private func confirmVote(
        userId: String,
        videoId: String,
        puzzle: PuzzleSolution
    ) {
        guard let url = URL(string: "\(baseURL)/interact/confirmVote") else {
            return
        }
        let body: [String: Any] = [
            "userId": userId, "videoId": videoId, "challenge": puzzle.base64,
            "difficulty": puzzle.difficulty, "solution": puzzle.solution.base64EncodedString()
        ]
        let req = buildJSONRequest(url: url, body: body)
        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let raw = data.flatMap { String(data: $0.prefix(200), encoding: .utf8) } ?? "?"
            if let error {
                AppLog.ryd("confirmVote error: \(error)")
            } else {
                AppLog.ryd("confirmVote status=\(status) response=\(raw)")
            }
        }
        task.resume()
    }
    private func solvePuzzle(
        challenge: Data,
        difficulty: Int
    ) -> (solution: Data, buffer: Data)? {
        let maxCount = Int(pow(2.0, Double(difficulty))) * 3
        var buf = [UInt8](repeating: 0, count: 20)
        let challengeBytes = Array(challenge.prefix(16))
        for i in 0..<min(16, challengeBytes.count) { buf[4 + i] = challengeBytes[i] }
        for i in 0..<maxCount {
            buf[0] = UInt8(i & 0xFF)
            buf[1] = UInt8((i >> 8) & 0xFF)
            buf[2] = UInt8((i >> 16) & 0xFF)
            buf[3] = UInt8((i >> 24) & 0xFF)
            let bufData = Data(buf)
            if leadingZeroBits(in: sha512(bufData)) >= difficulty {
                return (Data(buf[0..<4]), bufData)
            }
        }
        return nil
    }
    private func sha512(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        _ = data.withUnsafeBytes {
            CC_SHA512($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    private func leadingZeroBits(in data: Data) -> Int {
        var count = 0
        for byte in data {
            if byte == 0 { count += 8; continue }
            var masked = byte
            while masked & 0x80 == 0 { count += 1; masked <<= 1 }
            break
        }
        return count
    }
}
