# App Store: App Privacy ("nutrition label") answers

App Store Connect → the app → *App Privacy* → *Get Started*. Based on the code
at commit a26c259. The AdMob part follows Google's guide,
<https://developers.google.com/admob/ios/privacy/data-disclosure>; **re-check
it when you fill the form**.

**Do you or your third-party partners collect data from this app?** → **Yes**.

"Linked" = linked to the user's identity. "Tracking" = used to track the user
across other companies' apps/sites (needs the ATT prompt, which the app shows).

| Data type | Purposes | Linked to user? | Used for tracking? | Source |
|---|---|---|---|---|
| Contact Info → **Email Address** | App Functionality | **Yes** | No | Account (email, Google, Apple; may be an Apple private relay address) |
| Contact Info → **Name** | App Functionality | **Yes** | No | Display name (Profile), from sign-up / Google / Apple |
| User Content → **Other User Content** | App Functionality | **Yes** | No | Habits (name, emoji, colour, schedule, reminder time) synced to the account |
| Identifiers → **User ID** | App Functionality | **Yes** | No | Supabase account id |
| Identifiers → **Device ID** | Third-Party Advertising, Analytics | No | **Yes** | IDFA (only if the user allows tracking) / IDFV, AdMob SDK |
| Usage Data → **Product Interaction** | App Functionality (our sync); Third-Party Advertising, Analytics (AdMob) | **Yes** for our data; No for AdMob | No for our data; **Yes** for AdMob | Check-ins, game state, quote loves (ours); app launches/taps (AdMob) |
| Usage Data → **Advertising Data** | Third-Party Advertising | No | **Yes** | Ads seen / tapped, AdMob SDK |
| Location → **Coarse Location** | Third-Party Advertising, Analytics | No | **Yes** | Derived from IP by AdMob |
| Diagnostics → **Crash Data**, **Performance Data**, **Other Diagnostic Data** | Analytics, Third-Party Advertising | No | No | AdMob SDK |

App Store Connect asks per data type; when one type has both "ours" and
"AdMob" uses (Product Interaction), tick the union: purposes App
Functionality + Third-Party Advertising + Analytics, **linked: Yes**,
**tracking: Yes**. Over-declaring is safe; under-declaring gets rejected.

**Not collected**: health & fitness, financial info, precise location,
sensitive info, contacts, emails or text messages, photos/videos, audio,
gameplay content, customer support, browsing/search history, purchases.
Reminders (local notifications) and widgets (App Group storage) stay on the
device.

The resulting label will show three sections: **Data Used to Track You**
(Device ID, Advertising Data, Coarse Location, Product Interaction),
**Data Linked to You** (Contact Info, User Content, Identifiers, Usage Data),
**Data Not Linked to You** (Diagnostics).

## Related Info.plist / privacy manifest facts

- `NSUserTrackingUsageDescription` is set (ATT prompt after Google UMP).
- Google Mobile Ads ships its own `PrivacyInfo.xcprivacy`; the app's
  required-reason APIs come from Flutter plugins' manifests. Xcode's
  *Product → Archive → Generate Privacy Report* summarises them; App Store
  Connect warns on upload if something is missing.
