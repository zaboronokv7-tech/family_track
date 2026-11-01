-- Обновление 3: наблюдатели из друзей, итоги в чате, смена дедлайна. Supabase -> SQL Editor -> Run
alter table task_comments add column is_result boolean default false;
create function is_watcher(tid uuid) returns boolean language sql security definer stable set search_path=public as $$ select exists(select 1 from task_watchers where task_id=tid and user_id=auth.uid()) $$;
create function task_member(tid uuid) returns boolean language sql security definer stable set search_path=public as $$ select exists(select 1 from tasks t where t.id=tid and is_member(t.family_id)) $$;
create or replace function task_ok(tid uuid) returns boolean language sql security definer stable set search_path=public as $$ select task_member(tid) or is_watcher(tid) $$;
create policy t2 on tasks for select to authenticated using(is_watcher(id));
drop policy w1 on task_watchers;
create policy w_sel on task_watchers for select to authenticated using(task_ok(task_id));
create policy w_ins on task_watchers for insert to authenticated with check(task_member(task_id));
create policy w_del on task_watchers for delete to authenticated using(task_member(task_id));
create policy c3 on task_comments for update to authenticated using(task_ok(task_id));
create or replace function log_task() returns trigger language plpgsql security definer set search_path=public as $$
begin
if tg_op='INSERT' then insert into task_events(task_id,text) values(new.id,'создал(а) задачу'); return new; end if;
if new.status<>old.status then insert into task_events(task_id,text) values(new.id,'статус: '||case new.status when 'new' then 'Новая' when 'work' then 'В работе' when 'review' then 'На проверке' else 'Закрыта' end); end if;
if new.deadline is distinct from old.deadline then insert into task_events(task_id,text) values(new.id,'изменил(а) дедлайн'); end if;
return new; end $$;
