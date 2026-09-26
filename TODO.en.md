# To Do

[中文](TODO.md) · English

## Handling translation failures caused by cloud model filtering

- Observed on 2026-09-23: Volcengine Ark `deepseek-v4-flash-ga-260731` returned HTTP 200 with `finish_reason: content_filter` for a Japanese reporter question. `message.content` contained a refusal such as “cannot answer,” which the app currently displays as a translation. A comparable English passage translated normally.
- Shortening the translation prompt did not avoid filtering. Splitting the source into sentences isolated a phrase containing “米中首脳会談” that was also filtered when submitted alone. Current evidence points to the provider’s content filter, rather than the built-in prompt.
- Design provider-independent failure detection and presentation for `finish_reason: content_filter`, structured `refusal`, HTTP errors, and refusals returned as plain text. Avoid matching only one refusal phrase. Validate against real responses from multiple providers and do not present filtered or incomplete output as a successful translation.
- Model providers control filtering; an app error message cannot guarantee that the passage can be translated with the same model. Consider letting the user retry with another model.
- The API key used for verification was not committed.
