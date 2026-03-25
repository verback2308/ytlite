import Foundation

struct InnertubeContexts {

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
                "screenHeightPoints": 1440,
                "screenPixelDensity": 1,
                "screenWidthPoints": 2560,
                "deviceMake": "",
                "deviceModel": "",
                "browserName": "Chrome",
                "browserVersion": "140.0.0.0",
                "userAgent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36,gzip(gfe)",
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
    static let android: [String: Any] = [
        "context": ["client": ["clientName": DirectPlaybackClient.android.clientName, "clientVersion": DirectPlaybackClient.android.clientVersion, "hl": "en", "gl": "US", "androidSdkVersion": 28]]
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
    static let androidVR: [String: Any] = [
        "context": ["client": [
            "clientName": DirectPlaybackClient.androidVR.clientName,
            "clientVersion": DirectPlaybackClient.androidVR.clientVersion,
            "hl": "en",
            "timeZone": "UTC",
            "utcOffsetMinutes": 0,
            "deviceMake": "Oculus",
            "deviceModel": "Quest 3",
            "androidSdkVersion": 32,
            "osName": "Android",
            "osVersion": "12L",
            "userAgent": "com.google.android.apps.youtube.vr.oculus/1.71.26 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
        ]]
    ]
    static let ios: [String: Any] = [
        "context": ["client": [
            "clientName": DirectPlaybackClient.ios.clientName,
            "clientVersion": DirectPlaybackClient.ios.clientVersion,
            "hl": "en",
            "timeZone": "UTC",
            "utcOffsetMinutes": 0,
            "deviceMake": "Apple",
            "deviceModel": "iPhone16,2",
            "osName": "iPhone",
            "osVersion": "17.5.1.21F90",
            "userAgent": "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)"
        ]]
    ]
}
