-- 분석 진단 로그 (내부 QA 전용)
--
-- TestFlight에서는 debugPrint가 어디에도 남지 않아 분석 실패 원인과
-- 파이프라인 중간 지표(검출률/핀존 소스/구속 두 코어 값)를 확인할 수 없다.
-- 성공/실패 양쪽 모두 한 행씩 남겨 표본을 축적한다.
--
-- 적용: Supabase 대시보드 → SQL Editor에 붙여넣고 실행.
-- 공개 배포 전 제거 대상(QA 뱃지·진단 필드와 함께).

create table if not exists public.analysis_debug_logs (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  app_version text,
  device text,
  outcome text not null check (outcome in ('success', 'failure')),
  stage text,
  error text,
  stack text,
  logs text,
  metrics jsonb
);

create index if not exists analysis_debug_logs_user_created_idx
  on public.analysis_debug_logs (user_id, created_at desc);

alter table public.analysis_debug_logs enable row level security;

drop policy if exists "analysis_debug_logs_insert_own" on public.analysis_debug_logs;
create policy "analysis_debug_logs_insert_own"
  on public.analysis_debug_logs for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "analysis_debug_logs_select_own" on public.analysis_debug_logs;
create policy "analysis_debug_logs_select_own"
  on public.analysis_debug_logs for select
  to authenticated
  using (user_id = auth.uid());
