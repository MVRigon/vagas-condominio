-- Vagas do Condomínio — schema do Supabase
-- Rodar inteiro no Supabase: SQL Editor → New query → colar → Run.

-- ---------------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------------

create table public.perfis (
  id        uuid primary key references auth.users(id) on delete cascade,
  bloco     text not null check (length(trim(bloco)) between 1 and 10),
  apto      text not null check (length(trim(apto)) between 1 and 10),
  criado_em timestamptz not null default now()
);

create table public.vagas (
  id           bigint generated always as identity primary key,
  dono_id      uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  modalidade   text not null check (modalidade in ('diaria', 'mensal')),
  -- diária: o dia locado · mensal: dia 1 do mês locado
  data_ref     date not null check (modalidade <> 'mensal' or extract(day from data_ref) = 1),
  lance_minimo numeric(10,2) not null default 0 check (lance_minimo >= 0),
  observacao   text check (length(observacao) <= 300),
  status       text not null default 'aberta' check (status in ('aberta', 'encerrada')),
  criado_em    timestamptz not null default now()
);

create table public.lances (
  id         bigint generated always as identity primary key,
  vaga_id    bigint not null references public.vagas(id) on delete cascade,
  usuario_id uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  valor      numeric(10,2) not null check (valor > 0 and valor < 100000),
  criado_em  timestamptz not null default now()
);

create index lances_vaga_valor_idx on public.lances (vaga_id, valor desc);
create index vagas_status_idx on public.vagas (status, data_ref);

-- ---------------------------------------------------------------------------
-- Período da vaga: último dia em que ela vale (hoje no fuso de Brasília)
-- ---------------------------------------------------------------------------

create or replace function public.fim_periodo(v public.vagas)
returns date language sql immutable as $$
  select case when v.modalidade = 'diaria' then v.data_ref
              else (v.data_ref + interval '1 month' - interval '1 day')::date end;
$$;

create or replace function public.hoje_br()
returns date language sql stable as $$
  select (now() at time zone 'America/Sao_Paulo')::date;
$$;

create or replace function public.validar_vaga()
returns trigger language plpgsql as $$
begin
  if new.modalidade = 'mensal' then
    new.data_ref := date_trunc('month', new.data_ref)::date;
  end if;
  if public.fim_periodo(new) < public.hoje_br() then
    raise exception 'Escolha um dia ou mês que ainda não passou.';
  end if;
  return new;
end;
$$;

create trigger trg_validar_vaga
  before insert on public.vagas
  for each row execute function public.validar_vaga();

-- ---------------------------------------------------------------------------
-- Regras do leilão (valem mesmo que alguém tente burlar a página)
-- ---------------------------------------------------------------------------

create or replace function public.validar_lance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v     public.vagas;
  maior numeric;
begin
  -- trava a vaga: dois lances simultâneos são avaliados um de cada vez
  select * into v from public.vagas where id = new.vaga_id for update;

  if not found then
    raise exception 'Vaga não encontrada.';
  end if;
  if v.status <> 'aberta' then
    raise exception 'Esta vaga não está mais recebendo lances.';
  end if;
  if public.fim_periodo(v) < public.hoje_br() then
    raise exception 'O período desta vaga já passou.';
  end if;
  if v.dono_id = new.usuario_id then
    raise exception 'Você não pode dar lance na sua própria vaga.';
  end if;
  if new.valor < v.lance_minimo then
    raise exception 'O lance mínimo desta vaga é R$ %.', replace(to_char(v.lance_minimo, 'FM999990.00'), '.', ',');
  end if;

  select max(valor) into maior from public.lances where vaga_id = new.vaga_id;
  if maior is not null and new.valor <= maior then
    raise exception 'O lance precisa ser maior que o atual (R$ %).', replace(to_char(maior, 'FM999990.00'), '.', ',');
  end if;

  new.criado_em := now();
  return new;
end;
$$;

create trigger trg_validar_lance
  before insert on public.lances
  for each row execute function public.validar_lance();

-- ---------------------------------------------------------------------------
-- Segurança (RLS): só moradores logados leem; cada um só altera o que é seu
-- ---------------------------------------------------------------------------

alter table public.perfis enable row level security;
alter table public.vagas  enable row level security;
alter table public.lances enable row level security;

create policy "perfis: leitura" on public.perfis
  for select to authenticated using (true);
create policy "perfis: cria o próprio" on public.perfis
  for insert to authenticated with check (id = auth.uid());
create policy "perfis: edita o próprio" on public.perfis
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy "vagas: leitura" on public.vagas
  for select to authenticated using (true);
create policy "vagas: oferta a própria" on public.vagas
  for insert to authenticated with check (dono_id = auth.uid());
create policy "vagas: dono altera" on public.vagas
  for update to authenticated using (dono_id = auth.uid()) with check (dono_id = auth.uid());
create policy "vagas: dono exclui" on public.vagas
  for delete to authenticated using (dono_id = auth.uid());

create policy "lances: leitura" on public.lances
  for select to authenticated using (true);
create policy "lances: dá o próprio" on public.lances
  for insert to authenticated with check (usuario_id = auth.uid());
-- lance não pode ser editado nem apagado (leilão aberto, histórico fica visível)

-- ---------------------------------------------------------------------------
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
