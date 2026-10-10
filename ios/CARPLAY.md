# CarPlay maps entitlement

Survive Miami's CarPlay scene is a navigation preview. It shows the two routes and the exposure summary. It does not speak turn-by-turn guidance, and it does not tell the car a road is closed.

Apple grants `com.apple.developer.carplay-maps`. Xcode cannot turn that entitlement on by itself.

1. Sign in at [developer.apple.com/account](https://developer.apple.com/account) with the Apple Developer account for this app.
2. Request the CarPlay navigation entitlement from [developer.apple.com/contact/carplay](https://developer.apple.com/contact/carplay). Describe the app as a Miami driving preview that compares a typical route with one that reduces mapped flood and event exposure. Say that it does not provide turn-by-turn guidance.
3. After Apple approves it, add the entitlement to the App ID `app.mapmiami.ios`.
4. Put the key below in `ios/MapMiami/MapMiami.entitlements`, then set the iOS target’s Code Signing Entitlements build setting to that file. The file is not used for signing yet, because a profile cannot include `com.apple.developer.carplay-maps` until Apple grants it.

```xml
<key>com.apple.developer.carplay-maps</key>
<true/>
```

5. Regenerate the provisioning profile so it includes that entitlement. The CarPlay Simulator can show the scene once that profile is installed. A car will show it only after the entitlement is on the installed profile.

`CPMapPanel` is the iOS 27 panel beside the map. The Xcode on this machine (iOS 26.2 SDK) does not include that class. `CarPlayMapPanel.swift` passes the route rows to `CPMapPanel` when the class is in the system. On this SDK the same rows are the `CPMapTemplate` trip preview: route name, minutes, flood summary, and "Not a closure."
