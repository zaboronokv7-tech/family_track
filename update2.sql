-- Обновление 2: чек-листы, повторы, баллы, покупки, вложения. Supabase -> SQL Editor -> Run
alter table tasks add column checklist jsonb default '[]', add column repeat_rule text, add column points int default 10, add column done_by uuid references profiles;
alter table task_comments add column kind text, add column file_path text;
create table shop_items(id uuid primary key default gen_random_uuid(), family_id uuid not null references families on delete cascade, text text not null, done boolean default false, added_by uuid default auth.uid(), created_at timestamptz default now());
alter table shop_items enable row level security;
create policy s1 on shop_items for all to authenticated using(is_member(family_id)) with check(is_member(family_id));
insert into storage.buckets(id,name,public) values('files','files',false) on conflict do nothing;
create policy files_rw on storage.objects for all to authenticated using(bucket_id='files' and is_member((storage.foldername(name))[1]::uuid)) with check(bucket_id='files' and is_member((storage.foldername(name))[1]::uuid));
alter publication supabase_realtime add table shop_items;
