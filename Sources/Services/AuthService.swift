import Foundation
import CryptoKit

enum AuthError: LocalizedError {
    case network(String)
    case invalidResponse(String)
    case otpFailed(String)
    case tokenFailed(String)

    var errorDescription: String? {
        switch self {
        case .network(let m): return m
        case .invalidResponse(let m): return m
        case .otpFailed(let m): return m
        case .tokenFailed(let m): return m
        }
    }
}

actor AuthService {
    private let session: URLSession
    private var codeVerifier = ""
    private var loginChallenge = ""

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        // Follow redirects so we land on login_challenge / code URLs
        session = URLSession(configuration: config)
    }

    // MARK: - Pre OTP

    func sendOTP(phone: String, channel: OTPChannel) async throws {
        codeVerifier = Self.makeCodeVerifier()
        let codeChallenge = Self.makeCodeChallenge(verifier: codeVerifier)
        setAuthCookies(codeVerifier: codeVerifier)

        // 1) OAuth authorize → extract login_challenge
        var authComponents = URLComponents(string: "\(ZomatoConfig.accountsBase)/oauth2/auth")!
        authComponents.queryItems = [
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: "offline openid"),
            .init(name: "response_type", value: "code"),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "redirect_uri", value: ZomatoConfig.redirectURI),
            .init(name: "state", value: Self.randomState()),
            .init(name: "client_id", value: ZomatoConfig.clientId),
            .init(name: "code_challenge", value: codeChallenge)
        ]

        var authReq = URLRequest(url: authComponents.url!)
        applyHeaders(&authReq)

        let (_, authResponse) = try await session.data(for: authReq)
        guard let http = authResponse as? HTTPURLResponse else {
            throw AuthError.network("No HTTP response from authorize")
        }
        guard let finalURL = http.url else {
            throw AuthError.invalidResponse("Missing authorize URL")
        }

        let challenge = URLComponents(url: finalURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "login_challenge" })?
            .value

        guard let challenge, !challenge.isEmpty else {
            throw AuthError.invalidResponse("Could not extract login_challenge. Try again.")
        }
        loginChallenge = challenge

        // 2) Send OTP
        var otpReq = URLRequest(url: URL(string: "\(ZomatoConfig.accountsBase)/login/phone")!)
        otpReq.httpMethod = "POST"
        applyHeaders(&otpReq)
        otpReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let form: [String: String] = [
            "number": phone,
            "country_id": "1",
            "lc": loginChallenge,
            "type": "initiate",
            "verification_type": channel.rawValue,
            "package_name": ZomatoConfig.packageName,
            "message_uuid": ""
        ]
        otpReq.httpBody = Self.formBody(form)

        let (data, resp) = try await session.data(for: otpReq)
        guard let httpResp = resp as? HTTPURLResponse else {
            throw AuthError.network("OTP request failed")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let status = json?["status"] as? Bool ?? false
        if !httpResp.statusCode.isSuccess || !status {
            let message = (json?["message"] as? String) ?? "Failed to send OTP (HTTP \(httpResp.statusCode))"
            throw AuthError.otpFailed(message)
        }
    }

    // MARK: - Post OTP

    func verifyOTP(phone: String, otp: String) async throws -> AuthTokens {
        // 1) Verify OTP
        var verifyReq = URLRequest(url: URL(string: "\(ZomatoConfig.accountsBase)/login/phone")!)
        verifyReq.httpMethod = "POST"
        applyHeaders(&verifyReq)
        verifyReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        verifyReq.httpBody = Self.formBody([
            "number": phone,
            "otp": otp,
            "country_id": "1",
            "lc": loginChallenge,
            "type": "verify",
            "trust_this_device": "true",
            "device_token": ""
        ])

        let (vData, vResp) = try await session.data(for: verifyReq)
        let vJSON = (try? JSONSerialization.jsonObject(with: vData)) as? [String: Any]
        guard (vResp as? HTTPURLResponse)?.statusCode.isSuccess == true,
              vJSON?["status"] as? Bool == true,
              let redirect1 = vJSON?["redirect_to"] as? String,
              let redirect1URL = URL(string: redirect1) else {
            let message = (vJSON?["message"] as? String) ?? "Invalid OTP"
            throw AuthError.otpFailed(message)
        }

        // 2) Follow redirect → consent_challenge
        var consentPageReq = URLRequest(url: redirect1URL)
        applyHeaders(&consentPageReq)
        let (_, consentPageResp) = try await session.data(for: consentPageReq)
        guard let consentURL = (consentPageResp as? HTTPURLResponse)?.url else {
            throw AuthError.invalidResponse("Consent page missing URL")
        }
        let consentChallenge = URLComponents(url: consentURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "consent_challenge" })?
            .value
        guard let consentChallenge else {
            throw AuthError.invalidResponse("Missing consent_challenge")
        }

        // 3) Post consent
        var consentReq = URLRequest(url: URL(string: "\(ZomatoConfig.accountsBase)/consent")!)
        consentReq.httpMethod = "POST"
        applyHeaders(&consentReq)
        consentReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        consentReq.httpBody = Self.formBody(["cc": consentChallenge])

        let (cData, cResp) = try await session.data(for: consentReq)
        let cJSON = (try? JSONSerialization.jsonObject(with: cData)) as? [String: Any]
        guard (cResp as? HTTPURLResponse)?.statusCode.isSuccess == true,
              cJSON?["status"] as? Bool == true,
              let redirect2 = cJSON?["redirect_to"] as? String,
              let redirect2URL = URL(string: redirect2) else {
            let message = (cJSON?["message"] as? String) ?? "Consent failed"
            throw AuthError.tokenFailed(message)
        }

        // 4) Final redirect → authorization code
        var finalReq = URLRequest(url: redirect2URL)
        applyHeaders(&finalReq)
        let (_, finalResp) = try await session.data(for: finalReq)
        guard let finalURL = (finalResp as? HTTPURLResponse)?.url else {
            throw AuthError.invalidResponse("Token redirect missing URL")
        }
        let items = URLComponents(url: finalURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let code = items.first(where: { $0.name == "code" })?.value
        let state = items.first(where: { $0.name == "state" })?.value
        let scope = items.first(where: { $0.name == "scope" })?.value

        guard let code, let state else {
            throw AuthError.tokenFailed("Missing authorization code")
        }

        // 5) Exchange code for tokens
        var tokenReq = URLRequest(url: URL(string: "\(ZomatoConfig.accountsBase)/token")!)
        tokenReq.httpMethod = "POST"
        applyHeaders(&tokenReq)
        tokenReq.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var tokenForm: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "code_verifier": codeVerifier,
            "client_id": ZomatoConfig.clientId,
            "redirect_uri": ZomatoConfig.redirectURI
        ]
        if let scope { tokenForm["scope"] = scope }
        tokenReq.httpBody = Self.formBody(tokenForm)

        let (tData, tResp) = try await session.data(for: tokenReq)
        let tJSON = (try? JSONSerialization.jsonObject(with: tData)) as? [String: Any]
        guard (tResp as? HTTPURLResponse)?.statusCode.isSuccess == true,
              tJSON?["status"] as? Bool == true,
              let tokenObj = tJSON?["token"] as? [String: Any],
              let access = tokenObj["access_token"] as? String else {
            let message = (tJSON?["message"] as? String) ?? "Token exchange failed"
            throw AuthError.tokenFailed(message)
        }
        let refresh = tokenObj["refresh_token"] as? String ?? ""
        return AuthTokens(accessToken: access, refreshToken: refresh)
    }

    func logout(accessToken: String, refreshToken: String) async {
        var req = URLRequest(url: URL(string: "\(ZomatoConfig.accountsBase)/signout")!)
        req.httpMethod = "POST"
        applyHeaders(&req, accessToken: accessToken)
        req.setValue(refreshToken, forHTTPHeaderField: "X-Zomato-Refresh-Token")
        req.setValue(
            "zxcv=; rurl=\(ZomatoConfig.redirectURI); cid=\(ZomatoConfig.clientId)",
            forHTTPHeaderField: "Cookie"
        )
        req.httpBody = Data()
        _ = try? await session.data(for: req)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    // MARK: - Helpers

    private func applyHeaders(_ request: inout URLRequest, accessToken: String? = nil) {
        for (k, v) in ZomatoHeaders.common(accessToken: accessToken) {
            request.setValue(v, forHTTPHeaderField: k)
        }
    }

    private func setAuthCookies(codeVerifier: String) {
        let domain = ".zomato.com"
        let path = "/"
        let pairs = [
            ("zxcv", codeVerifier),
            ("cid", ZomatoConfig.clientId),
            ("rurl", ZomatoConfig.redirectURI)
        ]
        for (name, value) in pairs {
            if let cookie = HTTPCookie(properties: [
                .domain: domain,
                .path: path,
                .name: name,
                .value: value,
                .secure: "TRUE"
            ]) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+:&="))
        let s = fields
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        return Data(s.utf8)
    }

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func makeCodeChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func randomState(_ length: Int = 32) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}

private extension Int {
    var isSuccess: Bool { (200..<300).contains(self) }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
