-- Administradores: podem encerrar, reabrir e excluir qualquer vaga e apagar lances.
-- O login por celular vira o e-mail técnico 55<DDD><número>@celular.vagas-condominio.app.

create table if not exists public.admins (
  email text primary key
);
alter table public.admins enable row level security;  -- ninguém lê/escreve pela API

-- Para tornar alguém admin, rode no SQL Editor do Supabase (não versionar o número):
--   insert into public.admins (email) values ('55<DDD><número>@celular.vagas-condominio.app');

create or replace function public.sou_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins a where a.email = (auth.jwt() ->> 'email'));
$$;

grant execute on function public.sou_admin() to authenticated;

drop policy if exists "vagas: dono altera" on public.vagas;
drop policy if exists "vagas: dono exclui" on public.vagas;

create policy "vagas: dono ou admin altera" on public.vagas
  for update to authenticated
  using (dono_id = auth.uid() or public.sou_admin())
  with check (dono_id = auth.uid() or public.sou_admin());

create policy "vagas: dono ou admin exclui" on public.vagas
  for delete to authenticated
  using (dono_id = auth.uid() or public.sou_admin());

create policy "lances: admin exclui" on public.lances
  for delete to authenticated
  using (public.sou_admin());
