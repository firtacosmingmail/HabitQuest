# Perseveo confirmation pages

Static pages that the `auth-confirm` Supabase Edge Function redirects to after a
user clicks the link in their confirmation email.

- `index.html`: email confirmed.
- `error.html?reason=expired|invalid|missing`: the link didn't work.
- `privacy.html`: the privacy policy (DRAFT: fill the `{{...}}` placeholders before publishing; its URL goes on the store listings).

Plain HTML/CSS, no build step, no secrets. Hosted on GitHub Pages.
