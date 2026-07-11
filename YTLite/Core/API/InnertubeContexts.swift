import Foundation

enum InnertubeContexts {
    /// Full web client context matching YouTube.js Session.#buildContext for WEB client.
    static let web: [String: Any] = [
        "context": [
            "client": [
                "clientName": "WEB",
                "clientVersion": "2.20260206.01.00",
                "hl": "en",
                "gl": "US",
                "osName": "Windows",
                "osVersion": "10.0",
                "platform": "DESKTOP",
                "clientFormFactor": "UNKNOWN_FORM_FACTOR",
                "userInterfaceTheme": "USER_INTERFACE_THEME_LIGHT",
                "timeZone": "UTC",
                "utcOffsetMinutes": 0,
                "screenDensityFloat": 1,
                "screenHeightPoints": 1_440,
                "screenPixelDensity": 1,
                "screenWidthPoints": 2_560,
                "deviceMake": "",
                "deviceModel": "",
                "browserName": "Chrome",
                "browserVersion": "140.0.0.0",
                "userAgent": UserAgent.chromeDesktop,
                "originalUrl": "https://www.youtube.com",
                "memoryTotalKbytes": "8000000",
                "mainAppWebInfo": [
                    "graftUrl": "https://www.youtube.com",
                    "pwaInstallabilityStatus": "PWA_INSTALLABILITY_STATUS_UNKNOWN",
                    "webDisplayMode": "WEB_DISPLAY_MODE_BROWSER",
                    "isWebNativeShareAvailable": true
                ]
            ],
            "user": ["enableSafetyMode": false, "lockedSafetyMode": false],
            "request": ["useSsl": true, "internalExperimentFlags": []]
        ]
    ]
    static let tv: [String: Any] = [
        "context": [
            "client": [
                "clientName": "TVHTML5",
                "clientVersion": "7.20260311.12.00",
                "hl": "en",
                "gl": "US",
                "platform": "TV",
                "clientFormFactor": "UNKNOWN_FORM_FACTOR"
            ],
            "user": ["enableSafetyMode": false, "lockedSafetyMode": false],
            "request": ["useSsl": true, "internalExperimentFlags": []]
        ]
    ]
    /// Mobile web client. Logged-out, so its GVS `pot` binds to visitorData —
    /// matching the anonymous BotGuard token we mint (unlike authed TVHTML5,
    /// whose pot binds to the account datasyncId).
    static let mweb: [String: Any] = [
        "context": [
            "client": [
                "clientName": "MWEB",
                "clientVersion": "2.20250101.00.00",
                "hl": "en",
                "gl": "US",
                "userAgent": UserAgent.mobileSafari
            ]
        ]
    ]
    static let android: [String: Any] = [
        "context": [
            "client": [
                "clientName": "ANDROID",
                "clientVersion": "21.02.35",
                "hl": "en",
                "gl": "US",
                "androidSdkVersion": 30,
                "osName": "Android",
                "osVersion": "11",
                "userAgent": "com.google.android.youtube/21.02.35"
                    + " (Linux; U; Android 11) gzip"
            ],
            "user": [
                "enableSafetyMode": false,
                "lockedSafetyMode": false
            ],
            "request": [
                "useSsl": true,
                "internalExperimentFlags": []
            ]
        ]
    ]

    static let androidVR: [String: Any] = [
        "context": [
            "client": [
                "clientName": "ANDROID_VR",
                "clientVersion": "1.65.10",
                "hl": "en",
                "timeZone": "UTC",
                "utcOffsetMinutes": 0,
                "deviceMake": "Oculus",
                "deviceModel": "Quest 3",
                "androidSdkVersion": 32,
                "osName": "Android",
                "osVersion": "12L",
                "userAgent": [
                    "com.google.android.apps.youtube.vr.oculus/1.65.10",
                    "(Linux; U; Android 12L;",
                    "eureka-user Build/SQ3A.220605.009.A1) gzip"
                ].joined(separator: " ")
            ]
        ]
    ]

    /// Official iOS app client. Its timedtext caption URLs are served without
    /// a proof-of-origin token, unlike the WEB client's.
    static let ios: [String: Any] = [
        "context": [
            "client": [
                "clientName": "IOS",
                "clientVersion": "20.10.4",
                "hl": "en",
                "deviceMake": "Apple",
                "deviceModel": "iPhone16,2",
                "osName": "iPhone",
                "osVersion": "18.3.2.22D82",
                "userAgent": UserAgent.iosYouTube
            ]
        ]
    ]
}
