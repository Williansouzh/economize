"""Coordenação entre instâncias do agente.

- Memória: uma instância só (desenvolvimento e CLI).
- PostgreSQL: várias instâncias atrás de um balanceador.
  * Cada mensagem da Meta é registrada uma vez (chave única); reenvios são descartados.
  * A mensagem fica "processing" até a resposta ser enviada, e então vira "done". Se a instância cair
    no meio, outra reassume depois de PROCESSING_TIMEOUT (até MAX_ATTEMPTS vezes; depois, "failed").
  * Mensagens do mesmo telefone são serializadas com pg_advisory_lock, que o Postgres libera
    sozinho se a instância morrer.
"""

import asyncio
import logging
from collections import OrderedDict
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Protocol

log = logging.getLogger(__name__)


class Coordinator(Protocol):
    async def claim(self, message_id: str, payload: dict) -> bool:
        """True só na primeira vez que o id aparece, em qualquer instância. Marca como em processamento."""
        ...

    async def done(self, message_id: str) -> None:
        """A resposta foi enviada: não reprocessar mais."""
        ...

    async def reclaim_stale(self) -> list[dict]:
        """Payloads de mensagens presas em processamento (instância caiu), já reassumidas por esta instância."""
        ...

    def lock(self, phone: str):
        """Context manager assíncrono: uma mensagem por telefone de cada vez."""
        ...


class InMemoryCoordinator:
    """Uma instância só: se o processo cair, a memória vai junto e não há o que reassumir."""

    def __init__(self, max_ids: int = 5000):
        self._seen: OrderedDict[str, None] = OrderedDict()
        self._max_ids = max_ids
        self._locks: dict[str, asyncio.Lock] = {}

    async def claim(self, message_id: str, payload: dict) -> bool:
        if message_id in self._seen:
            return False
        self._seen[message_id] = None
        if len(self._seen) > self._max_ids:
            self._seen.popitem(last=False)
        return True

    async def done(self, message_id: str) -> None:
        pass

    async def reclaim_stale(self) -> list[dict]:
        return []

    @asynccontextmanager
    async def lock(self, phone: str) -> AsyncIterator[None]:
        async with self._locks.setdefault(phone, asyncio.Lock()):
            yield


class PostgresCoordinator:
    RETENTION = "2 days"

    def __init__(self, data_pool, lock_pool, processing_timeout_s: int = 300, max_attempts: int = 3):
        # Pools separados: as conexões de lock ficam presas enquanto o telefone é processado,
        # e marcar mensagens não pode esperar por elas.
        self._data = data_pool
        self._locks = lock_pool
        self._timeout = processing_timeout_s
        self._max_attempts = max_attempts
        self._claims = 0

    async def setup(self) -> None:
        async with self._data.connection() as conn:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS agent_processed_messages (
                    id text PRIMARY KEY,
                    received_at timestamptz NOT NULL DEFAULT now()
                )""")
            # Colunas novas (versões anteriores só guardavam o id): linhas antigas contam como concluídas.
            await conn.execute("""
                ALTER TABLE agent_processed_messages
                    ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'done',
                    ADD COLUMN IF NOT EXISTS payload jsonb,
                    ADD COLUMN IF NOT EXISTS attempts int NOT NULL DEFAULT 1,
                    ADD COLUMN IF NOT EXISTS started_at timestamptz NOT NULL DEFAULT now()""")
            await conn.execute("""
                CREATE INDEX IF NOT EXISTS agent_processed_messages_processing
                    ON agent_processed_messages (started_at) WHERE status = 'processing'""")

    async def claim(self, message_id: str, payload: dict) -> bool:
        from psycopg.types.json import Jsonb

        async with self._data.connection() as conn:
            cur = await conn.execute("""
                INSERT INTO agent_processed_messages (id, status, payload, attempts, started_at)
                VALUES (%s, 'processing', %s, 1, now())
                ON CONFLICT DO NOTHING RETURNING id""", (message_id, Jsonb(payload)))
            inserted = await cur.fetchone() is not None
            self._claims += 1
            if self._claims % 500 == 0:
                await conn.execute(
                    "DELETE FROM agent_processed_messages WHERE status <> 'processing' "
                    f"AND received_at < now() - interval '{self.RETENTION}'")
        return inserted

    async def done(self, message_id: str) -> None:
        async with self._data.connection() as conn:
            await conn.execute("UPDATE agent_processed_messages SET status = 'done' WHERE id = %s", (message_id,))

    async def reclaim_stale(self) -> list[dict]:
        async with self._data.connection() as conn:
            cur = await conn.execute("""
                UPDATE agent_processed_messages SET status = 'failed'
                WHERE status = 'processing' AND attempts >= %s
                  AND started_at < now() - make_interval(secs => %s)
                RETURNING id""", (self._max_attempts, self._timeout))
            for row in await cur.fetchall():
                log.error("Mensagem %s falhou %s vezes; desistindo.", row["id"], self._max_attempts)

            # SKIP LOCKED: com várias instâncias rodando este laço, cada mensagem presa vai para uma só.
            cur = await conn.execute("""
                WITH stale AS (
                    SELECT id FROM agent_processed_messages
                    WHERE status = 'processing' AND attempts < %s
                      AND started_at < now() - make_interval(secs => %s)
                    ORDER BY started_at LIMIT 20
                    FOR UPDATE SKIP LOCKED)
                UPDATE agent_processed_messages m
                SET attempts = m.attempts + 1, started_at = now()
                FROM stale WHERE m.id = stale.id
                RETURNING m.payload""", (self._max_attempts, self._timeout))
            return [row["payload"] for row in await cur.fetchall() if row["payload"]]

    @asynccontextmanager
    async def lock(self, phone: str) -> AsyncIterator[None]:
        # O lock é da sessão: a mesma conexão precisa ficar reservada até o unlock.
        async with self._locks.connection() as conn:
            await conn.execute("SELECT pg_advisory_lock(hashtextextended(%s, 0))", (phone,))
            try:
                yield
            finally:
                await conn.execute("SELECT pg_advisory_unlock(hashtextextended(%s, 0))", (phone,))


@asynccontextmanager
async def postgres_backend(database_url: str, pool_size: int = 20, processing_timeout_s: int = 300):
    """Abre os pools e devolve (checkpointer, coordinator). Fecha tudo ao sair."""
    from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
    from psycopg.rows import dict_row
    from psycopg_pool import AsyncConnectionPool

    kwargs = {"autocommit": True, "prepare_threshold": 0, "row_factory": dict_row}
    async with (
        AsyncConnectionPool(database_url, max_size=pool_size, kwargs=kwargs, open=False) as data_pool,
        AsyncConnectionPool(database_url, max_size=pool_size, kwargs={"autocommit": True}, open=False) as lock_pool,
    ):
        checkpointer = AsyncPostgresSaver(data_pool)
        await checkpointer.setup()
        coordinator = PostgresCoordinator(data_pool, lock_pool, processing_timeout_s)
        await coordinator.setup()
        log.info("Agente usando PostgreSQL: pode rodar com várias instâncias.")
        yield checkpointer, coordinator
