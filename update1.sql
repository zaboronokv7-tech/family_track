-- Обновление 1: шаблоны задач. Supabase -> SQL Editor -> Run
create table task_templates(id uuid primary key default gen_random_uuid(), family_id uuid not null references families on delete cascade, name text not null, title text not null, description text default '', priority text default 'mid', created_at timestamptz default now());
alter table task_templates enable row level security;
create policy tp1 on task_templates for all to authenticated using(is_member(family_id)) with check(is_member(family_id));
