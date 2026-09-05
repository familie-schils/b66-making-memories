create extension if not exists pgcrypto;

alter table public.campers
  add column if not exists owner_id uuid references auth.users(id) on delete set null;

create or replace function public.admin_create_camper_owner(p_email text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_requester_id constant uuid := auth.uid();
  v_head_admin_id constant uuid := '13032a8d-1c16-4f80-b497-b679abf36682';
  v_email text := lower(trim(coalesce(p_email, '')));
  v_password text := coalesce(p_password, '');
  v_user_id uuid := gen_random_uuid();
  v_camper_id bigint;
begin
  if v_requester_id is null then
    raise exception using
      errcode = '42501',
      message = 'Alleen een ingelogde hoofdbeheerder mag een campereigenaar aanmaken.';
  end if;

  if v_requester_id <> v_head_admin_id then
    raise exception using
      errcode = '42501',
      message = 'Alleen de hoofdbeheerder mag deze functie gebruiken.';
  end if;

  if v_email = '' then
    raise exception using
      errcode = '22023',
      message = 'E-mailadres is verplicht.';
  end if;

  if position('@' in v_email) = 0 then
    raise exception using
      errcode = '22023',
      message = 'Vul een geldig e-mailadres in.';
  end if;

  if v_password = '' then
    raise exception using
      errcode = '22023',
      message = 'Wachtwoord is verplicht.';
  end if;

  if exists (
    select 1
    from auth.users
    where lower(email) = v_email
  ) or exists (
    select 1
    from public.profiles
    where lower(email) = v_email
  ) then
    raise exception using
      errcode = '23505',
      message = 'Er bestaat al een gebruiker met dit e-mailadres.';
  end if;

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    recovery_sent_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    v_email,
    crypt(v_password, gen_salt('bf')),
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('created_via', 'admin_create_camper_owner', 'test_agent', true),
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  insert into auth.identities (
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    v_user_id::text,
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email),
    'email',
    now(),
    now(),
    now()
  );

  insert into public.profiles (user_id, email, display_name)
  values (v_user_id, v_email, v_email);

  insert into public.campers (naam, owner_id)
  values ('Camper van ' || v_email, v_user_id)
  returning id into v_camper_id;

  insert into public.camper_users (user_id, camper_id, role)
  values (v_user_id, v_camper_id, 'admin');

  return jsonb_build_object(
    'user_id', v_user_id,
    'camper_id', v_camper_id,
    'email', v_email,
    'role', 'admin',
    'message', 'Campereigenaar succesvol aangemaakt.'
  );
exception
  when unique_violation then
    if exists (
      select 1
      from auth.users
      where lower(email) = v_email
    ) or exists (
      select 1
      from public.profiles
      where lower(email) = v_email
    ) then
      raise exception using
        errcode = '23505',
        message = 'Er bestaat al een gebruiker met dit e-mailadres.';
    end if;
    raise;
end;
$$;

revoke all on function public.admin_create_camper_owner(text, text) from public;
grant execute on function public.admin_create_camper_owner(text, text) to authenticated;

comment on function public.admin_create_camper_owner(text, text) is
  'TEST-AGENT RPC voor hoofdbeheerder: maakt auth user, profiel, camper en admin-koppeling atomair aan.';
