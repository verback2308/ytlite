import Foundation

// MARK: - Mint Script JS Utilities

private let mintUtilityJS = """
  function getHeaders() {
    return {
      "Content-Type": "application/json+protobuf",
      "x-goog-api-key": googApiKey,
      "x-user-agent": "grpc-web-javascript/0.1"
    };
  }

  async function fetchWithTimeout(
    url, init, timeoutMs, label
  ) {
    return await Promise.race([
      fetch(url, init),
      new Promise((_, reject) => setTimeout(
        () => reject(
          new Error(label + " timeout")
        ),
        timeoutMs
      ))
    ]);
  }

  function base64ToU8(base64) {
    const normalized = base64.replace(
      /[-_.]/g,
      (ch) => ({
        "-": "+", "_": "/", ".": "="
      }[ch])
    );
    const bin = atob(normalized);
    return new Uint8Array(
      Array.from(bin)
        .map((c) => c.charCodeAt(0))
    );
  }

  function u8ToBase64(u8, base64url) {
    const r = btoa(
      String.fromCharCode(...u8)
    );
    if (!base64url) return r;
    return r
      .replace(/\\+/g, "-")
      .replace(/\\//g, "_")
      .replace(/=/g, "");
  }
"""

private let mintContinueCallbackJS = """
  window.__ytvliteWebPoState =
    window.__ytvliteWebPoState || {};

  window.__ytvliteContinueMint = async (
    identifier, attemptID, integrityToken
  ) => {
    try {
      const state =
        window.__ytvliteWebPoState[identifier];
      if (
        !state ||
        state.attemptID !== attemptID ||
        !(state.getMinter instanceof Function)
      ) {
        throw new Error("Stored minter missing");
      }

      postLog("mint_callback:start");
      const mintCallback =
        await state.getMinter(
          base64ToU8(integrityToken)
        );
      if (!(mintCallback instanceof Function)) {
        throw new Error("Mint callback invalid");
      }

      postLog("mint:start");
      const tokenBytes = await mintCallback(
        new TextEncoder().encode(identifier)
      );
      if (!(tokenBytes instanceof Uint8Array)) {
        throw new Error("Mint result invalid");
      }

      postLog("mint:ok");
      window.webkit.messageHandlers.webPoToken
        .postMessage({
          identifier,
          attemptID,
          token: u8ToBase64(tokenBytes, true)
        });
    } catch (error) {
      const message =
        error && error.message
          ? error.message : String(error);
      window.webkit.messageHandlers.webPoError
        .postMessage(
          { identifier, attemptID, message }
        );
    }
  };
"""

// MARK: - Script Assembly

enum WebPoTokenScripts {
    static func mintScript(
        identifier: String,
        attemptID: String,
        requestKey: String,
        apiKey: String
    ) -> String {
        let vars = """
          const identifier = \(identifier);
          const attemptID = \(attemptID);
          const requestKey = \(requestKey);
          const googApiKey = "\(apiKey)";
          const postLog = (message) => {
            window.webkit.messageHandlers
              .webPoLog.postMessage({
                identifier, attemptID, message
              });
          };
        """
        return [
            "(() => {",
            vars,
            mintUtilityJS,
            mintContinueCallbackJS,
            challengeJS,
            generateTokenJS,
            "})();",
            "true;"
        ].joined(separator: "\n")
    }

    static func continueMintScript(
        identifier: String,
        attemptID: String,
        integrityToken: String
    ) -> String {
        """
        (() => {
          if (window.__ytvliteContinueMint) {
            window.__ytvliteContinueMint(
              \(identifier),
              \(attemptID),
              \(integrityToken)
            );
          } else {
            const id = \(identifier);
            const aid = \(attemptID);
            window.webkit.messageHandlers
              .webPoError.postMessage({
                identifier: id,
                attemptID: aid,
                message: "Continue mint missing"
              });
          }
        })();
        true;
        """
    }
}
