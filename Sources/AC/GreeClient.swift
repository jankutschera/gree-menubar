import CommonCrypto
import CryptoKit
import Foundation

struct GreeError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Local-LAN client for Gree+ units (UDP 7000, AES-GCM firmware). No cloud account needed.
actor GreeClient {
    static let cols = ["Pow", "Mod", "SetTem", "WdSpd", "Air", "Blo", "Health", "SwhSlp", "Lig",
                       "SwingLfRig", "SwUpDn", "Quiet", "Tur", "SvSt", "TemSen"]

    private static let genericKey = Data("{yxAHAY_Lm6pbC/<".utf8)
    private static let ecbKey = Data("a3K8Bx%2r8Y7#xDh".utf8)
    private static let nonce = Data([0x54, 0x40, 0x78, 0x44, 0x49, 0x67, 0x5a, 0x51, 0x6c, 0x5e, 0x63, 0x13])
    private static let aad = Data("qualcomm-test".utf8)

    private var ip: String?
    private var mac: String?
    private var key: Data?

    // MARK: public API

    func status() throws -> [String: Int] {
        try withReconnect {
            let r = try call(["cols": Self.cols, "mac": mac!, "t": "status"], i: 0)
            guard let names = r["cols"] as? [String], let vals = r["dat"] as? [Int] else {
                throw GreeError("Unexpected status reply")
            }
            return Dictionary(uniqueKeysWithValues: zip(names, vals))
        }
    }

    func command(_ pairs: [(String, Int)]) throws {
        _ = try withReconnect {
            try call(["opt": pairs.map(\.0), "p": pairs.map(\.1), "t": "cmd"], i: 0)
        }
    }

    // MARK: connection

    private func withReconnect<T>(_ body: () throws -> T) throws -> T {
        if key == nil { try connect() }
        do { return try body() } catch {
            key = nil
            try connect()
            return try body()
        }
    }

    private func connect() throws {
        let env = ProcessInfo.processInfo.environment["GREE_IP"]
        let cached = UserDefaults.standard.string(forKey: "ip")
        let hosts = env.map { [$0] } ?? ([cached].compactMap { $0 } + ["255.255.255.255"])
        let scan = Data(#"{"t":"scan"}"#.utf8)

        for host in hosts {
            for (data, from) in udp(scan, to: host, wait: host == "255.255.255.255" ? 2 : 1) {
                guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pack = o["pack"] as? String,
                      let dev = try? openScan(pack: pack, tag: o["tag"] as? String),
                      let devMac = dev["mac"] as? String else { continue }
                ip = from
                mac = devMac
                try bind()
                UserDefaults.standard.set(from, forKey: "ip")
                return
            }
        }
        throw GreeError("AC not found on the network")
    }

    private func bind() throws {
        key = nil
        let r = try call(["mac": mac!, "t": "bind", "uid": 0], i: 1, useKey: Self.genericKey)
        guard let k = r["key"] as? String else { throw GreeError("Bind failed") }
        key = Data(k.utf8)
    }

    // MARK: protocol

    private func call(_ pack: [String: Any], i: Int, useKey: Data? = nil) throws -> [String: Any] {
        guard let ip, let mac, let k = useKey ?? key else { throw GreeError("Not connected") }
        let (p, t) = try seal(pack, key: k)
        let msg: [String: Any] = ["cid": "app", "i": i, "t": "pack", "uid": 0, "tcid": mac, "pack": p, "tag": t]
        let payload = try JSONSerialization.data(withJSONObject: msg)
        guard let (data, _) = udp(payload, to: ip, wait: 2).first,
              let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rp = o["pack"] as? String, let rt = o["tag"] as? String
        else { throw GreeError("No reply from AC") }
        return try open(pack: rp, tag: rt, key: k)
    }

    private func seal(_ obj: [String: Any], key: Data) throws -> (String, String) {
        let plain = try JSONSerialization.data(withJSONObject: obj)
        let box = try AES.GCM.seal(plain, using: SymmetricKey(data: key),
                                   nonce: AES.GCM.Nonce(data: Self.nonce), authenticating: Self.aad)
        return (box.ciphertext.base64EncodedString(), box.tag.base64EncodedString())
    }

    private func open(pack: String, tag: String, key: Data) throws -> [String: Any] {
        guard let c = Data(base64Encoded: pack), let t = Data(base64Encoded: tag) else {
            throw GreeError("Bad reply encoding")
        }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: Self.nonce), ciphertext: c, tag: t)
        let plain = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Self.aad)
        return try JSONSerialization.jsonObject(with: plain) as? [String: Any] ?? [:]
    }

    /// Scan replies are AES-ECB on older firmware (the unit here), GCM on newer.
    private func openScan(pack: String, tag: String?) throws -> [String: Any] {
        if let tag { return try open(pack: pack, tag: tag, key: Self.genericKey) }
        guard let raw = Data(base64Encoded: pack) else { throw GreeError("Bad scan reply") }
        var out = Data(count: raw.count + kCCBlockSizeAES128)
        var n = 0
        let outCount = out.count
        let status = out.withUnsafeMutableBytes { o in
            raw.withUnsafeBytes { i in
                Self.ecbKey.withUnsafeBytes { k in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                            k.baseAddress, k.count, nil, i.baseAddress, i.count,
                            o.baseAddress, outCount, &n)
                }
            }
        }
        guard status == kCCSuccess else { throw GreeError("Scan decrypt failed") }
        return try JSONSerialization.jsonObject(with: out.prefix(n)) as? [String: Any] ?? [:]
    }

    // MARK: UDP (blocking, called on the actor's thread; worst case ~2 s)

    private func udp(_ payload: Data, to host: String, wait: Double) -> [(Data, String)] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(7000).bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return [] }
        let sent = payload.withUnsafeBytes { p in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, p.baseAddress, p.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent >= 0 else { return [] }

        var buf = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buf, buf.count, 0, $0, &len)
                }
            }
            if n > 0 {
                var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &from.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
                return [(Data(buf[0..<n]), String(cString: ipBuf))]
            }
        }
        return []
    }
}
