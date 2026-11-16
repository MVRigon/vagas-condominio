# Vagas do Condomínio

Moradores ofertam vagas de garagem e vizinhos dão lances (por dia ou por mês) em leilão aberto.
Tudo gratuito: página estática (GitHub Pages) + banco/login no plano free do Supabase.

## Como funciona
- Cada morador cria conta com **celular + senha** e informa **bloco/apto**. Os vizinhos só veem bloco/apto; o celular não aparece.
- **Ofertar vaga** (todas cobertas): locação **diária** (um dia específico) ou **mensal** (um mês fechado), lance mínimo opcional e observação.
- Os lances são em R$/dia ou R$/mês, conforme a locação. Quando o dia ou mês passa, a vaga sai da lista sozinha.
- **Lances**: todos veem o maior lance e o histórico. O banco garante que cada lance seja maior que o anterior, que ninguém dê lance na própria vaga e que vaga encerrada não receba lance.
- O dono **encerra** a vaga quando fechar negócio (pode reabrir ou excluir depois). O acerto final é direto entre os vizinhos.

## Publicar (≈ 15 min, uma vez só)

### 1. Supabase (banco + login)
1. Crie conta em https://supabase.com → **New project** (região São Paulo; guarde a senha do banco).
2. **SQL Editor → New query** → cole o conteúdo de `supabase/schema.sql` → **Run**.
3. **Authentication → Sign In / Providers → Email**: desligue **Confirm email**.
   Obrigatório: o login por celular usa um e-mail técnico por trás (o Supabase grátis não envia SMS), então não há e-mail para confirmar.
4. **Project Settings → API**: copie **Project URL** e a chave **anon public** para o `config.js`.
   Ajuste também `NOME_CONDOMINIO`.

### 2. GitHub Pages (a página)
1. Crie um repositório **público** numa conta pessoal do GitHub (ex.: `vagas-condominio`) e suba `index.html`, `config.js` e a pasta `supabase/`.
2. **Settings → Pages → Source: Deploy from a branch → main / (root)**.
3. Em ~1 min o link fica no ar: `https://<seu-usuario>.github.io/vagas-condominio/`. Mande no grupo do condomínio.

> A chave *anon* no `config.js` é pública por design — quem protege os dados são as regras de RLS do `schema.sql`
> (só usuário logado lê; cada um só altera o que é seu).

## Testar no computador antes
Com o Docker ligado: `npx supabase start` (aplica o schema) e crie `config.local.js` igual ao `config.js`, com a URL `http://127.0.0.1:54321` e a anon key que o `npx supabase status` mostra. Esse arquivo não vai para o git e só é usado em localhost.
Abra a pasta e rode `npx serve .` (ou `python -m http.server`) e acesse `http://localhost:3000` / `:8000`.

## Limites conhecidos
- O celular não é verificado por SMS (seria pago). Esqueceu a senha: o administrador apaga a conta em **Authentication → Users** e a pessoa se cadastra de novo.
- Qualquer pessoa com o link pode criar conta. Se aparecer gente de fora, dá para exigir um "código do condomínio" no cadastro.
- Projeto free do Supabase **pausa após 7 dias sem nenhum acesso**; basta entrar no painel e clicar em *Restore*.
- A lista atualiza sozinha a cada 30 s.
