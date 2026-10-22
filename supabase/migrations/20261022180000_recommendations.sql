create table public.document_tags (
  document_id uuid not null references public.documents(id) on delete cascade,
  tag text not null check (length(tag) between 1 and 40),
  primary key (document_id, tag)
);

create table public.document_interactions (
  id bigint generated always as identity primary key,
  user_id text not null references public.users(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  action text not null check (action in ('view', 'search', 'save', 'borrow')),
  created_at timestamptz not null default now()
);

create index document_interactions_user_time_idx
  on public.document_interactions (user_id, created_at desc);

create table public.user_fcm_tokens (
  token text primary key,
  user_id text not null references public.users(id) on delete cascade,
  updated_at timestamptz not null default now()
);
create index user_fcm_tokens_user_idx on public.user_fcm_tokens(user_id);

alter table public.document_tags enable row level security;
alter table public.document_interactions enable row level security;
alter table public.user_fcm_tokens enable row level security;
revoke all on public.document_tags, public.document_interactions,
  public.user_fcm_tokens from anon, authenticated;
