-- J Hunter: ที่เก็บข้อมูลสำหรับซิงก์ข้ามเครื่อง
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งหมดนี้ → Run (รันครั้งเดียว)

create sequence if not exists public.jhunter_rev;

create table if not exists public.jhunter_items (
  space      text   not null,              -- รหัสซิงก์ที่แฮชแล้ว (ไม่เก็บรหัสจริง)
  id         text   not null,              -- id กระดาน หรือ '_meta'
  data       jsonb  not null,
  ts         bigint not null default 0,    -- เวลาที่แก้ (จากเครื่องที่แก้)
  rev        bigint not null default nextval('public.jhunter_rev'),
  updated_at timestamptz not null default now(),
  primary key (space, id)
);
create index if not exists jhunter_items_space_rev on public.jhunter_items (space, rev);

-- ปิดการเข้าถึงตารางตรง ๆ ทั้งหมด ให้เข้าได้ผ่านฟังก์ชันด้านล่างเท่านั้น
alter table public.jhunter_items enable row level security;
revoke all on public.jhunter_items from anon, authenticated;

-- ดึงข้อมูลที่เปลี่ยนหลังจาก rev ที่เคยเห็น
create or replace function public.jh_pull(p_space text, p_since bigint default 0)
returns table (id text, data jsonb, ts bigint, rev bigint)
language plpgsql security definer set search_path = public as $$
begin
  if p_space is null or length(p_space) < 32 then raise exception 'bad space'; end if;
  return query
    select i.id, i.data, i.ts, i.rev from public.jhunter_items i
    where i.space = p_space and i.rev > coalesce(p_since, 0)
    order by i.rev;
end $$;

-- บันทึก 1 รายการ (ทับเฉพาะเมื่อของใหม่ไม่เก่ากว่าของเดิม)
create or replace function public.jh_push(p_space text, p_id text, p_data jsonb, p_ts bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare r bigint;
begin
  if p_space is null or length(p_space) < 32 then raise exception 'bad space'; end if;
  if p_id is null or length(p_id) > 100 then raise exception 'bad id'; end if;
  if pg_column_size(p_data) > 300000 then raise exception 'too large'; end if;
  insert into public.jhunter_items as t (space, id, data, ts)
    values (p_space, p_id, p_data, p_ts)
  on conflict (space, id) do update
    set data = excluded.data, ts = excluded.ts,
        rev = nextval('public.jhunter_rev'), updated_at = now()
    where t.ts <= excluded.ts
  returning t.rev into r;
  return r;
end $$;

revoke all on function public.jh_pull(text, bigint) from public;
revoke all on function public.jh_push(text, text, jsonb, bigint) from public;
grant execute on function public.jh_pull(text, bigint) to anon, authenticated;
grant execute on function public.jh_push(text, text, jsonb, bigint) to anon, authenticated;
