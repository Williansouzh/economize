"""Coordenação entre instâncias do agente.

- Memória: uma instância só (desenvolvimento e CLI).
- PostgreSQL: várias instâncias atrás de um balanceador. As mensagens repetidas são
  descartadas por uma tabela com chave única, e as mensagens do mesmo telefone são
  serializadas com pg_advisory_lock, que o Postgres libera sozinho se a instância morrer.
  A tabela guarda também o conteúdo de cada mensagem e quando ela foi concluída: se uma
  instância cair no meio do processamento, outra pega a mensagem de volta (claim_stale).
"""

import asyncio
import logging
from collections import OrderedDict
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any, Protocol

log = logging.getLogger(__name__)


class Coordinator(Protocol):
    async def first_time(self, message_id: str, payload: dict[str, Any] | None = None) -> bool:
        """True só na primeira vez que o id aparece, em qualquer instância."""
        ...

    def lock(self, phone: str):
        """Context manager assíncrono: uma mensagem por telefone de cada vez."""
        ...

    async def started(self, message_id: str) -> None:
        """A mensagem saiu da fila do telefone e começou a ser processada."""
        ...

    async def done(self, message_id: str) -> None:
        """A mensagem foi processada e respondida: não precisa ser retomada."""
        ...

    async def claim_stale(self, older_than_seconds: int, max_attempts: int) -> list[dict[str, Any]]:
        """Pega para esta instância as mensagens abandonadas por uma instância que caiu."""
        ...

    async def forget(self, phone: str) -> None:
        """Apaga as mensagens guardadas desse número (RN-30)."""
        ...


class InMemoryCoordinator:
    def __init__(self, max_ids: int = 5000):
        self._seen: OrderedDict[str, None] = OrderedDict()
        self._max_ids = max_ids
        self._locks: dict[str, asyncio.Lock] = {}

    async def first_time(self, message_id: str, payload: dict[str, Any] | None = None) -> bool:
        if message_id in self._seen:
            return False
        self._seen[message_id] = None
        if len(self._seen) > self._max_ids:
            self._seen.popitem(last=False)
        return True

    @asynccontextmanager
    async def lock(self, phone: str) -> AsyncIterator[None]:
        async with self._locks.setdefault(phone, asyncio.Lock()):
            yield

    # Com uma instância só, se o processo cair a memória vai junto: não há o que retomar.
    async def started(self, message_id: str) -> None:
        pass

    async def done(self, message_id: str) -> None:
        pass

    async def claim_stale(self, older_than_seconds: int, max_attempts: int) -> list[dict[str, Any]]:
        return []

    async def forget(self, phone: str) -> None:
        pass  # só guarda ids, sem conteúdo


class PostgresCoordinator:
    # Ids da Meta ficam guardados por 2 dias; reenvios acontecem em minutos.
    RETENTION = "2 days"

    def __init__(self, pool):
        self._pool = pool  # psycopg_pool.AsyncConnectionPool com autocommit
        self._inserts = 0

    async def setup(self) -> None:
        async with self._pool.connection() as conn:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS agent_processed_messages (
                    id text PRIMARY KEY,
                    received_at timestamptz NOT NULL DEFAULT now()
                )""")
            # Colunas da retomada. Linhas antigas ficam sem payload e nunca são retomadas.
            await conn.execute("""
                ALTER TABLE agent_processed_messages
                    ADD COLUMN IF NOT EXISTS payload jsonb,
                    ADD COLUMN IF NOT EXISTS started_at timestamptz NOT NULL DEFAULT now(),
                    ADD COLUMN IF NOT EXISTS attempts int NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS done_at timestamptz""")

    async def first_time(self, message_id: str, payload: dict[str, Any] | None = None) -> bool:
        from psycopg.types.json import Jsonb

        async with self._pool.connection() as conn:
            cur = await conn.execute(
                "INSERT INTO agent_processed_messages (id, payload) VALUES (%s, %s) "
                "ON CONFLICT DO NOTHING RETURNING id",
                (message_id, Jsonb(payload) if payload is not None else None))
            inserted = await cur.fetchone() is not None
            self._inserts += 1
            if self._inserts % 500 == 0:
                await conn.execute(
                    f"DELETE FROM agent_processed_messages WHERE received_at < now() - interval '{self.RETENTION}'")
        return inserted

    async def started(self, message_id: str) -> None:
        async with self._pool.connection() as conn:
            await conn.execute(
                "UPDATE agent_processed_messages SET started_at = now(), attempts = attempts + 1 WHERE id = %s",
                (message_id,))

    async def done(self, message_id: str) -> None:
        async with self._pool.connection() as conn:
            await conn.execute("UPDATE agent_processed_messages SET done_at = now() WHERE id = %s", (message_id,))

    async def claim_stale(self, older_than_seconds: int, max_attempts: int) -> list[dict[str, Any]]:
        # SKIP LOCKED: duas instâncias procurando ao mesmo tempo nunca pegam a mesma mensagem.
        # started_at é renovado na hora, então quem pegou tem o mesmo prazo para terminar.
        async with self._pool.connection() as conn:
            cur = await conn.execute("""
                UPDATE agent_processed_messages SET started_at = now()
                WHERE id IN (
                    SELECT id FROM agent_processed_messages
                    WHERE done_at IS NULL AND payload IS NOT NULL AND attempts < %s
                      AND started_at < now() - make_interval(secs => %s)
                    ORDER BY received_at
                    LIMIT 20
                    FOR UPDATE SKIP LOCKED)
                RETURNING payload""", (max_attempts, older_than_seconds))
            return [row[0] for row in await cur.fetchall()]

    async def forget(self, phone: str) -> None:
        async with self._pool.connection() as conn:
            await conn.execute("DELETE FROM agent_processed_messages WHERE payload->>'phone' = %s", (phone,))

    @asynccontextmanager
    async def lock(self, phone: str) -> AsyncIterator[None]:
        # O lock é da sessão: a mesma conexão precisa ficar reservada até o unlock.
        async with self._pool.connection() as conn:
            await conn.execute("SELECT pg_advisory_lock(hashtextextended(%s, 0))", (phone,))
            try:
                yield
            finally:
                await conn.execute("SELECT pg_advisory_unlock(hashtextextended(%s, 0))", (phone,))


@asynccontextmanager
async def postgres_backend(database_url: str, pool_size: int = 20):
    """Abre os pools e devolve (checkpointer, coordinator). Fecha tudo ao sair."""
    from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
    from psycopg.rows import dict_row
    from psycopg_pool import AsyncConnectionPool

    kwargs = {"autocommit": True, "prepare_threshold": 0, "row_factory": dict_row}
    # Pools separados: cada telefone em processamento segura uma conexão de lock
    # enquanto o grafo usa outras para o checkpointer.
    async with (
        AsyncConnectionPool(database_url, max_size=pool_size, kwargs=kwargs, open=False) as graph_pool,
        AsyncConnectionPool(database_url, max_size=pool_size, kwargs={"autocommit": True}, open=False) as lock_pool,
    ):
        checkpointer = AsyncPostgresSaver(graph_pool)
        await checkpointer.setup()
        coordinator = PostgresCoordinator(lock_pool)
        await coordinator.setup()
        log.info("Agente usando PostgreSQL: pode rodar com várias instâncias.")
        yield checkpointer, coordinator
