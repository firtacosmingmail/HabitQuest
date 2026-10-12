-- Google / Apple sign-in (auth-oauth): the signup trigger also fires for
-- OAuth users, but their metadata has no display_name. Fall back to the name
-- the provider supplies (Google: full_name / name; Apple: full_name only on
-- the very first authorization, often absent). No name → null, and the app
-- shows its "Nameless hero" placeholder until the user sets one.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    nullif(left(trim(coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'displayName'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
      ''
    )), 100), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;
