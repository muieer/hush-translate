import Foundation

/// 通用 OpenAI-compatible 翻译客户端。
/// 同时支持纯文本和多模态（图片）输入。
actor TranslateService {

    enum TranslateError: LocalizedError {
        case invalidURL(String)
        case http(Int, String)
        case emptyResponse
        case decoding(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidURL(let s): return "URL 不合法: \(s)"
            case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
            case .emptyResponse: return "模型返回为空"
            case .decoding(let s): return "响应解析失败: \(s)"
            case .cancelled: return "已取消"
            }
        }
    }

    func translate(_ request: TranslationRequest, config: TranslateConfig) async throws -> String {
        let endpoint = config.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, let url = URL(string: endpoint + "/chat/completions") else {
            throw TranslateError.invalidURL(endpoint)
        }

        let messages = buildMessages(for: request, config: config)

        let body: [String: Any] = [
            "model":       config.model,
            "messages":    messages,
            "temperature": 0.3,
            "stream":      false,
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        urlRequest.timeoutInterval = config.requestTimeout

        Log.api.info("POST \(url.absoluteString, privacy: .public) model=\(config.model, privacy: .public) textLen=\(request.text.count) hasImage=\(request.imageData != nil)")

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw TranslateError.http(0, "no HTTPURLResponse")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<binary>"
                Log.api.error("HTTP \(http.statusCode) body=\(body, privacy: .public)")
                throw TranslateError.http(http.statusCode, body)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw TranslateError.decoding("顶层不是 JSON 对象")
            }
            guard let choices = json["choices"] as? [[String: Any]], let first = choices.first else {
                throw TranslateError.decoding("无 choices")
            }
            guard let msg = first["message"] as? [String: Any], let content = msg["content"] as? String else {
                throw TranslateError.decoding("无 content")
            }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { throw TranslateError.emptyResponse }
            return trimmed
        } catch is CancellationError {
            throw TranslateError.cancelled
        }
    }

    // MARK: - Private

    private func buildMessages(for req: TranslationRequest, config: TranslateConfig) -> [[String: Any]] {
        let systemText = systemPrompt(for: req, config: config)
        var messages: [[String: Any]] = [["role": "system", "content": systemText]]

        if let imgData = req.imageData {
            let b64 = imgData.base64EncodedString()
            let userText: String
            if case .screenshot = req.source {
                userText = "请先识别图片中的所有文字（按原文顺序、保留段落和换行），然后翻译成 \(displayName(req.targetLang))。先输出【原文】段落，再空一行输出【译文】段落。"
            } else {
                userText = "Translate the text in this image to \(displayName(req.targetLang)). First output the original text (preserving line breaks), then a blank line, then the translation."
            }
            messages.append([
                "role": "user",
                "content": [
                    ["type": "text",      "text": userText] as [String: Any],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(b64)"]] as [String: Any],
                ] as [[String: Any]],
            ])
        } else {
            // 系统提示词里已包含翻译指令与 {input}，user 消息只承载原文。
            messages.append(["role": "user", "content": req.text])
        }
        return messages
    }

    private func systemPrompt(for req: TranslationRequest, config: TranslateConfig) -> String {
        let src = req.sourceLang == "auto" ? "源语言（自动检测）" : displayName(req.sourceLang)
        let dst = displayName(req.targetLang)
        return renderTemplate(config.systemPrompt,
                              sourceLanguage: src,
                              targetLanguage: dst,
                              input: req.text)
    }

    /// 渲染自定义提示词模板。支持 {sourceLanguage}、{targetLanguage}、{input}。
    /// 未识别的 {xxx} 占位符原样保留，便于用户自定义字面文本。
    private func renderTemplate(_ template: String,
                                sourceLanguage: String,
                                targetLanguage: String,
                                input: String) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{sourceLanguage}", with: sourceLanguage)
        result = result.replacingOccurrences(of: "{targetLanguage}", with: targetLanguage)
        result = result.replacingOccurrences(of: "{input}", with: input)
        return result
    }

    private func displayName(_ code: String) -> String {
        SettingsStore.languages.first(where: { $0.code == code })?.label ?? code
    }
}
