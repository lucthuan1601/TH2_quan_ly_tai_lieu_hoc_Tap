alter table public.users enable row level security;
alter table public.documents enable row level security;
alter table public.document_permissions enable row level security;

-- Firebase users are authenticated by documents-api, not by Supabase Auth.
-- The Edge Function uses the service role and performs the owner/permission checks.
-- No anonymous or Supabase-authenticated client receives direct table access.
revoke all on public.users from anon, authenticated;
revoke all on public.documents from anon, authenticated;
revoke all on public.document_permissions from anon, authenticated;

insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do update set public = false;
