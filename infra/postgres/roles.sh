#!/bin/sh
# Um usuário do PostgreSQL para cada serviço, em vez de todos usarem o superusuário "postgres":
#   api_user    dono do banco "financas" (a API aplica as migrations na subida, então precisa ser o dono)
#   agente_user dono do banco "agente"   (histórico e fila do WhatsApp)
# Cada um só consegue se conectar ao próprio banco. O "postgres" fica para o backup e emergências.
#
# Instalação nova: roda sozinho na primeira subida do banco (montado em /docker-entrypoint-initdb.d).
# Banco que já existe: rode uma vez, e de novo sempre que trocar uma das senhas:
#   docker compose -f docker-compose.prod.yml exec db sh /docker-entrypoint-initdb.d/roles.sh
# Pode rodar quantas vezes quiser: não apaga nada e só troca o dono das tabelas.
set -eu

: "${API_DB_PASSWORD:?defina API_DB_PASSWORD no .env}"
: "${AGENT_DB_PASSWORD:?defina AGENT_DB_PASSWORD no .env}"

run() { psql -v ON_ERROR_STOP=1 --username postgres --no-psqlrc "$@"; }

# Cria os usuários (ou atualiza a senha) e fecha cada banco para quem não é o dono.
run --dbname postgres -v api_pw="$API_DB_PASSWORD" -v agent_pw="$AGENT_DB_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE api_user LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'api_user') \gexec
SELECT 'CREATE ROLE agente_user LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'agente_user') \gexec
ALTER ROLE api_user WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'api_pw';
ALTER ROLE agente_user WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'agent_pw';

ALTER DATABASE financas OWNER TO api_user;
ALTER DATABASE agente OWNER TO agente_user;
REVOKE ALL ON DATABASE financas FROM PUBLIC;
REVOKE ALL ON DATABASE agente FROM PUBLIC;
REVOKE CONNECT ON DATABASE financas FROM agente_user;
REVOKE CONNECT ON DATABASE agente FROM api_user;
SQL

# Dentro de cada banco: o dono do banco passa a ser dono do schema e de tudo que já existe nele.
own_everything() {
  run --dbname "$1" -v owner="$2" <<'SQL'
SELECT format('ALTER SCHEMA %I OWNER TO %I', nspname, :'owner')
  FROM pg_namespace WHERE nspname NOT LIKE 'pg\_%' AND nspname <> 'information_schema' \gexec
SELECT format('ALTER %s %I.%I OWNER TO %I',
              CASE c.relkind WHEN 'S' THEN 'SEQUENCE' WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' ELSE 'TABLE' END,
              n.nspname, c.relname, :'owner')
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE c.relkind IN ('r', 'p', 'v', 'm', 'S')
   AND n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema'
   -- Sequências de colunas serial e identity mudam de dono junto com a tabela.
   AND NOT (c.relkind = 'S' AND EXISTS (SELECT FROM pg_depend d WHERE d.objid = c.oid AND d.deptype IN ('a', 'i')))
   AND pg_get_userbyid(c.relowner) <> :'owner' \gexec
SELECT format('ALTER FUNCTION %s OWNER TO %I', p.oid::regprocedure, :'owner')
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema'
   AND NOT EXISTS (SELECT FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e') \gexec
SQL
}
own_everything financas api_user
own_everything agente agente_user

echo "Usuários do banco prontos: api_user (financas) e agente_user (agente)."
