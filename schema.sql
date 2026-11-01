-- Семейные задачи: вставьте целиком в Supabase -> SQL Editor -> Run
create table profiles(id uuid primary key references auth.users on delete cascade, email text unique not null, name text not null);
create table families(id uuid primary key default gen_random_uuid(), name text not null, owner uuid not null default auth.uid() references profiles, created_at timestamptz default now());
create table family_members(family_id uuid references families on delete cascade, user_id uuid references profiles on delete cascade, primary key(family_id,user_id));
create table invitations(id uuid primary key default gen_random_uuid(), family_id uuid references families on delete cascade, family_name text, email text not null, invited_by uuid default auth.uid(), status text default 'pending', created_at timestamptz default now());
create table friendships(id uuid primary key default gen_random_uuid(), requester uuid not null default auth.uid() references profiles, addressee_email text not null, status text default 'pending', unique(requester,addressee_email));
create table tasks(id uuid primary key default gen_random_uuid(), family_id uuid not null references families on delete cascade, title text not null, description text default '', author uuid default auth.uid() references profiles, assignee uuid references profiles, deadline timestamptz, priority text default 'mid', status text default 'new', created_at timestamptz default now());
create table task_watchers(task_id uuid references tasks on delete cascade, user_id uuid references profiles, primary key(task_id,user_id));
create table task_comments(id uuid primary key default gen_random_uuid(), task_id uuid not null references tasks on delete cascade, user_id uuid default auth.uid(), body text not null, created_at timestamptz default now());
create table task_events(id uuid primary key default gen_random_uuid(), task_id uuid not null references tasks on delete cascade, user_id uuid default auth.uid(), text text, created_at timestamptz default now());

create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into profiles values(new.id,lower(new.email),coalesce(new.raw_user_meta_data->>'name',split_part(new.email,'@',1))); return new; end $$;
create trigger on_auth_user after insert on auth.users for each row execute function handle_new_user();

create function add_owner() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into family_members values(new.id,new.owner); return new; end $$;
create trigger on_family after insert on families for each row execute function add_owner();

create function is_member(fid uuid) returns boolean language sql security definer stable set search_path=public as $$
select exists(select 1 from family_members where family_id=fid and user_id=auth.uid()) $$;
create function task_ok(tid uuid) returns boolean language sql security definer stable set search_path=public as $$
select exists(select 1 from tasks t where t.id=tid and is_member(t.family_id)) $$;

create function accept_invitation(inv uuid) returns void language plpgsql security definer set search_path=public as $$
declare i invitations; begin
select * into i from invitations where id=inv and status='pending' and lower(email)=lower(auth.jwt()->>'email');
if not found then raise exception 'Приглашение не найдено'; end if;
insert into family_members values(i.family_id,auth.uid()) on conflict do nothing;
update invitations set status='accepted' where id=inv; end $$;

create function log_task() returns trigger language plpgsql security definer set search_path=public as $$
begin
if tg_op='INSERT' then insert into task_events(task_id,text) values(new.id,'создал(а) задачу');
elsif new.status<>old.status then insert into task_events(task_id,text) values(new.id,'статус: '||case new.status when 'new' then 'Новая' when 'work' then 'В работе' when 'review' then 'На проверке' else 'Закрыта' end);
end if; return new; end $$;
create trigger t_log after insert or update on tasks for each row execute function log_task();

alter table profiles enable row level security; alter table families enable row level security;
alter table family_members enable row level security; alter table invitations enable row level security;
alter table friendships enable row level security; alter table tasks enable row level security;
alter table task_watchers enable row level security; alter table task_comments enable row level security;
alter table task_events enable row level security;

create policy p1 on profiles for select to authenticated using(true);
create policy p2 on profiles for update to authenticated using(id=auth.uid());
create policy f1 on families for select to authenticated using(is_member(id));
create policy f2 on families for insert to authenticated with check(owner=auth.uid());
create policy f3 on families for delete to authenticated using(owner=auth.uid());
create policy m1 on family_members for select to authenticated using(is_member(family_id));
create policy m2 on family_members for delete to authenticated using(user_id=auth.uid());
create policy i1 on invitations for select to authenticated using(lower(email)=lower(auth.jwt()->>'email') or invited_by=auth.uid());
create policy i2 on invitations for insert to authenticated with check(invited_by=auth.uid() and is_member(family_id));
create policy i3 on invitations for update to authenticated using(lower(email)=lower(auth.jwt()->>'email'));
create policy r1 on friendships for select to authenticated using(requester=auth.uid() or lower(addressee_email)=lower(auth.jwt()->>'email'));
create policy r2 on friendships for insert to authenticated with check(requester=auth.uid());
create policy r3 on friendships for update to authenticated using(lower(addressee_email)=lower(auth.jwt()->>'email'));
create policy t1 on tasks for all to authenticated using(is_member(family_id)) with check(is_member(family_id));
create policy w1 on task_watchers for all to authenticated using(task_ok(task_id)) with check(task_ok(task_id));
create policy c1 on task_comments for select to authenticated using(task_ok(task_id));
create policy c2 on task_comments for insert to authenticated with check(task_ok(task_id) and user_id=auth.uid());
create policy e1 on task_events for select to authenticated using(task_ok(task_id));

alter publication supabase_realtime add table tasks, task_comments, task_events, invitations, friendships, profiles;
