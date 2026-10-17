-- Executado só na primeira subida do container (volume vazio).
-- O banco "financas" (da API) é criado pela variável POSTGRES_DB; aqui criamos o do agente.
CREATE DATABASE agente;
