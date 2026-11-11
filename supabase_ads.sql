-- My Khata: Ads backend (Supabase SQL Editor mein run karein)
-- SIRF tab run karein jab app mein ads par error aaye:  "Could not find the function public.list_ads"
-- Pehle se bane functions ko ye replace kar dega, is liye purana data/functions check kar lein.

create table if not exists public.ads (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid(),
  title text not null check (char_length(title) between 1 and 60),
  detail text default '',
  link text not null,
  comment text default '',
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  likes int not null default 0,
  reports int not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.ad_votes (
  ad_id bigint references public.ads(id) on delete cascade,
  user_id uuid not null default auth.uid(),
  kind text not null check (kind in ('like','report')),
  primary key (ad_id, user_id, kind)
);
create table if not exists public.admins (user_id uuid primary key);   -- apna user id yahan insert karein
alter table public.ads enable row level security;
alter table public.ad_votes enable row level security;
alter table public.admins enable row level security;

create or replace function public.is_admin() returns boolean
language sql security definer set search_path = public as
$$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;

create or replace function public.list_ads()
returns table(id bigint, title text, detail text, link text, comment text, likes int, reports int,
              created_at timestamptz, my_like boolean, my_report boolean, mine boolean)
language sql security definer set search_path = public as $$
  select a.id, a.title, a.detail, a.link, a.comment, a.likes, a.reports, a.created_at,
         exists(select 1 from ad_votes v where v.ad_id=a.id and v.user_id=auth.uid() and v.kind='like'),
         exists(select 1 from ad_votes v where v.ad_id=a.id and v.user_id=auth.uid() and v.kind='report'),
         a.user_id = auth.uid()
  from ads a where a.status='approved' order by a.created_at desc limit 200 $$;

create or replace function public.my_ads()
returns table(id bigint, title text, detail text, link text, comment text, status text, likes int, reports int, created_at timestamptz)
language sql security definer set search_path = public as $$
  select id, title, detail, link, comment, status, likes, reports, created_at
  from ads where user_id = auth.uid() order by created_at desc $$;

create or replace function public.submit_ad(p_title text, p_detail text, p_link text, p_comment text)
returns json language plpgsql security definer set search_path = public as $$
declare st text := 'pending';
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if (p_title||' '||coalesce(p_detail,'')||' '||p_link||' '||coalesce(p_comment,'')) ~* '(porn|xxx|xvideo|xnxx|xhamster|redtube|youporn|hentai|brazzers|nsfw|nude|sexcam|camgirl)' then st := 'rejected'; end if;
  insert into ads(title, detail, link, comment, status) values (left(p_title,60), left(coalesce(p_detail,''),400), p_link, left(coalesce(p_comment,''),50), st);
  return json_build_object('status', st);
end $$;

create or replace function public.vote_ad(p_ad bigint, p_kind text)
returns json language plpgsql security definer set search_path = public as $$
declare r ads; had boolean;
begin
  select * into r from ads where id = p_ad and status='approved';
  if not found then raise exception 'ad not found'; end if;
  if r.user_id = auth.uid() then raise exception 'You cannot vote on your own ad'; end if;
  select exists(select 1 from ad_votes where ad_id=p_ad and user_id=auth.uid() and kind=p_kind) into had;
  if had then delete from ad_votes where ad_id=p_ad and user_id=auth.uid() and kind=p_kind;
  else insert into ad_votes(ad_id,kind) values (p_ad,p_kind); end if;
  update ads set likes   = (select count(*) from ad_votes where ad_id=p_ad and kind='like'),
                 reports = (select count(*) from ad_votes where ad_id=p_ad and kind='report') where id=p_ad returning * into r;
  if r.reports >= 30 then delete from ads where id=p_ad; return json_build_object('deleted', true); end if;
  return json_build_object('likes', r.likes, 'reports', r.reports,
    'my_like',   exists(select 1 from ad_votes where ad_id=p_ad and user_id=auth.uid() and kind='like'),
    'my_report', exists(select 1 from ad_votes where ad_id=p_ad and user_id=auth.uid() and kind='report'), 'deleted', false);
end $$;

create or replace function public.delete_my_ad(p_id bigint) returns void
language sql security definer set search_path = public as $$ delete from ads where id=p_id and user_id=auth.uid() $$;

create or replace function public.admin_list_ads(p_status text)
returns table(id bigint, title text, detail text, link text, comment text, likes int, reports int, created_at timestamptz, email text)
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  return query select a.id, a.title, a.detail, a.link, a.comment, a.likes, a.reports, a.created_at, u.email::text
               from ads a left join auth.users u on u.id=a.user_id where a.status=p_status order by a.created_at desc;
end $$;

create or replace function public.admin_review_ad(p_id bigint, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  update ads set status = case when p_approve then 'approved' else 'rejected' end where id=p_id;
end $$;

create or replace function public.admin_delete_ad(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  delete from ads where id=p_id;
end $$;

grant execute on function public.list_ads(), public.my_ads(), public.submit_ad(text,text,text,text),
  public.vote_ad(bigint,text), public.delete_my_ad(bigint), public.admin_list_ads(text),
  public.admin_review_ad(bigint,boolean), public.admin_delete_ad(bigint) to authenticated;

-- Admin banne ke liye (apna user id Authentication > Users se copy karein):
-- insert into public.admins(user_id) values ('PASTE-YOUR-USER-ID');
