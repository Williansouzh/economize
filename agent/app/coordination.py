"""Coordenação entre instâncias do agente.

- Memória: uma instância só (desenvolvimento e CLI).
- PostgreSQL: várias instâncias atrás de um balanceador. As mensagens repetidas são
  descartadas por uma tabela com chave única, e as mensagens do mesmo telefone são
  serializadas com pg_advisory_lock, que o Postgres libera sozinho se a instância morrer.
"""

import asyncio
import logging
from collections import OrderedDict
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Protocol

log = logging.getLogger(__name__)


class Coordinator(Protocol):
    async def first_time(self, message_id: str) -> bool:
        """True só na primeira vez que o id aparece, em qualquer instância."""
        ...

    def lock(self, phone: str):
        """Context manager assíncrono: uma mensagem por telefone de cada vez."""
        ...


class InMemoryCoordinator:
    def __init__(self, max_ids: int = 5000):
        self._seen: OrderedDict[str, None] = OrderedDict()
        self._max_ids = max_ids
        self._locks: dict[str, asyncio.Lock] = {}

    async def first_time(self, message_id: str) -> bool:
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

    async def first_time(self, message_id: str) -> bool:
        async with self._pool.connection() as conn:
            cur = await conn.execute(
                "INSERT INTO agent_processed_messages (id) VALUES (%s) ON CONFLICT DO NOTHING RETURNING id",
                (message_id,))
            inserted = await cur.fetchone() is not None
            self._inserts += 1
            if self._inserts % 500 == 0:
                await conn.execute(
                    f"DELETE FROM agent_processed_messages WHERE received_at < now() - interval '{self.RETENTION}'")
        return inserted

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
