/// Where an ad slot sits. Ads are only ever placed on these two screens:
/// never on login, profile, splash, edit or create screens.
enum AdPlacement {
  /// Inline in the Habits list, between habit cards.
  habitsList,

  /// On the habit details screen, under the monthly calendar.
  habitDetails,
}

/// Number of habit cards before the first inline ad in the Habits list.
const habitsListFirstAdAfter = 3;

/// Number of habit cards between later inline ads.
const habitsListAdEvery = 6;

/// Whether an inline ad follows the [position]-th habit card (1-based) in a
/// Habits list of [total] cards: after card 3, then after every 6 more
/// (9, 15, ...); with fewer than 3 cards, one ad after the last card; none
/// for an empty list. Ads always sit between whole cards, so never between
/// a card and its check-in button.
bool habitsListAdAfter(int position, int total) {
  if (total <= 0 || position < 1 || position > total) return false;
  if (total < habitsListFirstAdAfter) return position == total;
  return position >= habitsListFirstAdAfter &&
      (position - habitsListFirstAdAfter) % habitsListAdEvery == 0;
}
