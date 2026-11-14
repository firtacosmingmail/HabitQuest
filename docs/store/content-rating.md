# Content rating and target audience notes

## Google Play: IARC questionnaire

Play Console → *Policy → App content → Content rating → Start questionnaire*.

- Email: `{{CONTACT_EMAIL}}` (IARC sends the certificate there)
- Category: **All other app types** (not a game, not social/communication;
  the XP and levels are gamified progress, not a game with gameplay content)

| Question (summary) | Answer | Note |
|---|---|---|
| Violence, blood, fear | **No** | Mascot and emoji only |
| Sexuality, nudity | **No** | |
| Language (profanity, crude humour) | **No** | Quotes are curated by the admin; keep them clean |
| Controlled substances (drugs, alcohol, tobacco) | **No** | Users may name a habit "quit smoking": that is user content, not app content |
| Gambling (real or simulated) | **No** | No loot boxes, no random rewards for money |
| Users can interact or exchange content with each other | **No** | No chat, no sharing, no public profiles. Habits are private to the account |
| Shares the user's current physical location with other users | **No** | |
| Allows users to purchase digital goods | **No** | No in-app purchases |
| Contains ads | (not part of IARC; declared under *Ads*) | |
| Unrestricted internet access (web browser) | **No** | |

Expected result: **PEGI 3 / ESRB Everyone / USK 0 / IARC 3+**.

## Google Play: Target audience and content

- Target age groups: **13–15, 16–17, 18+** (do **not** select under 13).
  Selecting under-13 groups brings the app under the Families policy (only
  Families-certified ad SDKs, no advertising ID for kids, teacher-approved
  rules), which the current AdMob setup is not configured for.
- *Could the app unintentionally appeal to children?* The mascot and bright
  style might; answer honestly. If Play asks, explain it is a productivity
  tool for teens and adults, with no child-directed content. If you ever
  target kids, AdMob must be set to child-directed treatment first.
- Store listing must not suggest it is for children.

## App Store: Age rating

All content questions → **None / No**; *Unrestricted web access* → No;
*Gambling* → No; *Made for Kids* → **No**. Result: **4+**. (Ads don't need
a higher rating on their own; the AdMob max ad content rating is the
AdMob-side setting; consider setting it to *G* or *PG* in AdMob → Blocking
controls so ads suit a 4+/PEGI 3 app.)
