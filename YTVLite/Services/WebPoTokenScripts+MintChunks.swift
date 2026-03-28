import Foundation

extension WebPoTokenScripts {
    static let challengeJS = """
      function descramble(scrambled) {
        const buffer = base64ToU8(scrambled);
        if (!buffer.length) return undefined;
        return new TextDecoder().decode(
          buffer.map((b) => b + 97)
        );
      }

      async function createChallenge() {
        postLog("challenge:create:start");
        const challengeUrl =
          "https://jnn-pa.googleapis.com" +
          "/$rpc/google.internal.waa.v1.Waa/Create";
        const response = await fetchWithTimeout(
          challengeUrl,
          {
            method: "POST",
            headers: getHeaders(),
            body: JSON.stringify([ requestKey ])
          },
          8000,
          "Challenge"
        );

        if (!response.ok) {
          throw new Error(
            "Challenge failed with status " +
            response.status
          );
        }

        const rawData = await response.json();
        postLog("challenge:create:ok");
        let challengeData = [];

        if (
          rawData.length > 1 &&
          typeof rawData[1] === "string"
        ) {
          challengeData = JSON.parse(
            descramble(rawData[1]) || "[]"
          );
        } else if (
          rawData.length &&
          typeof rawData[0] === "object"
        ) {
          challengeData = rawData[0];
        }

        const [
          messageId, wrappedScript, wrappedUrl,
          interpreterHash, program, globalName
        ] = challengeData;
        const interpreterJavascript =
          Array.isArray(wrappedScript)
            ? wrappedScript.find(
                (v) => v && typeof v === "string"
              )
            : null;
        const interpreterUrl =
          Array.isArray(wrappedUrl)
            ? wrappedUrl.find(
                (v) => v && typeof v === "string"
              )
            : null;

        if (
          !interpreterJavascript ||
          !program ||
          !globalName
        ) {
          throw new Error(
            "Malformed challenge response"
          );
        }

        postLog("challenge:parsed");
        const meta = [
          messageId || "nil",
          interpreterHash || "nil",
          globalName || "nil",
          interpreterUrl || "nil"
        ].join("|");
        postLog("challenge:meta:" + meta);
        return {
          interpreterJavascript,
          interpreterHash,
          program,
          globalName
        };
      }
    """
}

extension WebPoTokenScripts {
    static let generateTokenJS = """
      async function generatePoToken() {
        const challenge = await createChallenge();
        postLog("vm:script:eval");
        const scriptId =
          challenge.interpreterHash ||
          ("ytvlite-bg-" + identifier);
        if (!document.getElementById(scriptId)) {
          const script =
            document.createElement("script");
          script.type = "text/javascript";
          script.id = scriptId;
          script.textContent =
            challenge.interpreterJavascript;
          document.head.appendChild(script);
        }

        const vm =
          globalThis[challenge.globalName];
        if (!vm || !vm.a) {
          throw new Error(
            "BotGuard VM not available"
          );
        }
        postLog("vm:ready");

        let asyncSnapshotFunction;
        const vmFunctionsCallback = (
          asyncSnapshot, _shutdown,
          _passEvent, _checkCamera
        ) => {
          asyncSnapshotFunction = asyncSnapshot;
        };

        const vmInitResult = await vm.a(
          challenge.program,
          vmFunctionsCallback,
          true,
          undefined,
          () => {},
          [ [], [] ]
        );
        postLog("vm:loaded");
        const initType =
          Array.isArray(vmInitResult)
            ? "array" : typeof vmInitResult;
        postLog("vm:init:type:" + initType);
        if (Array.isArray(vmInitResult)) {
          postLog(
            "vm:init:length:" +
            vmInitResult.length
          );
          const s0 =
            vmInitResult[0] instanceof Function
              ? "function"
              : typeof vmInitResult[0];
          postLog("vm:init:slot0:" + s0);
        }

        if (!asyncSnapshotFunction) {
          throw new Error(
            "Async snapshot function not found"
          );
        }

        const webPoSignalOutput = [];
        postLog("snapshot:start");
        const botguardResponse =
          await new Promise(
            (resolve, reject) => {
              asyncSnapshotFunction(
                (r) => resolve(r),
                [
                  undefined, undefined,
                  webPoSignalOutput, undefined
                ]
              );
              setTimeout(
                () => reject(
                  new Error(
                    "BotGuard snapshot timeout"
                  )
                ),
                5000
              );
            }
          );
        postLog("snapshot:ok");
        postLog(
          "snapshot:signal:length:" +
          webPoSignalOutput.length
        );
        postLog(
          "snapshot:signal:types:" +
          webPoSignalOutput.map((value) => {
            if (value instanceof Function)
              return "function";
            if (value === undefined)
              return "undefined";
            if (value === null) return "null";
            if (Array.isArray(value))
              return "array";
            return typeof value;
          }).join(",")
        );

        const getMinter = webPoSignalOutput[0];
        if (!(getMinter instanceof Function)) {
          throw new Error("Minter not found");
        }
        window.__ytvliteWebPoState[identifier] = {
          getMinter, attemptID
        };
        postLog("generate_it:start");
        window.webkit.messageHandlers
          .webPoGenerateIT.postMessage({
            identifier,
            attemptID,
            botguardResponse
          });
      }

      (async () => {
        try {
          await generatePoToken();
        } catch (error) {
          const message =
            error && error.message
              ? error.message : String(error);
          window.webkit.messageHandlers.webPoError
            .postMessage({
              identifier, attemptID, message
            });
        }
      })();
    """
}
