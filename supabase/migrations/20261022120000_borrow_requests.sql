-- Mục 4: Chia sẻ và mượn tài liệu (Trần Văn Hồng Quân)

-- Quyền có thời hạn: dùng cho tài liệu được mượn.
alter table public.document_permissions
  add column if not exists expires_at timestamptz,
  add column if not exists source text not null default 'share'
    check (source in ('share', 'borrow'));

create table if not exists public.borrow_requests (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete cascade,
  requester_id text not null references public.users(id),
  owner_id text not null references public.users(id),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'returned', 'expired')),
  message text,
  borrow_from timestamptz not null default now(),
  borrow_until timestamptz not null,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (borrow_until > borrow_from)
);

create index if not exists borrow_requests_owner_idx
  on public.borrow_requests (owner_id, status);
create index if not exists borrow_requests_requester_idx
  on public.borrow_requests (requester_id, status);
-- Mỗi người chỉ có 1 yêu cầu pending cho 1 tài liệu.
create unique index if not exists borrow_requests_one_pending
  on public.borrow_requests (document_id, requester_id)
  where status = 'pending';

alter table public.borrow_requests enable row level security;
revoke all on public.borrow_requests from anon, authenticated;
